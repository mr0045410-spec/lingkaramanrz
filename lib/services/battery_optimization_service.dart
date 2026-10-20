import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Layanan untuk mengelola proteksi Anti-Kill OS Android & Battery Optimization Whitelist.
/// Memastikan pelacakan GPS dan koneksi darurat tidak dimatikan saat ponsel sleep di saku.
class BatteryOptimizationService {
  static final BatteryOptimizationService _instance = BatteryOptimizationService._internal();
  factory BatteryOptimizationService() => _instance;
  BatteryOptimizationService._internal();

  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/battery_optimization');

  /// Memeriksa apakah aplikasi sudah masuk ke whitelist 'Abaikan Optimasi Baterai'
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } catch (e) {
      debugPrint('[BatteryOptimizationService] Error check battery optimization: $e');
      return false;
    }
  }

  /// Membuka prompt sistem Android langsung untuk mengizinkan aplikasi berjalan tanpa batas di latar belakang
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('[BatteryOptimizationService] Error request battery optimization: $e');
    }
  }
}
