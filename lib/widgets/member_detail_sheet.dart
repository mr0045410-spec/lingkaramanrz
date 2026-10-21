import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/app_usage_service.dart';
import '../services/loud_signal_service.dart';
import '../services/phone_protection_service.dart';
import '../services/member_nickname_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import 'trip_history_sheet.dart';

class MemberDetailSheet extends StatefulWidget {
  final CircleMember member;
  final CircleModel? circle;

  const MemberDetailSheet({
    super.key,
    required this.member,
    this.circle,
  });

  static Future<void> show(BuildContext context, CircleMember member, CircleModel? circle) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MemberDetailSheet(member: member, circle: circle),
    );
  }

  @override
  State<MemberDetailSheet> createState() => _MemberDetailSheetState();
}

class _MemberDetailSheetState extends State<MemberDetailSheet> {
  final SupabaseService _supa = SupabaseService();
  final AudioPlayer _player = AudioPlayer();
  final LoudSignalService _loudSignalService = LoudSignalService();
  final AppUsageService _appUsageService = AppUsageService();
  final PhoneProtectionService _protectionService = PhoneProtectionService();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  RealtimeChannel? _requestSub;
  StreamSubscription? _signalStoppedSub;
  StreamSubscription<LostModeCommand>? _lostModeSub;

  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  AudioRequestModel? _currentRequest;
  bool _isRequesting = false;
  String _statusText = '';

  List<AudioRequestModel> _pastRecordings = [];
  bool _isLoadingHistory = true;
  String? _currentlyPlayingUrl;

  // Loud Signal State
  bool _isSendingLoudSignal = false;
  LoudSignalModel? _activeSentSignal;

  // App Usage State
  List<AppUsageModel> _appUsageList = [];
  bool _isLoadingUsage = true;
  bool _hasUsagePermission = true;
  bool _isSyncingUsage = false;

  // Phone Protection State
  bool _isLostModeActiveForMember = false;
  bool _isActionRunning = false;

  @override
  void initState() {
    super.initState();
    _initAudioListeners();
    _loadPastRecordings();
    _initLoudSignalListener();
    _loadUsageData();
    _initProtectionListener();
  }

  Timer? _lostModePollTimer;

