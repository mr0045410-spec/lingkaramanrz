import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'phone_protection_service.dart';
import 'loud_signal_service.dart';

/// Service untuk menangani Push Notification & High-Priority Remote Wakeup (FCM)
/// Dirancang modular dengan graceful fallback jika Firebase belum terkonfigurasi.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final SupabaseClient _supa = Supabase.instance.client;
  final PhoneProtectionService _phoneProtectionService = PhoneProtectionService();
  final LoudSignalService _loudSignalService = LoudSignalService();

  bool _isInitialized = false;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Inisialisasi listener Push Notification
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      debugPrint('[PushNotificationService] Memulai inisialisasi push notification...');
      // Membaca token cache lokal jika ada
      final prefs = await SharedPreferences.getInstance();
      _fcmToken = prefs.getString('cached_fcm_token');

      if (_fcmToken != null && _supa.auth.currentUser != null) {
        await syncTokenToSupabase(_fcmToken!);
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Inisialisasi aman (fallback realtime aktif): $e');
    }
  }

  /// Sinkronisasi token FCM ke tabel user_devices di Supabase
  Future<void> syncTokenToSupabase(String token) async {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    try {
      _fcmToken = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_fcm_token', token);

      // Simpan/Update token di tabel user_devices
      await _supa.from('user_devices').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': 'android',
        'is_active': true,
        'last_seen': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, fcm_token');

      debugPrint('[PushNotificationService] FCM token berhasil disinkronkan ke Supabase');
    } catch (e) {
      debugPrint('[PushNotificationService] Gagal sinkronisasi token (tabel user_devices belum aktif): $e');
    }
  }

  /// Handler payload pesan darurat (Data Payload) yang diterima dari FCM
  /// Dapat dipanggil di background maupun foreground
  Future<void> handleRemoteEmergencyPayload(Map<String, dynamic> data) async {
    try {
      final type = data['type'] as String? ?? data['command_type'] as String?;
      final targetUserId = data['target_user_id'] as String?;
      final currentUid = _supa.auth.currentUser?.id;

      debugPrint('[PushNotificationService] Menerima data payload: $type untuk target: $targetUserId');

      // 1. Perintah Penguncian Mode HP Hilang
      if (type == 'lost_mode' || type == 'lost_mode_on' || type == 'fake_shutdown') {
        if (targetUserId == null || targetUserId == currentUid) {
          final contactPhone = data['contact_phone'] as String? ?? '';
          final message = data['message'] as String? ?? 'HP ini dalam mode hilang.';
          final enableSiren = data['enable_siren'] == 'true' || data['enable_siren'] == true;
          final enableFakeShutdown = type == 'fake_shutdown' || data['enable_fake_shutdown'] == 'true' || data['enable_fake_shutdown'] == true;

          await _phoneProtectionService.applyRemoteLostModeFromPayload(
            contactPhone: contactPhone,
            message: message,
            enableSiren: enableSiren,
            enableFakeShutdown: enableFakeShutdown,
          );
        }
      }

      // 2. Perintah Sinyal Keras Tembus Silent
      if (type == 'loud_signal') {
        if (targetUserId == null || targetUserId == currentUid) {
          await _loudSignalService.playNativeAlarm();
        }
      }

      // 3. Perintah Nonaktifkan Penguncian
      if (type == 'lost_mode_off' || type == 'resolve_lost_mode') {
        if (targetUserId == null || targetUserId == currentUid) {
          if (currentUid != null) {
            await _phoneProtectionService.deactivateLostMode(targetUserId: currentUid);
          }
        }
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Error handling payload: $e');
    }
  }
}
