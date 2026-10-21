import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service untuk menangani Push Notification Token & Device Sync
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final SupabaseClient _supa = Supabase.instance.client;

  bool _isInitialized = false;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Inisialisasi listener Push Notification
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      debugPrint('[PushNotificationService] Memulai inisialisasi push notification...');
      final prefs = await SharedPreferences.getInstance();
      _fcmToken = prefs.getString('cached_fcm_token');

      if (_fcmToken != null && _supa.auth.currentUser != null) {
        await syncTokenToSupabase(_fcmToken!);
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Inisialisasi aman (fallback realtime aktif): $e');
    }
  }

  /// Sinkronisasi token perangkat ke tabel user_devices di Supabase
  Future<void> syncTokenToSupabase(String token) async {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    try {
      _fcmToken = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_fcm_token', token);

      await _supa.from('user_devices').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': 'android',
        'is_active': true,
        'last_seen': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, fcm_token');

      debugPrint('[PushNotificationService] Device token berhasil disinkronkan ke Supabase');
    } catch (e) {
      debugPrint('[PushNotificationService] Sinkronisasi device token ditunda: $e');
    }
  }
}
