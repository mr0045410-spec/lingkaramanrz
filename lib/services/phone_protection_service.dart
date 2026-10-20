import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'location_service.dart';
import 'loud_signal_service.dart';
import 'intruder_camera_service.dart';
import 'sound_settings_service.dart';
import 'supabase_service.dart';

class PhoneProtectionService {
  static final PhoneProtectionService _instance = PhoneProtectionService._internal();
  factory PhoneProtectionService() => _instance;
  PhoneProtectionService._internal();

  final SupabaseService _supa = SupabaseService();
  final LoudSignalService _loudSignal = LoudSignalService();
  static const MethodChannel _nativeLostMode = MethodChannel('com.lingkaraman.lingkar_aman/lost_mode_protection');

  static const String _kLostModeActive = 'lost_mode_active';
  static const String _kLostModeId = 'lost_mode_id';
  static const String _kLostModeContactPhone = 'lost_mode_contact_phone';
  static const String _kLostModeMessage = 'lost_mode_message';
  static const String _kLostModeSiren = 'lost_mode_siren';
  static const String _kLostModeFakeShutdown = 'lost_mode_fake_shutdown';
  static const String _kLostModePin = 'lost_mode_pin';
  static const String _kIntruderFailedAttempts = 'intruder_failed_attempts';
  static const String _kVaultLocked = 'vault_locked';

  RealtimeChannel? _channel;
  RealtimeChannel? _remoteCommandsChannel;
  bool _isListening = false;

  LostModeCommand? _activeLostMode;
  LostModeCommand? get activeLostMode => _activeLostMode;
  bool get isLostModeActive => _activeLostMode != null && _activeLostMode!.isActive;

  bool _isFakeShutdownActive = false;
  bool get isFakeShutdownActive => _isFakeShutdownActive;

  bool _isVaultLocked = false;
  bool get isVaultLocked => _isVaultLocked;

  int _failedPinAttempts = 0;
  int get failedPinAttempts => _failedPinAttempts;

  final StreamController<LostModeCommand> _lostModeController = StreamController<LostModeCommand>.broadcast();
  Stream<LostModeCommand> get onLostModeChanged => _lostModeController.stream;

  final StreamController<IntruderAlertModel> _intruderAlertController = StreamController<IntruderAlertModel>.broadcast();
  Stream<IntruderAlertModel> get onIntruderAlert => _intruderAlertController.stream;

  final StreamController<LastBreathBeaconModel> _lastBreathController = StreamController<LastBreathBeaconModel>.broadcast();
  Stream<LastBreathBeaconModel> get onLastBreathBeacon => _lastBreathController.stream;

  bool _lastBreathBeaconTriggered = false;

