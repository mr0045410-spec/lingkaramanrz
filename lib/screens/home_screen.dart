import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/loud_signal_service.dart';
import '../services/phone_protection_service.dart';
import '../services/oem_security_service.dart';
import '../services/sos_trigger_service.dart';
import '../services/sound_settings_service.dart';
import '../services/fall_detection_service.dart';
import '../services/safety_timer_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/member_nickname_service.dart';
import '../services/supabase_service.dart';
import 'circle_screen.dart';
import 'chat_screen.dart';
import 'lost_mode_screen.dart';
import 'map_view.dart';
import 'profile_screen.dart';
import 'sos_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onSignedOut;
  const HomeScreen({super.key, required this.onSignedOut});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final SupabaseService _supa = SupabaseService();
  final LocationService _locService = LocationService();
  final AudioService _audioService = AudioService();
  final SosTriggerService _sosTriggerService = SosTriggerService();
  final LoudSignalService _loudSignalService = LoudSignalService();
  final GeofenceService _geofenceService = GeofenceService();
  final PhoneProtectionService _phoneProtectionService = PhoneProtectionService();
  final SafetyTimerService _safetyTimerService = SafetyTimerService();
  StreamSubscription<int>? _safetyTimerSub;

  StreamSubscription<void>? _sosTriggerSub;
  StreamSubscription<LoudSignalModel>? _incomingSignalSub;
  StreamSubscription<String>? _signalStoppedSub;
  StreamSubscription<GeofenceTransition>? _geofenceTransitionSub;
  StreamSubscription<IntruderAlertModel>? _intruderAlertSub;
  StreamSubscription<LastBreathBeaconModel>? _lastBreathSub;
  StreamSubscription<bool>? _gpsStatusSub;
  StreamSubscription<LostModeCommand>? _lostModeSub;
  StreamSubscription<void>? _fallSub;
  bool _isFallDialogShowing = false;
  Timer? _alertRefreshTimer;
  bool _isLostModeScreenOpen = false;
  bool _isAccessibilityEnabled = true;
  bool _dismissedAccessibilityBanner = false;

  Future<void> _showFallEmergencyDialog() async {
    if (_isFallDialogShowing || !mounted) return;
    _isFallDialogShowing = true;

    int secondsRemaining = 15;
    Timer? countdownTimer;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (secondsRemaining > 1) {
                setDialogState(() {
                  secondsRemaining--;
                });
              } else {
                timer.cancel();
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop(true);
                }
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF1E212B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'BENTURAN / JATUH KERAS TERDETEKSI!',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.shade900.withValues(alpha: 0.3),
                      border: Border.all(color: Colors.redAccent, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$secondsRemaining',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ponsel mendeteksi guncangan/benturan keras. Mengirim sinyal SOS darurat ke keluarga jika tidak ada respons.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'SAYA BAIK-BAIK SAJA (BATAL)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: () {
                      countdownTimer?.cancel();
                      Navigator.of(dialogCtx).pop(false);
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((triggered) async {
      countdownTimer?.cancel();
      _isFallDialogShowing = false;
      if (triggered == true && mounted) {
        final pos = await _locService.getCurrentLocation();
        await _supa.triggerSOS(
          latitude: pos?.latitude ?? 0.0,
          longitude: pos?.longitude ?? 0.0,
          circleId: _selectedCircle?.id,
          customMessage: '🚨 DARURAT OTOMATIS: Pengguna mengalami benturan/jatuh keras dan tidak merespons!',
        );
        _loadActiveAlerts();
        setState(() => _currentIndex = 2);
      }
    });
  }

  void _openLostModeScreen(LostModeCommand cmd) {
    if (_isLostModeScreenOpen || !mounted) return;
    _isLostModeScreenOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LostModeScreen(command: cmd),
          ),
        )
        .then((_) {
          _isLostModeScreenOpen = false;
        });
  }

  void _closeLostModeScreen() {
    if (_isLostModeScreenOpen && mounted) {
      _isLostModeScreenOpen = false;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  int _currentIndex = 0;
  int _unreadChatCount = 0;
  List<CircleModel> _circles = [];
  CircleModel? _selectedCircle;
  List<SosAlert> _activeAlerts = [];
  bool _isLoading = true;
  LoudSignalModel? _incomingRingingSignal;
  final List<RealtimeChannel> _chatChannels = [];
  StreamSubscription? _openChatSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccessibilityStatus();
    _initialize();
  }

  @override
  void dispose() {
    for (var ch in _chatChannels) {
      ch.unsubscribe();
    }
    _chatChannels.clear();
    _gpsStatusSub?.cancel();
    _lostModeSub?.cancel();
    _safetyTimerSub?.cancel();
    _fallSub?.cancel();
    _alertRefreshTimer?.cancel();
    _openChatSub?.cancel();
    _audioService.stopListening();
    _sosTriggerSub?.cancel();
    _incomingSignalSub?.cancel();
    _signalStoppedSub?.cancel();
    _geofenceTransitionSub?.cancel();
    _intruderAlertSub?.cancel();
    _lastBreathSub?.cancel();
    _loudSignalService.stopListening();
    _geofenceService.stopListening();
    _phoneProtectionService.stopListening();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibilityStatus();
    }
  }

  Future<void> _checkAccessibilityStatus() async {
    try {
      final enabled = await OemSecurityService.instance.isAccessibilityServiceEnabled();
      if (mounted) {
        setState(() => _isAccessibilityEnabled = enabled);
      }
    } catch (_) {}
  }

  Future<void> _promptEnableAccessibility() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.shield, color: Colors.deepOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Proteksi Kunci Daya & Status Bar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Agar pencuri tidak bisa menarik Status Bar ke bawah, membuka Pengaturan HP, mematikan koneksi data, atau mematikan HP secara paksa saat Mode Hilang aktif, silakan aktifkan Layanan Aksesibilitas LingkarAman.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Petunjuk di Pengaturan:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              '1. Pilih "Proteksi Anti-Matikan Daya (LingkarAman)".\n2. Aktifkan sakelar (switch) lalu pilih "Izinkan / Allow".',
              style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti Saja'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await OemSecurityService.instance.openAccessibilitySettings();
            },
            child: const Text('Buka Pengaturan HP'),
          ),
        ],
      ),
    );
    await _checkAccessibilityStatus();
  }

  Future<void> _initialize() async {
    // Inisialisasi Nama Panggilan & Notifikasi
    unawaited(MemberNicknameService.instance.init());
    Permission.notification.request();

    final soundSettings = SoundSettingsService();
    soundSettings.initChatNotificationListener();
    _openChatSub = soundSettings.onOpenChatTriggered.listen((_) {
      if (mounted) {
        setState(() => _currentIndex = 2);
      }
    });
    soundSettings.getInitialOpenChatTrigger().then((triggered) {
      if (triggered && mounted) {
        setState(() => _currentIndex = 2);
      }
    });

    // 1. Prioritaskan render UI peta & lingkaran secepat mungkin
    try {
      await Future.wait([
        _loadCircles().timeout(const Duration(seconds: 3)),
        _loadActiveAlerts().timeout(const Duration(seconds: 3)),
      ]);
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (_selectedCircle != null) {
      _geofenceService.subscribeToCircleEvents(_selectedCircle!.id);
    }

    // 2. Jalankan background services & triggers secara non-blocking
    _sosTriggerService.initialize().then((_) {
      _sosTriggerSub = _sosTriggerService.onSosTriggered.listen((_) {
        if (mounted) {
          _loadActiveAlerts();
          setState(() => _currentIndex = 2);
        }
      });
    });

    _fallSub = FallDetectionService().onFallDetected.listen((_) {
      if (mounted) {
        _showFallEmergencyDialog();
      }
    });

    // Start live location streaming & battery tracking (Foreground Service & Doze resistant)
    unawaited(_locService.startTracking());

    // Start GPS service status listener and check initial state
    _locService.startGpsListener();
    _gpsStatusSub = _locService.onGpsStatusChanged.listen((enabled) {
      if (!enabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFC62828),
            duration: const Duration(seconds: 8),
            content: Row(
              children: const [
                Icon(Icons.location_off, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'GPS/Lokasi dimatikan. Nyalakan agar posisi Anda terdeteksi.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'NYALAKAN',
              textColor: Colors.yellowAccent,
              onPressed: () => _locService.openGpsSettings(),
            ),
          ),
        );
      }
    });

    // Check GPS & Battery Optimization di background
    _locService.checkGpsStatus().then((isGpsOn) {
      if (!isGpsOn && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFC62828),
            duration: const Duration(seconds: 8),
            content: Row(
              children: const [
                Icon(Icons.location_off, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'GPS/Lokasi belum dinyalakan. Nyalakan agar fitur pelacakan aktif.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'NYALAKAN',
              textColor: Colors.yellowAccent,
              onPressed: () => _locService.openGpsSettings(),
            ),
          ),
        );
      }
    });

    // Check Battery Optimization (Anti-Kill OS)
    final batteryService = BatteryOptimizationService();
    batteryService.isIgnoringBatteryOptimizations().then((isBatteryIgnored) async {
      if (!isBatteryIgnored && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final hasPrompted = prefs.getBool('battery_optimization_prompted') ?? false;
        if (!hasPrompted) {
          await prefs.setBool('battery_optimization_prompted', true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xFF1E293B),
                duration: const Duration(seconds: 10),
                content: Row(
                  children: const [
                    Icon(Icons.battery_alert, color: Colors.amberAccent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Agar pelacakan tidak mati saat HP di saku, izinkan proteksi latar belakang.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                action: SnackBarAction(
                  label: 'IZINKAN',
                  textColor: Colors.amberAccent,
                  onPressed: () => batteryService.requestIgnoreBatteryOptimizations(),
                ),
              ),
            );
          }
        }
      }
    });

    // Start background ambient audio request listener
    _audioService.startListeningForRequests();

    // Start background loud signal listener (bypassing DND)
    _loudSignalService.startListening();
    _incomingSignalSub = _loudSignalService.onIncomingSignal.listen((signal) {
      if (mounted) {
        setState(() => _incomingRingingSignal = signal);
        _showLoudAlarmDialog(signal);
      }
    });
    _signalStoppedSub = _loudSignalService.onSignalStopped.listen((signalId) {
      if (mounted && _incomingRingingSignal?.id == signalId) {
        setState(() => _incomingRingingSignal = null);
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });

    // Start geofence transition alerts listener
    _geofenceTransitionSub = _geofenceService.onTransition.listen((transition) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: transition.eventType == 'entered' ? Colors.teal.shade800 : Colors.indigo.shade800,
            duration: const Duration(seconds: 6),
            content: Row(
              children: [
                Icon(
                  transition.eventType == 'entered' ? Icons.location_on : Icons.directions_walk,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    transition.notificationText,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });

    // Initialize Phone Protection (Lost Mode, Intruder Trap, Last Breath)
    _phoneProtectionService.initialize().then((_) {
      _phoneProtectionService.checkAndApplyRemoteLostMode();
    });

    _intruderAlertSub = _phoneProtectionService.onIntruderAlert.listen((alert) {
      if (!mounted) return;
      _showIntruderAlertDialog(alert);
    });

    _lastBreathSub = _phoneProtectionService.onLastBreathBeacon.listen((beacon) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.battery_alert, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ TITIK TERAKHIR (Last Breath)! Baterai ${beacon.batteryLevel}%, posisi darurat terakhir tercatat.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    });

    // Listen to real-time Lost Mode updates from other circle devices
    _lostModeSub = _phoneProtectionService.onLostModeChanged.listen((cmd) async {
      if (mounted) {
        _loadActiveAlerts();
        final myUid = _supa.currentUser?.id;
        if (cmd.targetUserId == myUid) {
          if (cmd.isActive) {
            await _phoneProtectionService.applyRemoteLostMode(cmd);
            if (mounted) {
              _openLostModeScreen(cmd);
            }
          } else {
            await _phoneProtectionService.deactivateLostMode(targetUserId: myUid!);
            _closeLostModeScreen();
          }
        }
        if (!cmd.isActive) {
          SoundSettingsService().cancelEmergencyNotification();
        }
      }
    });

    // Listen to real-time SOS alerts globally
    _supa.subscribeToSosAlerts((alert) async {
      if (mounted) {
        _loadActiveAlerts();

        final myUid = _supa.currentUser?.id;

        // Check if this is a remote Lost Mode command
        if (alert.message.contains('[MODE HP HILANG]')) {
          final cmd = LostModeCommand.parseFromSosMessage(
            alertId: alert.id,
            message: alert.message,
            senderId: alert.userId,
            circleId: alert.circleId,
          );

          if (cmd != null && cmd.targetUserId == myUid) {
            if (alert.status == 'active') {
              // HP ini adalah target yang dituju: KUNCI SEKETIKA!
              await _phoneProtectionService.applyRemoteLostMode(cmd);
              if (mounted) {
                _openLostModeScreen(cmd);
              }
            } else if (alert.status == 'resolved' || alert.status == 'cancelled') {
              // Kunci dibuka kembali oleh keluarga!
              await _phoneProtectionService.deactivateLostMode(targetUserId: myUid!);
              _closeLostModeScreen();
            }
            return;
          }
        }

        // When alert is resolved or cancelled on other devices
        if (alert.status == 'resolved' || alert.status == 'cancelled') {
          await SoundSettingsService().cancelEmergencyNotification();
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }
          return;
        }

        // Only show emergency snackbar for currently active alerts
        if (alert.status == 'active') {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade800,
              duration: const Duration(seconds: 8),
              content: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PERINGATAN SOS DARURAT! ${alert.message}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'LIHAT',
                textColor: Colors.white,
                onPressed: () => setState(() => _currentIndex = 2),
              ),
            ),
          );
        }
      }
    });

    _alertRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _loadActiveAlerts();
    });

    if (mounted) setState(() => _isLoading = false);
  }

  void _showLoudAlarmDialog(LoudSignalModel signal) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'SINYAL KERAS BERDERING!',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Ponsel Anda dibunyikan dengan volume maksimal dari anggota keluarga untuk menarik perhatian darurat.',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            SizedBox(height: 16),
            Icon(Icons.volume_up, color: Colors.white, size: 48),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.stop_circle, color: Colors.red),
            label: const Text(
              'HENTIKAN ALARM SEKARANG',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () async {
              await _loudSignalService.stopCurrentRingingSignal();
              if (mounted) {
                setState(() => _incomingRingingSignal = null);
              }
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showIntruderAlertDialog(IntruderAlertModel alert) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.camera_alt_outlined, color: Colors.orangeAccent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '🚨 PENYUSUP TERJEBAK!',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Terdeteksi ${alert.attemptCount}x salah memasukkan PIN pada ponsel!',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (alert.photoUrl != null && alert.photoUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: 220,
                    child: alert.photoUrl!.startsWith('http')
                        ? Image.network(
                            alert.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => const Center(
                              child: Text('Gagal memuat foto penyusup', style: TextStyle(color: Colors.white54)),
                            ),
                          )
                        : Image.file(
                            File(alert.photoUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => const Center(
                              child: Text('Gagal membuka file foto', style: TextStyle(color: Colors.white54)),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '📸 Foto diambil otomatis dari kamera depan saat salah PIN 3x.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Koordinat: ${alert.latitude.toStringAsFixed(5)}, ${alert.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tutup', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.map, size: 18),
            label: const Text('Buka Peta Lokasi', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _currentIndex = 0);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadCircles() async {
    try {
      final circles = await _supa.getMyCircles();
      if (mounted) {
        setState(() {
          _circles = circles;
          if (_circles.isNotEmpty && (_selectedCircle == null || !_circles.any((c) => c.id == _selectedCircle!.id))) {
            _selectedCircle = _circles.first;
            _supa.currentCircleId = _selectedCircle!.id;
            _geofenceService.subscribeToCircleEvents(_selectedCircle!.id);
          }
        });
        _startGlobalChatListeners();
      }
    } catch (_) {}
  }

  void _startGlobalChatListeners() {
    for (var ch in _chatChannels) {
      ch.unsubscribe();
    }
    _chatChannels.clear();

    final myUid = _supa.currentUser?.id;
    if (myUid == null) return;

    for (var circle in _circles) {
      final ch = _supa.subscribeToMessages(circle.id, (msg) async {
        if (msg.userId != myUid) {
          if (mounted) setState(() => _unreadChatCount++);
          final nickname = MemberNicknameService.instance.getNickname(msg.userId);
          final senderName = nickname ?? msg.senderProfile?.fullName ?? 'Anggota';
          SoundSettingsService().previewSound('bubble_pop');
          await SoundSettingsService().showChatNotification(
            senderName: senderName,
            message: msg.message,
            circleName: circle.name,
          );

          if (mounted && _currentIndex != 2) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xFF1E3A8A),
                duration: const Duration(seconds: 4),
                content: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$senderName (${circle.name}): ${msg.message}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                action: SnackBarAction(
                  label: 'Buka',
                  textColor: Colors.amberAccent,
                  onPressed: () {
                    setState(() {
                      _selectedCircle = circle;
                      _currentIndex = 2;
                      _unreadChatCount = 0;
                    });
                  },
                ),
              ),
            );
          }
        }
      });
      _chatChannels.add(ch);
    }
  }

  Future<void> _loadActiveAlerts() async {
    try {
      final alerts = await _supa.getActiveAlerts(_selectedCircle?.id);
      if (mounted) {
        setState(() => _activeAlerts = alerts);
        if (alerts.isEmpty) {
          ScaffoldMessenger.of(context).clearSnackBars();
        }
        final hasActiveLostMode = alerts.any((a) => a.message.contains('[MODE HP HILANG]'));
        if (!hasActiveLostMode) {
          SoundSettingsService().cancelEmergencyNotification();
        }

        final myUid = _supa.currentUser?.id;
        if (myUid != null) {
          bool isTargetActive = false;
          for (final alert in alerts) {
            if (alert.message.contains('[MODE HP HILANG]') && alert.message.contains('Target: $myUid')) {
              isTargetActive = true;
              if (!_phoneProtectionService.isLostModeActive) {
                final cmd = LostModeCommand.parseFromSosMessage(
                  alertId: alert.id,
                  message: alert.message,
                  senderId: alert.userId,
                  circleId: alert.circleId,
                );
                if (cmd != null) {
                  await _phoneProtectionService.applyRemoteLostMode(cmd);
                  if (mounted) {
                    _openLostModeScreen(cmd);
                  }
                }
              }
              break;
            }
          }

          if (!isTargetActive && _phoneProtectionService.isLostModeActive) {
            final deactivateCmd = LostModeCommand(
              id: 'unlocked',
              targetUserId: myUid,
              senderId: 'remote',
              isActive: false,
              contactPhone: '',
              message: 'Mode HP Hilang dinonaktifkan.',
              enableSiren: false,
              enableFakeShutdown: false,
              updatedAt: DateTime.now(),
            );
            await _phoneProtectionService.applyRemoteLostMode(deactivateCmd);
            _closeLostModeScreen();
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasActiveSos = _activeAlerts.isNotEmpty;

    return Scaffold(
      body: Column(
        children: [
          // Accessibility Warning Banner if protection is not complete
          if (!_isAccessibilityEnabled && !_dismissedAccessibilityBanner)
            Material(
              color: Colors.amber.shade900,
              elevation: 3,
              child: SafeArea(
                bottom: false,
                top: !hasActiveSos,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Proteksi Anti-Maling Belum Lengkap',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text(
                              'Aktifkan Aksesibilitas agar pencuri tidak bisa tarik status bar / matikan HP.',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _promptEnableAccessibility,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.amber.shade900,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          'Aktifkan',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                        tooltip: 'Tutup Peringatan',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() => _dismissedAccessibilityBanner = true);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Global Prominent SOS Banner if any active alert exists
          if (hasActiveSos)
            Material(
              color: Colors.red.shade700,
              elevation: 4,
              child: SafeArea(
                bottom: false,
                child: InkWell(
                  onTap: () => setState(() => _currentIndex = 3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'PERINGATAN SOS AKTIF (${_activeAlerts.length} Panggilan Darurat)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Buka',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          
          // Banner Safety Timer (Fitur S6)
          if (_safetyTimerService.isActive)
            Material(
              color: Colors.teal.shade800,
              elevation: 4,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Safety Timer: ${_safetyTimerService.formattedRemaining}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _safetyTimerService.tripDescription,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.teal.shade900,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await _safetyTimerService.checkInSafe();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Check-In Berhasil! Anda tiba dengan selamat.'),
                                backgroundColor: Colors.teal,
                              ),
                            );
                          }
                        },
                        child: const Text('CHECK-IN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Batalkan Timer',
                        onPressed: () => _safetyTimerService.stopTimer(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Main Tab Pages (5 Tab Mandiri: Peta, Lingkaran, Obrolan, SOS, Profil)
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                MapViewScreen(
                  circles: _circles,
                  selectedCircle: _selectedCircle,
                  onCircleSelected: (c) {
                    setState(() => _selectedCircle = c);
                    _geofenceService.subscribeToCircleEvents(c.id);
                    _loadActiveAlerts();
                  },
                  onRefreshCircles: _loadCircles,
                  onNavigateToCircles: () => setState(() => _currentIndex = 1),
                  activeAlerts: _activeAlerts,
                ),
                CircleScreen(
                  circles: _circles,
                  selectedCircle: _selectedCircle,
                  onCircleSelected: (c) {
                    setState(() => _selectedCircle = c);
                    _geofenceService.subscribeToCircleEvents(c.id);
                    _loadActiveAlerts();
                  },
                  onRefreshCircles: _loadCircles,
                ),
                ChatScreen(
                  circles: _circles,
                  selectedCircle: _selectedCircle,
                  onCircleSelected: (c) {
                    setState(() => _selectedCircle = c);
                    _geofenceService.subscribeToCircleEvents(c.id);
                    _loadActiveAlerts();
                  },
                ),
                SosScreen(
                  selectedCircle: _selectedCircle,
                  activeAlerts: _activeAlerts,
                  onRefreshAlerts: _loadActiveAlerts,
                ),
                ProfileScreen(onSignedOut: widget.onSignedOut),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 10,
        shadowColor: Colors.black12,
        selectedIndex: _currentIndex,
        indicatorColor: const Color(0xFFEFF6FF),
        onDestinationSelected: (idx) {
          setState(() {
            _currentIndex = idx;
            if (idx == 2) _unreadChatCount = 0;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.location_on_outlined, color: Color(0xFF64748B)),
            selectedIcon: Icon(Icons.location_on, color: Color(0xFF1E3A8A)),
            label: 'Peta',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined, color: Color(0xFF64748B)),
            selectedIcon: Icon(Icons.groups_rounded, color: Color(0xFF1E3A8A)),
            label: 'Lingkaran',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unreadChatCount > 0,
              label: Text('$_unreadChatCount'),
              child: const Icon(Icons.chat_bubble_outline, color: Color(0xFF64748B)),
            ),
            selectedIcon: Badge(
              isLabelVisible: _unreadChatCount > 0,
              label: Text('$_unreadChatCount'),
              child: const Icon(Icons.chat_bubble, color: Color(0xFF1E3A8A)),
            ),
            label: 'Obrolan',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hasActiveSos,
              label: const Text(''),
              child: const Icon(Icons.crisis_alert_outlined, color: Color(0xFF64748B)),
            ),
            selectedIcon: const Icon(Icons.crisis_alert, color: Color(0xFFDC2626)),
            label: 'SOS',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline, color: Color(0xFF64748B)),
            selectedIcon: Icon(Icons.person, color: Color(0xFF1E3A8A)),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
