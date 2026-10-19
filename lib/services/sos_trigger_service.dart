import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'supabase_service.dart';

class SosTriggerService {
  static final SosTriggerService _instance = SosTriggerService._internal();
  factory SosTriggerService() => _instance;
  SosTriggerService._internal();

  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/sos_triggers');

  final StreamController<void> _sosTriggerStreamController = StreamController<void>.broadcast();
  Stream<void> get onSosTriggered => _sosTriggerStreamController.stream;

  bool _isInitialized = false;
  bool _isTriggering = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSosTriggered') {
        _handleTrigger();
      }
    });

    // Check if app was started directly with SOS trigger
    try {
      final initialTrigger = await _channel.invokeMethod<bool>('getInitialSosTrigger');
      if (initialTrigger == true) {
        _handleTrigger();
      }
    } catch (e) {
      debugPrint('Info: Native SOS trigger check: $e');
    }

    // Sync saved preferences to native Android background service
    await syncSettingsToNative();
  }

  Future<void> _handleTrigger() async {
    if (_isTriggering) return;
    _isTriggering = true;

    try {
      _sosTriggerStreamController.add(null);

      final supa = SupabaseService();
      if (!supa.isAuthenticated) {
        debugPrint('Cannot trigger SOS: user not authenticated');
        return;
      }

      final locService = LocationService();
      final pos = await locService.getCurrentLocation();
      final lat = pos?.latitude ?? 0.0;
      final lng = pos?.longitude ?? 0.0;

      // Get user's circle if available
      final circles = await supa.getMyCircles();
      final circleId = circles.isNotEmpty ? circles.first.id : null;

      await supa.triggerSOS(
        latitude: lat,
        longitude: lng,
        circleId: circleId,
        customMessage: 'DARURAT! Sinyal SOS dipicu melalui Pemicu Cepat!',
      );
      debugPrint('SOS triggered successfully from external trigger.');
    } catch (e) {
      debugPrint('Error executing external SOS trigger: $e');
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        _isTriggering = false;
      });
    }
  }

  Future<bool> isPowerButtonEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('sos_power_button_enabled') ?? true;
  }

  Future<int> getPowerButtonCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sos_power_button_count') ?? 3;
  }

  Future<void> setPowerButtonSettings({required bool enabled, required int count}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_power_button_enabled', enabled);
    await prefs.setInt('sos_power_button_count', count);
    await syncSettingsToNative();
  }

  Future<void> syncSettingsToNative() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('sos_power_button_enabled') ?? true;
      final count = prefs.getInt('sos_power_button_count') ?? 3;

      await _channel.invokeMethod('updatePowerButtonSettings', {
        'enabled': enabled,
        'count': count,
      });
    } catch (e) {
      debugPrint('Info: syncSettingsToNative: $e');
    }
  }

  Future<bool> isPinShortcutSupported() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isPinShortcutSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pinSosShortcut() async {
    try {
      final result = await _channel.invokeMethod<bool>('pinSosShortcut');
      return result ?? false;
    } catch (e) {
      debugPrint('Error pinning SOS shortcut: $e');
      return false;
    }
  }
}