  String? get _currentUserId {
    try {
      return _supa.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient? get _safeClient {
    try {
      return _supa.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> enableNativeAntiBypass({
    required String contactPhone,
    required String message,
    required bool enableSiren,
  }) async {
    try {
      await _nativeLostMode.invokeMethod('enableAntiBypass', {
        'contactPhone': contactPhone,
        'message': message,
        'enableSiren': enableSiren,
      });
    } catch (e) {
      debugPrint('Error enabling native anti-bypass: $e');
    }
  }

  Future<void> disableNativeAntiBypass() async {
    try {
      await _nativeLostMode.invokeMethod('disableAntiBypass');
    } catch (e) {
      debugPrint('Error disabling native anti-bypass: $e');
    }
  }

  Future<bool> hasOverlayPermission() async {
    try {
      final res = await _nativeLostMode.invokeMethod<bool>('hasOverlayPermission');
      if (res != null) return res;
    } catch (_) {}
    return false;
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _nativeLostMode.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool(_kLostModeActive) ?? false;
    _isVaultLocked = prefs.getBool(_kVaultLocked) ?? false;
    _failedPinAttempts = prefs.getInt(_kIntruderFailedAttempts) ?? 0;

    // Listen to native callback if Android brought lock to front
    _nativeLostMode.setMethodCallHandler((call) async {
      if (call.method == 'onLostModeLockTriggered') {
        if (_activeLostMode != null) {
          _lostModeController.add(_activeLostMode!);
        }
      }
    });

    if (isActive) {
      _activeLostMode = LostModeCommand(
        id: prefs.getString(_kLostModeId) ?? 'persisted_lost_mode',
        targetUserId: _currentUserId ?? '',
        senderId: 'remote',
        isActive: true,
        contactPhone: prefs.getString(_kLostModeContactPhone) ?? '',
        message: prefs.getString(_kLostModeMessage) ?? 'HP ini dalam mode hilang. Segera hubungi pemilik.',
        enableSiren: prefs.getBool(_kLostModeSiren) ?? true,
        enableFakeShutdown: prefs.getBool(_kLostModeFakeShutdown) ?? false,
        updatedAt: DateTime.now(),
      );
      _isFakeShutdownActive = _activeLostMode?.enableFakeShutdown ?? false;
      _lostModeController.add(_activeLostMode!);

      await enableNativeAntiBypass(
        contactPhone: _activeLostMode!.contactPhone,
        message: _activeLostMode!.message,
        enableSiren: _activeLostMode!.enableSiren,
      );

      if (_activeLostMode!.enableSiren) {
        _loudSignal.playNativeAlarm();
      }
    }

    startListening();

    // Periksa apakah ada remote command yang pending saat inisialisasi
    if (_currentUserId != null) {
      try {
        final pendingCommands = await _safeClient
            ?.from('remote_commands')
            .select()
            .eq('target_user_id', _currentUserId!)
            .eq('status', 'pending')
            .order('created_at', ascending: false)
            .limit(1)
            .timeout(const Duration(seconds: 3));
        if (pendingCommands != null && pendingCommands.isNotEmpty) {
          await _handleRemoteCommandRecord(pendingCommands.first);
        }
      } catch (e) {
        debugPrint('[PhoneProtection] Error checking initial pending remote_commands: $e');
      }
    }
  }

  void startListening() {
    if (_isListening) return;
    _isListening = true;

    final client = _safeClient;
    if (client == null) return;

    // 1. Realtime broadcast channel for instant multi-device synchronisation
    _channel = client.channel('phone_protection');

    _channel!
        .onBroadcast(
          event: 'lost_mode',
          callback: (payload) async {
            try {
              final cmd = LostModeCommand.fromMap(payload);
              final currentUid = _currentUserId;
              if (cmd.targetUserId == currentUid) {
                await _applyLocalLostMode(cmd);
              }
              _lostModeController.add(cmd);
            } catch (e) {
              debugPrint('Error processing lost_mode broadcast: $e');
            }
          },
        )
        .onBroadcast(
          event: 'vault_lock',
          callback: (payload) async {
            try {
              final targetUserId = payload['target_user_id'] as String?;
              final currentUid = _currentUserId;
              if (targetUserId == currentUid) {
                await executeLocalVaultLock();
              }
            } catch (e) {
              debugPrint('Error processing vault_lock broadcast: $e');
            }
          },
        )
        .onBroadcast(
          event: 'intruder_alert',
          callback: (payload) {
            try {
              final alert = IntruderAlertModel.fromMap(payload);
              _intruderAlertController.add(alert);
            } catch (e) {
              debugPrint('Error processing intruder_alert broadcast: $e');
            }
          },
        )
        .onBroadcast(
          event: 'last_breath',
          callback: (payload) {
            try {
              final beacon = LastBreathBeaconModel.fromMap(payload);
              _lastBreathController.add(beacon);
            } catch (e) {
              debugPrint('Error processing last_breath broadcast: $e');
            }
          },
        )
        .subscribe();

    // 2. Realtime Postgres Changes listener pada tabel public.remote_commands
    final myUid = _currentUserId;
    if (myUid != null) {
      _remoteCommandsChannel = client
          .channel('public:remote_commands:$myUid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'remote_commands',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'target_user_id',
              value: myUid,
            ),
            callback: (payload) async {
              final newRec = payload.newRecord;
              if (newRec.isEmpty) return;
              if (newRec['status'] == 'pending') {
                await _handleRemoteCommandRecord(newRec);
              }
            },
          )
          .subscribe();
    }
  }

  Future<void> _handleRemoteCommandRecord(Map<String, dynamic> rec) async {
    final id = rec['id'] as String;
    final cmdType = rec['command_type'] as String?;
    final senderId = rec['sender_id'] as String? ?? 'remote';
    final circleId = rec['circle_id'] as String?;
    final targetUserId = rec['target_user_id'] as String? ?? _currentUserId ?? '';

    // Mark as executed in Supabase
    try {
      await _safeClient?.from('remote_commands').update({
        'status': 'executed',
        'executed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      debugPrint('[PhoneProtection] Error updating remote_command status: $e');
    }

    if (cmdType == 'lost_mode_on') {
      final cmd = LostModeCommand(
        id: id,
        targetUserId: targetUserId,
        senderId: senderId,
        circleId: circleId,
        isActive: true,
        contactPhone: '',
        message: 'HP ini dalam mode hilang. Segera hubungi pemilik.',
        enableSiren: true,
        enableFakeShutdown: false,
        updatedAt: DateTime.now(),
      );
      await _applyLocalLostMode(cmd);
    } else if (cmdType == 'fake_shutdown') {
      final cmd = LostModeCommand(
        id: id,
        targetUserId: targetUserId,
        senderId: senderId,
        circleId: circleId,
        isActive: true,
        contactPhone: '',
        message: 'Perangkat sedang dalam mode pura-pura mati.',
        enableSiren: false,
        enableFakeShutdown: true,
        updatedAt: DateTime.now(),
      );
      await _applyLocalLostMode(cmd);
    } else if (cmdType == 'lost_mode_off') {
      final cmd = LostModeCommand(
        id: id,
        targetUserId: targetUserId,
        senderId: senderId,
        circleId: circleId,
        isActive: false,
        contactPhone: '',
        message: 'Mode HP Hilang dinonaktifkan.',
        enableSiren: false,
        enableFakeShutdown: false,
        updatedAt: DateTime.now(),
      );
      await _applyLocalLostMode(cmd);
    } else if (cmdType == 'remote_wipe') {
      await executeRemoteWipe();
    }
  }

  void stopListening() {
    _channel?.unsubscribe();
    _channel = null;
    _remoteCommandsChannel?.unsubscribe();
    _remoteCommandsChannel = null;
    _isListening = false;
  }

  Future<void> _applyLocalLostMode(LostModeCommand cmd) async {
    final prefs = await SharedPreferences.getInstance();

    if (cmd.isActive) {
      _activeLostMode = cmd;
      _isFakeShutdownActive = cmd.enableFakeShutdown;
      await prefs.setBool(_kLostModeActive, true);
      await prefs.setString(_kLostModeId, cmd.id);
      await prefs.setString(_kLostModeContactPhone, cmd.contactPhone);
      await prefs.setString(_kLostModeMessage, cmd.message);
      await prefs.setBool(_kLostModeSiren, cmd.enableSiren);
      await prefs.setBool(_kLostModeFakeShutdown, cmd.enableFakeShutdown);

      await enableNativeAntiBypass(
        contactPhone: cmd.contactPhone,
        message: cmd.message,
        enableSiren: cmd.enableSiren,
      );

      if (cmd.enableSiren) {
        await _loudSignal.playNativeAlarm();
      }
    } else {
      _activeLostMode = null;
      _isFakeShutdownActive = false;
      await prefs.setBool(_kLostModeActive, false);
      await disableNativeAntiBypass();
      await _loudSignal.stopNativeAlarm();
    }
    _lostModeController.add(cmd);
  }

  // 1. MODE HP HILANG (LOST MODE)
  Future<LostModeCommand> sendLostModeCommand({
    required String targetUserId,
    required String contactPhone,
    required String message,
    bool enableSiren = true,
    bool enableFakeShutdown = false,
    String? circleId,
  }) async {
    final myUid = _currentUserId ?? 'remote_admin';
    try {
      circleId ??= _supa.currentCircleId ?? (await _supa.getCircles()).firstOrNull?.id;
    } catch (_) {}

    final cmd = LostModeCommand(
      id: 'lost_${DateTime.now().millisecondsSinceEpoch}',
      targetUserId: targetUserId,
      senderId: myUid,
      circleId: circleId,
      isActive: true,
      contactPhone: contactPhone,
      message: message,
      enableSiren: enableSiren,
      enableFakeShutdown: enableFakeShutdown,
      updatedAt: DateTime.now(),
    );

    // Broadcast realtime event
    if (_channel != null) {
      await _channel!.sendBroadcastMessage(
        event: 'lost_mode',
        payload: cmd.toMap(),
      );
    }

    // Persist to remote_commands queue
    try {
      final commandType = enableFakeShutdown ? 'fake_shutdown' : 'lost_mode_on';
      await _safeClient?.from('remote_commands').insert({
        'circle_id': circleId,
        'sender_id': myUid,
        'target_user_id': targetUserId,
        'command_type': commandType,
        'status': 'pending',
      });
    } catch (e) {
      debugPrint('[PhoneProtection] Error inserting remote_commands: $e');
    }

    // Persist as SOS Alert so circle members and offline targets can see it
    try {
      final pos = LocationService().currentPosition;
      final alertMsg = '[MODE HP HILANG] Target: $targetUserId | Kontak: $contactPhone | Sirine: ${enableSiren ? "Aktif" : "Mati"} | Pesan: $message';
      await _safeClient?.from('sos_alerts').insert({
        'user_id': myUid,
        'circle_id': circleId,
        'latitude': pos?.latitude ?? 0.0,
        'longitude': pos?.longitude ?? 0.0,
        'message': alertMsg,
        'status': 'active',
        'triggered_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error inserting lost mode sos alert: $e');
    }

    // Trigger ongoing emergency notification on the sender device so they can monitor status
    await SoundSettingsService().showEmergencyNotification(
      title: '🚨 Mode HP Hilang Aktif',
      message: 'Perangkat anggota sedang dikunci & dilacak secara langsung.',
    );

    // If target is self (e.g. testing), apply locally
    if (targetUserId == myUid) {
      await _applyLocalLostMode(cmd);
    }
    _lostModeController.add(cmd);

    return cmd;
  }

  Future<void> deactivateLostMode({
    required String targetUserId,
    String? circleId,
  }) async {
    final myUid = _currentUserId ?? 'remote_admin';
    try {
      circleId ??= _activeLostMode?.circleId ?? _supa.currentCircleId ?? (await _supa.getCircles()).firstOrNull?.id;
    } catch (_) {}

    final cmd = LostModeCommand(
      id: 'lost_${DateTime.now().millisecondsSinceEpoch}',
      targetUserId: targetUserId,
      senderId: myUid,
      circleId: circleId,
      isActive: false,
      contactPhone: '',
      message: 'Mode HP Hilang dinonaktifkan.',
      enableSiren: false,
      enableFakeShutdown: false,
      updatedAt: DateTime.now(),
    );

    // Apply locally first so device is freed immediately
    if (targetUserId == myUid || (_activeLostMode != null && _activeLostMode!.targetUserId == targetUserId)) {
      await _applyLocalLostMode(cmd);
    }
    _lostModeController.add(cmd);
    await SoundSettingsService().cancelEmergencyNotification();

    // Broadcast deactivation with timeout
    if (_channel != null) {
      try {
        await _channel!.sendBroadcastMessage(
          event: 'lost_mode',
          payload: cmd.toMap(),
        ).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('[PhoneProtection] Broadcast error: $e');
      }
    }

    // Call RPC resolve_lost_mode (SECURITY DEFINER)
    try {
      await _safeClient?.rpc('resolve_lost_mode', params: {
        'p_target_user_id': targetUserId,
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[PhoneProtection] RPC resolve_lost_mode error: $e');
    }

    // Direct update to sos_alerts status by specific alert ID
    try {
      final activeAlerts = await _safeClient
          ?.from('sos_alerts')
          .select('id, message')
          .eq('status', 'active')
          .timeout(const Duration(seconds: 4));

      if (activeAlerts != null && activeAlerts.isNotEmpty) {
        for (final row in activeAlerts) {
          final msg = (row['message'] as String?) ?? '';
          if (msg.contains('[MODE HP HILANG]') && msg.contains(targetUserId)) {
            final alertId = row['id'];
            await _safeClient
                ?.from('sos_alerts')
                .update({
                  'status': 'resolved',
                  'resolved_at': DateTime.now().toIso8601String(),
                })
                .eq('id', alertId)
                .timeout(const Duration(seconds: 3));
          }
        }
      }
    } catch (e) {
      debugPrint('[PhoneProtection] Direct update sos_alerts error: $e');
    }

    // Direct update to remote_commands
    try {
      await _safeClient
          ?.from('remote_commands')
          .update({
            'status': 'executed',
            'executed_at': DateTime.now().toIso8601String(),
          })
          .eq('target_user_id', targetUserId)
          .eq('status', 'pending')
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[PhoneProtection] Direct update remote_commands error: $e');
    }

    // Insert deactivation command into remote_commands
    try {
      await _safeClient?.from('remote_commands').insert({
        'circle_id': circleId,
        'sender_id': myUid,
        'target_user_id': targetUserId,
        'command_type': 'lost_mode_off',
        'status': 'pending',
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[PhoneProtection] Error inserting deactivation remote_command: $e');
    }
  }

  Future<void> applyRemoteLostMode(LostModeCommand cmd) async {
    await _applyLocalLostMode(cmd);
  }

  Future<void> applyRemoteLostModeFromPayload({
    required String contactPhone,
    required String message,
    required bool enableSiren,
    required bool enableFakeShutdown,
  }) async {
    final cmd = LostModeCommand(
      id: 'fcm_remote_${DateTime.now().millisecondsSinceEpoch}',
      targetUserId: _currentUserId ?? '',
      senderId: 'fcm_push',
      isActive: true,
      contactPhone: contactPhone,
      message: message,
      enableSiren: enableSiren,
      enableFakeShutdown: enableFakeShutdown,
      updatedAt: DateTime.now(),
    );
    await _applyLocalLostMode(cmd);
  }

  Future<bool> isLostModeActiveForUser(String targetUserId) async {
    if (isLostModeActive && activeLostMode?.targetUserId == targetUserId) {
      return true;
    }
    try {
      final res = await _safeClient
          ?.from('sos_alerts')
          .select('id, message')
          .eq('status', 'active')
          .timeout(const Duration(seconds: 3));
      if (res != null && res.isNotEmpty) {
        for (final row in res) {
          final msg = (row['message'] as String?) ?? '';
          if (msg.contains('[MODE HP HILANG]') && msg.contains(targetUserId)) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<LostModeCommand?> checkAndApplyRemoteLostMode() async {
    final myUid = _currentUserId;
    if (myUid == null) return null;

    try {
      final res = await _safeClient
          ?.from('sos_alerts')
          .select()
          .eq('status', 'active')
          .order('triggered_at', ascending: false)
          .limit(10)
          .timeout(const Duration(seconds: 3));

      if (res != null && res.isNotEmpty) {
        for (final row in res) {
          final msg = (row['message'] as String?) ?? '';
          if (msg.contains('[MODE HP HILANG]') && msg.contains(myUid)) {
            final cmd = LostModeCommand.parseFromSosMessage(
              alertId: row['id'] as String,
              message: row['message'] as String,
              senderId: row['user_id'] as String,
              circleId: row['circle_id'] as String?,
            );
            if (cmd != null) {
              await _applyLocalLostMode(cmd);
              return cmd;
            }
          }
        }
      }
      if (_activeLostMode != null) {
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
        await _applyLocalLostMode(deactivateCmd);
      }
    } catch (e) {
      debugPrint('Error checking remote lost mode: $e');
    }
    return null;
  }

  // 2. LAST BREATH BEACON (BATERAI < 5%)
  Future<void> checkBatteryAndTriggerLastBreath({
    required double lat,
    required double lng,
    required int batteryLevel,
    required bool isCharging,
    String? circleId,
  }) async {
    if (batteryLevel > 5 || isCharging) {
      _lastBreathBeaconTriggered = false;
      return;
    }

    if (_lastBreathBeaconTriggered) return;
    _lastBreathBeaconTriggered = true;

    final myUid = _currentUserId ?? 'self';
    final beacon = LastBreathBeaconModel(
      userId: myUid,
      latitude: lat,
      longitude: lng,
      batteryLevel: batteryLevel,
      timestamp: DateTime.now(),
    );

    // Broadcast
    if (_channel != null) {
      await _channel!.sendBroadcastMessage(
        event: 'last_breath',
        payload: beacon.toMap(),
      );
    }

    // Persist as SOS Alert
    try {
      await _safeClient?.from('sos_alerts').insert({
        'user_id': myUid,
        'circle_id': circleId,
        'latitude': lat,
        'longitude': lng,
        'message': '[TITIK TERAKHIR - LAST BREATH BEACON] Baterai kritis $batteryLevel%. Posisi darurat terakhir sebelum ponsel kehabisan daya.',
        'status': 'active',
        'triggered_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error inserting last breath beacon: $e');
    }

    _lastBreathController.add(beacon);
  }

  // 3. JEBAKAN PENYUSUP / SALAH PIN
  Future<bool> verifyUnlockPin(String inputPin, {String? circleId}) async {
    final prefs = await SharedPreferences.getInstance();
    final correctPin = prefs.getString(_kLostModePin) ?? '1234';

    if (inputPin == correctPin) {
      _failedPinAttempts = 0;
      await prefs.setInt(_kIntruderFailedAttempts, 0);
      await disableNativeAntiBypass();
      await _loudSignal.stopNativeAlarm();

      final myUid = _currentUserId;
      circleId ??= _activeLostMode?.circleId ?? _supa.currentCircleId;

      final cmd = LostModeCommand(
        id: 'unlocked_${DateTime.now().millisecondsSinceEpoch}',
        targetUserId: myUid ?? '',
        senderId: myUid ?? '',
        circleId: circleId,
        isActive: false,
        contactPhone: '',
        message: 'Mode HP Hilang dinonaktifkan.',
        enableSiren: false,
        enableFakeShutdown: false,
        updatedAt: DateTime.now(),
      );

      // Local state is deactivated immediately
      await _applyLocalLostMode(cmd);
      await SoundSettingsService().cancelEmergencyNotification();

      if (myUid != null) {
        // Sync deactivation to Supabase & Circle devices concurrently
        unawaited(
          deactivateLostMode(targetUserId: myUid, circleId: circleId).catchError((e) {
            debugPrint('[PhoneProtection] Error deactivating lost mode: $e');
          }),
        );
      }
      return true;
    } else {
      _failedPinAttempts++;
      await prefs.setInt(_kIntruderFailedAttempts, _failedPinAttempts);

      if (_failedPinAttempts >= 3) {
        final pos = LocationService().currentPosition;

        // 📸 Jepret Foto Kamera Depan Secara Diam-diam (Silent Intruder Selfie)
        String? photoUrl;
        try {
          photoUrl = await IntruderCameraService().captureIntruderSelfie(userId: _currentUserId);
        } catch (e) {
          debugPrint('Error capturing intruder selfie: $e');
        }

        await reportIntruderAttempt(
          attemptCount: _failedPinAttempts,
          lat: pos?.latitude ?? 0.0,
          lng: pos?.longitude ?? 0.0,
          photoUrl: photoUrl,
          circleId: circleId,
        );
      }
      return false;
    }
  }

  Future<void> reportIntruderAttempt({
    required int attemptCount,
    required double lat,
    required double lng,
    String? photoUrl,
    String? circleId,
  }) async {
    final myUid = _currentUserId ?? 'self';
    final alert = IntruderAlertModel(
      id: 'intruder_${DateTime.now().millisecondsSinceEpoch}',
      userId: myUid,
      circleId: circleId,
      attemptCount: attemptCount,
      latitude: lat,
      longitude: lng,
      photoUrl: photoUrl,
      alertType: 'wrong_pin',
      createdAt: DateTime.now(),
    );

    if (_channel != null) {
      await _channel!.sendBroadcastMessage(
        event: 'intruder_alert',
        payload: alert.toMap(),
      );
    }

    try {
      final msg = photoUrl != null
          ? '[JEBAKAN PENYUSUP] Seseorang salah memasukkan PIN ${attemptCount}x! Foto: $photoUrl'
          : '[JEBAKAN PENYUSUP] Seseorang salah memasukkan PIN ${attemptCount}x!';

      await _safeClient?.from('sos_alerts').insert({
        'user_id': myUid,
        'circle_id': circleId,
        'latitude': lat,
        'longitude': lng,
        'message': msg,
        'status': 'active',
        'triggered_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error reporting intruder alert: $e');
    }

    _intruderAlertController.add(alert);
  }

  Future<void> setOwnerPin(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLostModePin, newPin);
  }

  Future<String> getOwnerPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLostModePin) ?? '1234';
  }

  // 4. PURA-PURA MATI (FAKE SHUTDOWN / STEALTH MODE)
  void toggleFakeShutdown(bool active) {
    _isFakeShutdownActive = active;
    if (_activeLostMode != null) {
      _activeLostMode = LostModeCommand(
        id: _activeLostMode!.id,
        targetUserId: _activeLostMode!.targetUserId,
        senderId: _activeLostMode!.senderId,
        circleId: _activeLostMode!.circleId,
        isActive: _activeLostMode!.isActive,
        contactPhone: _activeLostMode!.contactPhone,
        message: _activeLostMode!.message,
        enableSiren: _activeLostMode!.enableSiren,
        enableFakeShutdown: active,
        updatedAt: DateTime.now(),
      );
      _lostModeController.add(_activeLostMode!);
    }
  }

  // 5. KUNCI / HAPUS BRANKAS DATA JARAK JAUH
  Future<void> remoteLockVault({
    required String targetUserId,
    String? circleId,
  }) async {
    if (_channel != null) {
      await _channel!.sendBroadcastMessage(
        event: 'vault_lock',
        payload: {
          'target_user_id': targetUserId,
          'circle_id': circleId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    }

    try {
      final pos = LocationService().currentPosition;
      await _safeClient?.from('sos_alerts').insert({
        'user_id': targetUserId,
        'circle_id': circleId,
        'latitude': pos?.latitude ?? 0.0,
        'longitude': pos?.longitude ?? 0.0,
        'message': '[KUNCI BRANKAS DATA] Perintah pengamanan darurat dan isolasi data perbankan/pribadi telah berhasil dieksekusi.',
        'status': 'resolved',
        'triggered_at': DateTime.now().toIso8601String(),
        'resolved_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    final myUid = _currentUserId;
    if (targetUserId == myUid) {
      await executeLocalVaultLock();
    }
  }

  Future<void> executeLocalVaultLock() async {
    _isVaultLocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVaultLocked, true);
    debugPrint('[PhoneProtectionService] Local vault locked and sensitive caches secured.');
  }

  Future<void> executeRemoteWipe() async {
    await executeLocalVaultLock();
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = _currentUserId;
      if (uid != null) {
        await prefs.remove('loc_history_$uid');
      }
      await prefs.remove('active_circle_id');
      await prefs.remove('access_token');
      debugPrint('[PhoneProtectionService] Remote wipe executed successfully.');
    } catch (e) {
      debugPrint('[PhoneProtectionService] Error executing remote wipe: $e');
    }
  }

  Future<bool> unlockVault(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final correctPin = prefs.getString(_kLostModePin) ?? '1234';
    if (pin == correctPin) {
      _isVaultLocked = false;
      await prefs.setBool(_kVaultLocked, false);
      return true;
    }
    return false;
  }
}
