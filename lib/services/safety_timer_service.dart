import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'supabase_service.dart';
import 'sound_settings_service.dart';

class SafetyTimerService {
  static final SafetyTimerService _instance = SafetyTimerService._internal();
  factory SafetyTimerService() => _instance;
  SafetyTimerService._internal();

  final SupabaseService _supa = SupabaseService();

  Timer? _timer;
  bool _isActive = false;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;
  String _tripDescription = '';

  final StreamController<int> _timerStreamController = StreamController<int>.broadcast();
  Stream<int> get onTick => _timerStreamController.stream;

  bool get isActive => _isActive;
  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  String get tripDescription => _tripDescription;

  String get formattedRemaining {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get progress {
    if (_totalSeconds <= 0) return 0.0;
    return (_totalSeconds - _remainingSeconds) / _totalSeconds;
  }

  void startSafetyTimer({
    required int durationMinutes,
    required String description,
  }) {
    stopTimer();

    _totalSeconds = durationMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _tripDescription = description.trim().isEmpty ? 'Perjalanan Mandiri' : description.trim();
    _isActive = true;

    _timerStreamController.add(_remainingSeconds);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        _timerStreamController.add(_remainingSeconds);
      } else {
        timer.cancel();
        _isActive = false;
        await _onTimerExpired();
      }
    });
  }

  Future<void> checkInSafe() async {
    final desc = _tripDescription;
    stopTimer();

    // Kirim pesan ke circle obrolan bahwa user sudah tiba dengan selamat
    try {
      final circles = await _supa.getMyCircles();
      if (circles.isNotEmpty) {
        for (final circle in circles) {
          await _supa.sendMessage(
            circle.id,
            '✅ Saya sudah tiba dengan selamat ($desc). Kondisi aman!',
          );
        }
      }
    } catch (e) {
      debugPrint('[SafetyTimer] Gagal broadcast check-in aman: $e');
    }
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _remainingSeconds = 0;
    _totalSeconds = 0;
    _timerStreamController.add(0);
  }

  Future<void> _onTimerExpired() async {
    debugPrint('[SafetyTimer] 🚨 Waktu perjalanan habis! Memicu SOS darurat otomatis.');

    // 1. Bunyikan sirene keras lokal
    try {
      await SoundSettingsService().previewSound('siren_pulse');
    } catch (_) {}

    // 2. Trigger SOS darurat ke Supabase Realtime keluarga
    try {
      double lat = -6.2088;
      double lng = 106.8456;
      try {
        final pos = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}

      await _supa.triggerSOS(
        latitude: lat,
        longitude: lng,
        customMessage: '🚨 DARURAT SAFETY TIMER: Pengguna tidak melakukan check-in aman setelah batas waktu habis! Catatan perjalanan: "$_tripDescription". Hubungi sekarang!',
      );
    } catch (e) {
      debugPrint('[SafetyTimer] Gagal trigger auto SOS: $e');
    }
  }
}