  Future<void> _showEditNicknameDialog(String userId, String? currentNickname, String fullName) async {
    final ctrl = TextEditingController(text: currentNickname ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.badge_outlined, color: Colors.indigo),
            SizedBox(width: 8),
            Expanded(
              child: Text('Nama Panggilan Anggota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ganti nama tampilan untuk \$fullName (hanya terlihat oleh Anda).',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Panggilan',
                hintText: 'Misal: Ayah, Ibu, Kakak, Adek',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (currentNickname != null && currentNickname.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                await MemberNicknameService.instance.removeNickname(userId);
                if (mounted) setState(() {});
              },
              child: const Text('Reset Asli'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final val = ctrl.text.trim();
              Navigator.pop(ctx);
              if (val.isEmpty) {
                await MemberNicknameService.instance.removeNickname(userId);
              } else {
                await MemberNicknameService.instance.setNickname(userId, val);
              }
              if (mounted) setState(() {});
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _initProtectionListener() async {
    final isActive = await _protectionService.isLostModeActiveForUser(widget.member.userId);
    if (mounted) {
      setState(() => _isLostModeActiveForMember = isActive);
    }
    _lostModeSub = _protectionService.onLostModeChanged.listen((cmd) {
      if (mounted && cmd.targetUserId == widget.member.userId) {
        setState(() => _isLostModeActiveForMember = cmd.isActive);
      }
    });

    _lostModePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      final active = await _protectionService.isLostModeActiveForUser(widget.member.userId);
      if (mounted && _isLostModeActiveForMember != active) {
        setState(() => _isLostModeActiveForMember = active);
      }
    });
  }

  void _initLoudSignalListener() {
    _signalStoppedSub = _loudSignalService.onSignalStopped.listen((stoppedId) {
      if (mounted && _activeSentSignal?.id == stoppedId) {
        setState(() => _activeSentSignal = null);
      }
    });
  }

  Future<void> _loadUsageData() async {
    try {
      final hasPerm = await _appUsageService.hasUsagePermission();
      final list = await _appUsageService.getMemberUsage(widget.member.userId);
      if (mounted) {
        setState(() {
          _hasUsagePermission = hasPerm;
          _appUsageList = list;
          _isLoadingUsage = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUsage = false);
    }
  }

  Future<void> _syncUsage() async {
    setState(() => _isSyncingUsage = true);
    await _appUsageService.syncTodayAppUsage();
    await _loadUsageData();
    if (mounted) setState(() => _isSyncingUsage = false);
  }

  Future<void> _sendLoudSignal() async {
    setState(() => _isSendingLoudSignal = true);
    try {
      final sig = await _loudSignalService.sendLoudSignal(
        targetUserId: widget.member.userId,
        circleId: widget.circle?.id,
      );
      if (mounted) {
        setState(() {
          _activeSentSignal = sig;
          _isSendingLoudSignal = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Sinyal Keras berhasil dikirim! Ponsel target akan berdering keras.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingLoudSignal = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim sinyal keras: $e')),
        );
      }
    }
  }

  Future<void> _stopLoudSignal() async {
    if (_activeSentSignal == null) return;
    try {
      await _loudSignalService.stopLoudSignal(_activeSentSignal!.id);
      if (mounted) {
        setState(() => _activeSentSignal = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghentikan sinyal: $e')),
        );
      }
    }
  }

  String _formatUsageSeconds(int seconds) {
    if (seconds < 60) return '$seconds dtk';
    final mins = seconds ~/ 60;
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    if (hours > 0) {
      return '$hours j $remMins m';
    }
    return '$mins m';
  }

  void _initAudioListeners() {
    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  Future<void> _loadPastRecordings() async {
    try {
      final history = await _supa.getAudioRequestsForTarget(widget.member.userId);
      if (mounted) {
        setState(() {
          _pastRecordings = history;
          _isLoadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Timer? _timeoutTimer;
  Timer? _pollTimer;

  @override
  void dispose() {
    _lostModePollTimer?.cancel();
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _signalStoppedSub?.cancel();
    _lostModeSub?.cancel();
    _requestSub?.unsubscribe();
    _player.dispose();
    super.dispose();
  }

  void _onStatusUpdated(AudioRequestModel updatedReq) {
    if (!mounted) return;
    setState(() {
      _currentRequest = updatedReq;
      if (updatedReq.status == 'recording') {
        _statusText = 'Target sedang merekam lingkungan sekitar (15 detik)...';
      } else if (updatedReq.status == 'completed') {
        _statusText = 'Rekaman berhasil diterima!';
        _isRequesting = false;
        _timeoutTimer?.cancel();
        _pollTimer?.cancel();
        _loadPastRecordings();
        if (updatedReq.audioUrl != null) {
          _playAudio(updatedReq.audioUrl!);
        }
      } else if (updatedReq.status == 'failed') {
        _statusText = 'Gagal merekam. Perangkat sedang offline atau mikrofon belum diizinkan.';
        _isRequesting = false;
        _timeoutTimer?.cancel();
        _pollTimer?.cancel();
      }
    });
  }

  Future<void> _requestAmbientAudio() async {
    setState(() {
      _isRequesting = true;
      _statusText = 'Mengirim sinyal permintaan audio ke HP target...';
    });

    try {
      final req = await _supa.createAudioRequest(
        targetUserId: widget.member.userId,
        circleId: widget.circle?.id,
        durationSeconds: 15,
      );

      setState(() {
        _currentRequest = req;
        _statusText = 'Menunggu target merespons sinyal...';
      });

      // 1. Subscribe to Realtime updates
      _requestSub?.unsubscribe();
      _requestSub = _supa.subscribeToSpecificAudioRequest(req.id, (updatedReq) {
        _onStatusUpdated(updatedReq);
      });

      // 2. Timeout after 25 seconds if target is offline
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && _isRequesting && _currentRequest?.status == 'pending') {
          setState(() {
            _isRequesting = false;
            _statusText = 'Target tidak merespons (ponsel target sedang offline/mati atau belum membuka aplikasi).';
          });
          _pollTimer?.cancel();
        }
      });

      // 3. Fallback polling every 2s
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (!mounted || !_isRequesting || _currentRequest == null) {
          timer.cancel();
          return;
        }
        try {
          final refreshed = await _supa.getAudioRequestById(_currentRequest!.id);
          if (refreshed != null && refreshed.status != _currentRequest!.status) {
            _onStatusUpdated(refreshed);
          }
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _statusText = 'Error: $e';
        });
      }
    }
  }


  Future<void> _playAudio(String url) async {
    try {
      if (_currentlyPlayingUrl == url && _playerState == PlayerState.playing) {
        await _player.pause();
      } else {
        _currentlyPlayingUrl = url;
        await _player.stop();
        if (url.startsWith('http://') || url.startsWith('https://')) {
          await _player.play(UrlSource(url));
        } else {
          await _player.play(DeviceFileSource(url));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memutar audio: $e')),
        );
      }
    }
  }

  Future<void> _openGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isMe = m.userId == _supa.currentUser?.id;
    final nickname = MemberNicknameService.instance.getNickname(m.userId);
    final fullName = m.profile?.fullName ?? 'Anggota';
    final name = isMe ? 'Saya' : (nickname ?? fullName);
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarUrl = m.profile?.avatarUrl;
    final loc = m.location;

    Color batteryColor = Colors.green;
    if (loc != null) {
      if (loc.batteryLevel < 20) {
        batteryColor = Colors.red;
      } else if (loc.batteryLevel < 50) {
        batteryColor = Colors.orange;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                                    // IDENTITAS ANGGOTA (Sesuai Referensi Layar 8)
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: isMe ? AppColors.primaryNavy : const Color(0xFF3B82F6),
                        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: (avatarUrl == null || avatarUrl.isEmpty)
                            ? Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.statusSuccess,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isMe ? 'Di sini • Baterai ${loc?.batteryLevel ?? 100}%' : 'Di rumah • Baterai ${loc?.batteryLevel ?? 100}%',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 3 TOMBOL TINDAKAN CEPAT WARNA (Sesuai Referensi Layar 8)
                  Row(
                    children: [
                      // Tombol 1: Merah "Sinyal Keras"
                      Expanded(
                        child: ActionTileButton(
                          icon: Icons.signal_cellular_alt_rounded,
                          label: 'Sinyal Keras',
                          backgroundColor: const Color(0xFFDC2626), // Merah
                          foregroundColor: Colors.white,
                          onTap: _activeSentSignal != null ? _stopLoudSignal : _sendLoudSignal,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Tombol 2: Navy "Mode HP Hilang"
                      Expanded(
                        child: ActionTileButton(
                          icon: Icons.shield_rounded,
                          label: 'Mode HP Hilang',
                          backgroundColor: AppColors.primaryNavy, // Navy
                          foregroundColor: Colors.white,
                          onTap: _isLostModeActiveForMember ? _deactivateLostMode : _showActivateLostModeDialog,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Tombol 3: Abu-abu "Riwayat Perjalanan"
                      Expanded(
                        child: ActionTileButton(
                          icon: Icons.history_rounded,
                          label: 'Riwayat Perjalanan',
                          backgroundColor: const Color(0xFF64748B), // Slate / Abu-abu
                          foregroundColor: Colors.white,
                          onTap: () {
                            if (widget.circle != null) {
                              TripHistorySheet.show(context, widget.member, widget.circle!);
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // KOTAK PRATINJAU PETA PERJALANAN (Sesuai Referensi Layar 8)
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          // Simulasi Polyline Rute Visual / Peta Rute Mini
                          Center(
                            child: Icon(
                              Icons.route_rounded,
                              size: 48,
                              color: AppColors.primaryNavy.withOpacity(0.3),
                            ),
                          ),
                          // Badge "Rute hari ini"
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Rute hari ini',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // INFORMASI STATUS LOKASI: Terakhir terlihat & Zona Aman (Layar 8 Referensi)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        // Terakhir terlihat
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_rounded, color: AppColors.textSecondary, size: 18),
                              const SizedBox(width: 10),
                              const Text(
                                'Terakhir terlihat',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                loc != null
                                    ? '${DateTime.now().difference(loc.updatedAt).inMinutes.clamp(1, 1440)} menit lalu'
                                    : 'Baru saja',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Zona Aman
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: const [
                              Icon(Icons.location_on_rounded, color: AppColors.primaryNavy, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Zona Aman',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Spacer(),
                              Text(
                                'Rumah',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
// Location Details
                  if (loc != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Koordinat Terakhir',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Pembaruan: ${DateFormat('dd MMM HH:mm').format(loc.updatedAt)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.directions, color: Colors.indigo),
                          tooltip: 'Buka Navigasi Google Maps',
                          onPressed: () => _openGoogleMaps(loc.latitude, loc.longitude),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Riwayat Perjalanan (Timeline) Card
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade50, Colors.indigo.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.timeline, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Riwayat Perjalanan (Linimasa)',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Lihat jejak rute, linimasa waktu, dan titik singgah ${isMe ? "Anda" : "anggota ini"}.',
                                style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            if (widget.circle != null) {
                              TripHistorySheet.show(context, widget.member, widget.circle!);
                            }
                          },
                          child: const Text('Buka Log', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  const Divider(),

                  // Ambient Audio Section (Remote audio - Only for other members)
                  if (!isMe) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: const [
                        Icon(Icons.mic, color: Colors.deepOrange, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Pemeriksaan Suara Sekitar (Remote Audio)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: Colors.amber.shade900,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Gunakan jika mencurigai ponsel sedang dipegang pelaku atau dalam bahaya. Sinyal dikirim dan direkam secara hening tanpa nada dering.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Remote request button for other members
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isRequesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.hearing),
                        label: Text(
                          _isRequesting ? 'Sedang Memproses...' : 'Minta Rekaman Lingkungan (15 Detik)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isRequesting ? null : _requestAmbientAudio,
                      ),
                    ),

                    if (_statusText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _currentRequest?.status == 'failed' ? Colors.red : Colors.indigo,
                          ),
                        ),
                      ),
                    ],

                    // Inline Audio Player (if current request completed)
                    if (_currentRequest != null && _currentRequest!.audioUrl != null) ...[
                      const SizedBox(height: 12),
                      _buildAudioPlayerCard(_currentRequest!.audioUrl!, 'Rekaman Terkini (${_currentRequest!.durationSeconds}s)'),
                    ],

                    const SizedBox(height: 16),
                    const Divider(),

                    // History of ambient recordings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Riwayat Rekaman Suara',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        if (_isLoadingHistory)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (!_isLoadingHistory && _pastRecordings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Belum ada riwayat rekaman suara untuk anggota ini.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _pastRecordings.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final rec = _pastRecordings[idx];
                          if (rec.audioUrl == null) return const SizedBox.shrink();
                          final isPlaying = _currentlyPlayingUrl == rec.audioUrl &&
                              _playerState == PlayerState.playing;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                    color: Colors.deepOrange,
                                    size: 32,
                                  ),
                                  onPressed: () => _playAudio(rec.audioUrl!),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Klip Audio ${rec.durationSeconds} Detik',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        DateFormat('dd MMM yyyy, HH:mm').format(rec.createdAt),
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],

                    // Sinyal Keras (Loud Signal - Bypassing DND, only for other members)
                    if (!isMe) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: const [
                          Icon(Icons.notifications_active, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sinyal Keras (Tembus Silent / DND)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.volume_up, color: Colors.red.shade900, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Bunyikan alarm darurat pada volume maksimal langsung di HP target meskipun dalam mode Senyap atau Jangan Ganggu (DND).',
                              style: TextStyle(fontSize: 12, color: Colors.red.shade900, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_activeSentSignal != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Sinyal Keras Berdering di HP Target...',
                                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade800,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.stop_circle, color: Colors.red),
                                label: const Text('Hentikan Sinyal Keras', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: _stopLoudSignal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isSendingLoudSignal
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.notifications_active),
                          label: Text(
                            _isSendingLoudSignal ? 'Mengirim Sinyal...' : 'Bunyikan Sinyal Keras Sekarang',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isSendingLoudSignal ? null : _sendLoudSignal,
                        ),
                      ),
                    ],
                  ],

                  // Mode HP Hilang & Perlindungan Anti-Maling
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildPhoneProtectionSection(isMe),

                  // Statistik Penggunaan Aplikasi (Screen Time - Semua Anggota)
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildAppUsageSection(isMe),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showActivateLostModeDialog() async {
    final contactController = TextEditingController(text: _supa.currentUser?.phone ?? '');
    final messageController = TextEditingController(
      text: 'HP ini tertinggal/hilang. Mohon bantu kembalikan ke pemiliknya dengan menghubungi nomor di bawah.',
    );
    bool siren = true;
    bool fakeShutdown = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.phonelink_lock, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Aktifkan Mode HP Hilang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ponsel target akan dikunci seketika. Layar hanya menampilkan nomor kontak dan pesan pengembalian Anda.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contactController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Nomor Kontak Pemilik',
                        hintText: '08xxxxxxxxxx',
                        prefixIcon: const Icon(Icons.phone),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: messageController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Pesan Darurat',
                        hintText: 'Pesan untuk yang menemukan HP',
                        prefixIcon: const Icon(Icons.message),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bunyikan Sirine Nyaring', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Alarm akan berdering terus menerus', style: TextStyle(fontSize: 11)),
                      value: siren,
                      activeThumbColor: Colors.red,
                      onChanged: (val) => setDialogState(() => siren = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kamuflase Mati (Fake Shutdown)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Layar padam pura-pura mati, GPS tetap melacak', style: TextStyle(fontSize: 11)),
                      value: fakeShutdown,
                      activeThumbColor: Colors.cyan,
                      onChanged: (val) => setDialogState(() => fakeShutdown = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final phone = contactController.text.trim();
                    final msg = messageController.text.trim();
                    Navigator.of(dialogCtx).pop();

                    setState(() => _isActionRunning = true);
                    try {
                      await _protectionService.sendLostModeCommand(
                        targetUserId: widget.member.userId,
                        contactPhone: phone.isNotEmpty ? phone : '08123456789',
                        message: msg.isNotEmpty ? msg : 'HP ini dalam mode hilang.',
                        enableSiren: siren,
                        enableFakeShutdown: fakeShutdown,
                        circleId: widget.circle?.id,
                      );
                      if (mounted) {
                        setState(() {
                          _isLostModeActiveForMember = true;
                          _isActionRunning = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('Mode HP Hilang berhasil diaktifkan pada ponsel anggota!'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _isActionRunning = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal mengaktifkan mode hilang: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Kunci Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deactivateLostMode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hentikan Mode HP Hilang?'),
        content: const Text('Layar ponsel target akan dibuka kembali dan sirine dihentikan.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Buka Kunci'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isActionRunning = true);
    try {
      await _protectionService.deactivateLostMode(
        targetUserId: widget.member.userId,
        circleId: widget.circle?.id,
      );
      if (mounted) {
        setState(() {
          _isLostModeActiveForMember = false;
          _isActionRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.teal,
            content: Text('Mode HP Hilang dinonaktifkan.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menonaktifkan: $e')),
        );
      }
    }
  }

  Future<void> _confirmRemoteVaultLock() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.shield, color: Colors.blueGrey),
            SizedBox(width: 8),
            Expanded(
              child: Text('Kunci Brankas Data?', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: const Text(
          'Perintah ini akan mengamankan brankas lokal, mengunci data perbankan/pribadi, dan membersihkan sesi cache sensitif dari jarak jauh.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kunci Brankas'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isActionRunning = true);
    try {
      await _protectionService.remoteLockVault(
        targetUserId: widget.member.userId,
        circleId: widget.circle?.id,
      );
      if (mounted) {
        setState(() => _isActionRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.blueGrey,
            content: Text('Perintah Penguncian Brankas Data berhasil dikirim ke perangkat!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim perintah: $e')),
        );
      }
    }
  }



  Widget _buildPhoneProtectionSection(bool isMe) {
    final battery = widget.member.location?.batteryLevel;
    final isCriticalBattery = battery != null && battery <= 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.shield_outlined, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Mode HP Hilang & Anti-Maling',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 2. LAST BREATH BEACON ALERT (If battery <= 5%)
        if (isCriticalBattery) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade400),
            ),
            child: Row(
              children: [
                const Icon(Icons.battery_alert, color: Colors.redAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TITIK TERAKHIR (Last Breath Beacon)',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Baterai tersisa $battery%! Titik lokasi darurat terekam sesaat sebelum ponsel kehabisan daya.',
                        style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Status Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isLostModeActiveForMember ? Colors.red.shade50 : Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isLostModeActiveForMember ? Colors.red.shade300 : Colors.blueGrey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isLostModeActiveForMember ? Icons.lock : Icons.verified_user,
                    color: _isLostModeActiveForMember ? Colors.red.shade900 : Colors.teal.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isLostModeActiveForMember
                          ? 'MODE HP HILANG AKTIF PADA PERANGKAT INI'
                          : 'Perlindungan Anti-Maling Siaga',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _isLostModeActiveForMember ? Colors.red.shade900 : Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _isLostModeActiveForMember
                    ? 'Layar ponsel sedang terkunci penuh dengan pesan kontak pemilik, alarm sirine, dan pelacakan GPS langsung.'
                    : 'Kunci jarak jauh jika ponsel hilang/dicuri. Pelacakan GPS akan aktif di latar belakang dan membunyikan sirine.',
                style: TextStyle(
                  fontSize: 12,
                  color: _isLostModeActiveForMember ? Colors.red.shade900 : Colors.blueGrey.shade800,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (!isMe) ...[
          // For other member's phone
          if (_isLostModeActiveForMember) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade800,
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.lock_open, color: Colors.red),
                label: const Text(
                  'Hentikan Mode HP Hilang',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _isActionRunning ? null : _deactivateLostMode,
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.phonelink_lock),
                label: const Text(
                  'Aktifkan Mode HP Hilang (Kunci Jarak Jauh)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _isActionRunning ? null : _showActivateLostModeDialog,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // 5. KUNCI / HAPUS BRANKAS DATA JARAK JAUH
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blueGrey.shade900,
                side: BorderSide(color: Colors.blueGrey.shade400),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.enhanced_encryption, size: 20),
              label: const Text(
                'Kunci / Amankan Brankas Data Jarak Jauh',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: _isActionRunning ? null : _confirmRemoteVaultLock,
            ),
          ),
        ] else ...[
          // For current user's phone: inform user about active family protection
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blueGrey.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Perangkat Anda siaga dan terhubung. Jika ponsel ini hilang atau dirampas, anggota keluarga lain dalam lingkaran dapat mengunci atau melacaknya dari aplikasi mereka.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAppUsageSection(bool isMe) {
    final totalSeconds = _appUsageList.fold<int>(0, (sum, item) => sum + item.totalTimeForegroundSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: const [
                  Icon(Icons.hourglass_bottom, color: Colors.indigo, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Waktu Layar & Aplikasi',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoadingUsage)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (isMe)
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: _isSyncingUsage
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                    : const Icon(Icons.sync, size: 16),
                label: Text(_isSyncingUsage ? 'Sinkron...' : 'Sinkron', style: const TextStyle(fontSize: 12)),
                onPressed: _isSyncingUsage ? null : _syncUsage,
              ),
          ],
        ),
        if (isMe && !_hasUsagePermission) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade900, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Izin Akses Penggunaan Diperlukan',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Aktifkan izin akses penggunaan di Android agar statistik waktu layar dapat dibagikan ke lingkaran keluarga.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade900,
                    side: BorderSide(color: Colors.amber.shade800),
                  ),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Buka Pengaturan Izin Android', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await _appUsageService.openUsageSettings();
                    await Future.delayed(const Duration(seconds: 1));
                    _loadUsageData();
                  },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_android, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Waktu Layar Hari Ini',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Text(
                      _formatUsageSeconds(totalSeconds),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (!_isLoadingUsage && _appUsageList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              isMe
                  ? 'Belum ada data aplikasi hari ini. Tekan tombol Sinkron setelah mengaktifkan izin.'
                  : 'Belum ada data penggunaan aplikasi dari anggota ini hari ini.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _appUsageList.length > 6 ? 6 : _appUsageList.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (ctx, idx) {
              final app = _appUsageList[idx];
              final ratio = totalSeconds > 0
                  ? (app.totalTimeForegroundSeconds / totalSeconds).clamp(0.0, 1.0)
                  : 0.0;
              final cleanName = app.appName.isNotEmpty
                  ? app.appName
                  : app.packageName.split('.').last;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.indigo.shade100,
                          child: Text(
                            cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'A',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cleanName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatUsageSeconds(app.totalTimeForegroundSeconds),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade400),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAudioPlayerCard(String url, String title) {
    final isPlaying = _currentlyPlayingUrl == url && _playerState == PlayerState.playing;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepOrange.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  size: 38,
                  color: Colors.deepOrange,
                ),
                onPressed: () => _playAudio(url),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 0,
              max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
              value: _position.inMilliseconds.toDouble().clamp(
                    0.0,
                    _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                  ),
              activeColor: Colors.deepOrange,
              inactiveColor: Colors.deepOrange.shade100,
              onChanged: (val) {
                _player.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
        ],
      ),
    );
  }
}
