import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/loud_signal_service.dart';
import '../services/phone_protection_service.dart';
import '../services/sos_trigger_service.dart';
import '../services/sound_settings_service.dart';
import '../services/supabase_service.dart';
import 'circle_screen.dart';
import 'features_screen.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseService _supa = SupabaseService();
  final LocationService _locService = LocationService();
  final AudioService _audioService = AudioService();
  final SosTriggerService _sosTriggerService = SosTriggerService();
  final LoudSignalService _loudSignalService = LoudSignalService();
  final GeofenceService _geofenceService = GeofenceService();
  final PhoneProtectionService _phoneProtectionService = PhoneProtectionService();

  StreamSubscription<void>? _sosTriggerSub;
  StreamSubscription<LoudSignalModel>? _incomingSignalSub;
  StreamSubscription<String>? _signalStoppedSub;
  StreamSubscription<GeofenceTransition>? _geofenceTransitionSub;
  StreamSubscription<LostModeCommand>? _lostModeSub;
  StreamSubscription<IntruderAlertModel>? _intruderAlertSub;
  StreamSubscription<LastBreathBeaconModel>? _lastBreathSub;
  StreamSubscription<bool>? _gpsStatusSub;

  int _currentIndex = 0;
  List<CircleModel> _circles = [];
  CircleModel? _selectedCircle;
  List<SosAlert> _activeAlerts = [];
  bool _isLoading = true;
  LoudSignalModel? _incomingRingingSignal;
  final List<RealtimeChannel> _chatChannels = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    for (var ch in _chatChannels) {
      ch.unsubscribe();
    }
    _chatChannels.clear();
    _gpsStatusSub?.cancel();
    _audioService.stopListening();
    _sosTriggerSub?.cancel();
    _incomingSignalSub?.cancel();
    _signalStoppedSub?.cancel();
    _geofenceTransitionSub?.cancel();
    _lostModeSub?.cancel();
    _intruderAlertSub?.cancel();
    _lastBreathSub?.cancel();
    _loudSignalService.stopListening();
    _geofenceService.stopListening();
    _phoneProtectionService.stopListening();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Start fast SOS trigger background listener & sync
    await _sosTriggerService.initialize();
    _sosTriggerSub = _sosTriggerService.onSosTriggered.listen((_) {
      if (mounted) {
        _loadActiveAlerts();
        setState(() => _currentIndex = 3);
      }
    });

    // Start live location streaming & battery tracking
    await _locService.startTracking();

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

    final isGpsOn = await _locService.checkGpsStatus();
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
    await _phoneProtectionService.initialize();

    _lostModeSub = _phoneProtectionService.onLostModeChanged.listen((cmd) {
      if (!mounted) return;
      final myUid = _supa.currentUser?.id;
      if (cmd.targetUserId == myUid) {
        if (cmd.isActive) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LostModeScreen(command: cmd),
            ),
          );
        }
      }
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

    // Check if Lost Mode was persisted from previous session OR active remotely on server
    final remoteCmd = await _phoneProtectionService.checkAndApplyRemoteLostMode();
    if (remoteCmd != null || (_phoneProtectionService.isLostModeActive && _phoneProtectionService.activeLostMode != null)) {
      final activeCmd = remoteCmd ?? _phoneProtectionService.activeLostMode!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LostModeScreen(command: activeCmd),
            ),
          );
        }
      });
    }

    // Load user's circles & active SOS alerts
    await _loadCircles();
    await _loadActiveAlerts();

    if (_selectedCircle != null) {
      _geofenceService.subscribeToCircleEvents(_selectedCircle!.id);
    }

    // Listen to real-time SOS alerts globally
    _supa.subscribeToSosAlerts((alert) async {
      if (mounted) {
        _loadActiveAlerts();

        // Check if this is a remote Lost Mode command
        if (alert.message.contains('[MODE HP HILANG]')) {
          final myUid = _supa.currentUser?.id;
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LostModeScreen(command: cmd),
                  ),
                );
              }
            } else if (alert.status == 'resolved' || alert.status == 'cancelled') {
              // Kunci dibuka kembali oleh keluarga!
              await _phoneProtectionService.deactivateLostMode(targetUserId: myUid!);
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
            return;
          }
        }

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
              onPressed: () => setState(() => _currentIndex = 3),
            ),
          ),
        );
      }
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
          final senderName = msg.senderProfile?.fullName ?? 'Anggota';
          await SoundSettingsService().showChatNotification(
            senderName: senderName,
            message: msg.message,
            circleName: circle.name,
          );

          if (mounted && _currentIndex != 1) {
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
                      _currentIndex = 1;
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

          // Main Tab Pages
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
                FeaturesScreen(
                  circles: _circles,
                  selectedCircle: _selectedCircle,
                  onNavigateToTab: (idx) => setState(() => _currentIndex = idx),
                  onRefresh: _loadCircles,
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
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: Colors.indigo),
            label: 'Peta',
          ),
          const NavigationDestination(
            icon: Icon(Icons.group_work_outlined),
            selectedIcon: Icon(Icons.group_work, color: Colors.indigo),
            label: 'Lingkaran',
          ),
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded, color: Colors.indigo),
            label: 'Fitur',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hasActiveSos,
              label: Text('${_activeAlerts.length}'),
              child: const Icon(Icons.crisis_alert_outlined),
            ),
            selectedIcon: const Icon(Icons.crisis_alert, color: Colors.red),
            label: 'SOS',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Colors.indigo),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
