import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FallDetectionService {
  static final FallDetectionService _instance = FallDetectionService._internal();
  factory FallDetectionService() => _instance;
  FallDetectionService._internal();

  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/fall_detection');
  static const String _kFallDetectionEnabled = 'fall_detection_enabled';

  final StreamController<void> _fallStreamController = StreamController<void>.broadcast();
  Stream<void> get onFallDetected => _fallStreamController.stream;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFallDetected') {
        final enabled = await isEnabled();
        if (enabled) {
          debugPrint('[FallDetectionService] Native fall/crash event received!');
          _fallStreamController.add(null);
        }
      }
    });

    // Sinkronisasi status tersimpan ke native saat inisialisasi awal
    final enabled = await isEnabled();
    if (enabled) {
      await _startNativeListening();
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFallDetectionEnabled) ?? false; // Default NONAKTIF
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFallDetectionEnabled, enabled);

    if (enabled) {
      await _startNativeListening();
    } else {
      await _stopNativeListening();
    }
  }

  Future<void> _startNativeListening() async {
    try {
      await _channel.invokeMethod('startListening');
    } catch (e) {
      debugPrint('[FallDetectionService] Error start listening: $e');
    }
  }

  Future<void> _stopNativeListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } catch (e) {
      debugPrint('[FallDetectionService] Error stop listening: $e');
    }
  }

  /// Pemicu simulasi langsung untuk keperluan pengujian / unit testing
  void simulateFall() {
    debugPrint('[FallDetectionService] Simulating hard fall/crash...');
    _fallStreamController.add(null);
  }
}
