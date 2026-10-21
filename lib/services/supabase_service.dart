import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import '../models/models.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static double? _lastRecordedLat;
  static double? _lastRecordedLng;

  SupabaseClient get _client => Supabase.instance.client;
  SupabaseClient get client => _client;

  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  // ---------------- AUTH ----------------
  Future<void> sendEmailOtp({
    required String email,
    bool shouldCreateUser = true,
    String? fullName,
    String? phoneNumber,
  }) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: shouldCreateUser,
      data: {
        if (fullName != null && fullName.isNotEmpty) 'full_name': fullName.trim(),
        if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone': phoneNumber.trim(),
      },
    );
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      serverClientId: AppConstants.googleWebClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Login Google dibatalkan oleh pengguna.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('Gagal mendapatkan ID Token dari Google. Pastikan SHA-1 sudah terdaftar.');
    }

    return await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone': phoneNumber,
      },
    );

    // Profile is automatically created by the handle_new_user database trigger.
    if (response.session != null && phoneNumber != null && phoneNumber.isNotEmpty) {
      try {
        await _client.from('profiles').update({
          'phone_number': phoneNumber,
        }).eq('id', response.user!.id);
      } catch (_) {}
    }
    return response;
  }

  Future<void> signOut() async {
    try {
      final googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (_) {}
    await _client.auth.signOut();
  }

  // ---------------- PROFILE ----------------
  Future<UserProfile?> getProfile([String? userId]) async {
    final uid = userId ?? currentUser?.id;
    if (uid == null) return null;

    final data = await _client.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return UserProfile.fromMap(data);
  }

  Future<UserProfile?> getMyProfile() => getProfile();

  Future<void> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? emergencyContactPhone,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (fullName != null) updates['full_name'] = fullName;
    if (phoneNumber != null) updates['phone_number'] = phoneNumber;
    if (emergencyContactPhone != null) updates['emergency_contact_phone'] = emergencyContactPhone;
    if (clearAvatar) {
      updates['avatar_url'] = null;
    } else if (avatarUrl != null) {
      updates['avatar_url'] = avatarUrl;
    }

    await _client.from('profiles').update(updates).eq('id', uid);
  }

  /// Upload foto profil ke Supabase Storage dan perbarui profiles.avatar_url
  Future<String> uploadAvatar(File imageFile) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');
    final bytes = await imageFile.readAsBytes();
    final ext = imageFile.path.split('.').last.toLowerCase();
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'avatars/${uid}_$timestamp.$ext';

    String publicUrl;
    try {
      await _client.storage.from('avatars').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
      publicUrl = _client.storage.from('avatars').getPublicUrl(storagePath);
    } catch (_) {
      // Fallback ke bucket 'ambient_audio' pada subfolder 'avatars/'
      final fallbackPath = 'avatars/${uid}_$timestamp.$ext';
      await _client.storage.from('ambient_audio').uploadBinary(
        fallbackPath,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
      publicUrl = _client.storage.from('ambient_audio').getPublicUrl(fallbackPath);
    }

    await updateProfile(avatarUrl: publicUrl);
    return publicUrl;
  }

  // ---------------- CIRCLES ----------------
  String? currentCircleId;

  Future<List<CircleModel>> getCircles() => getMyCircles();

  Future<List<CircleModel>> getMyCircles() async {
    final uid = currentUser?.id;
    if (uid == null) return [];

    final res = await _client
        .from('circle_members')
        .select('circle_id, circles(*)')
        .eq('user_id', uid);

    final List<CircleModel> list = [];
    for (var item in res) {
      if (item['circles'] != null) {
        list.add(CircleModel.fromMap(item['circles'] as Map<String, dynamic>));
      }
    }
    if (list.isNotEmpty && currentCircleId == null) {
      currentCircleId = list.first.id;
    }
    return list;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  Future<CircleModel> createCircle(String name) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');

    final code = _generateInviteCode();
    final circleData = await _client
        .from('circles')
        .insert({
          'name': name,
          'invite_code': code,
          'created_by': uid,
        })
        .select()
        .single();

    final circle = CircleModel.fromMap(circleData);

    // Add creator as admin member
    await _client.from('circle_members').insert({
      'circle_id': circle.id,
      'user_id': uid,
      'role': 'admin',
      'is_sharing_location': true,
    });

    return circle;
  }

  Future<void> joinCircleByCode(String code) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');

    final cleanCode = code.trim().toUpperCase();

    try {
      final res = await _client.rpc('join_circle_by_code', params: {'p_code': cleanCode});
      if (res != null) return;
    } catch (_) {}

    final circleData = await _client
        .from('circles')
        .select('id, created_by')
        .eq('invite_code', cleanCode)
        .maybeSingle();

    if (circleData == null) {
      throw Exception('Kode lingkaran tidak valid atau tidak ditemukan');
    }

    final circleId = circleData['id'] as String;
    final createdBy = circleData['created_by'] as String?;

    // Rule: Hanya pembuat lingkaran yang menjadi 'admin'. Siapapun yang gabung via kode selalu 'member'
    final strictRole = (uid == createdBy) ? 'admin' : 'member';

    await _client.from('circle_members').upsert(
      {
        'circle_id': circleId,
        'user_id': uid,
        'role': strictRole,
        'is_sharing_location': true,
      },
      onConflict: 'circle_id,user_id',
    );
  }

  Future<int> normalizeCircleRoles(String circleId) async {
    try {
      final res = await _client.rpc('normalize_circle_roles', params: {'p_circle_id': circleId});
      final count = (res as num?)?.toInt() ?? 0;
      debugPrint('[SupabaseService] normalize_circle_roles berhasil memperbaiki $count baris admin di circle $circleId');
      return count;
    } catch (e, st) {
      debugPrint('[SupabaseService] GAGAL menjalankan normalize_circle_roles untuk circle $circleId: $e\n$st');
      rethrow;
    }
  }

  Future<List<CircleMember>> getCircleMembers(String circleId) async {
    final membersData = await _client
        .from('circle_members')
        .select('*, profiles(*)')
        .eq('circle_id', circleId);

    // Ambil info pembuat lingkaran untuk kepastian hierarki peran
    final circleInfo = await _client
        .from('circles')
        .select('created_by')
        .eq('id', circleId)
        .maybeSingle();
    final creatorId = circleInfo?['created_by'] as String?;

    final List<CircleMember> members = [];
    final List<String> userIds = [];
    bool needsRoleNormalization = false;

    for (var m in membersData) {
      final rawMember = CircleMember.fromMap(m);
      UserProfile? prof;
      if (m['profiles'] != null) {
        prof = UserProfile.fromMap(m['profiles'] as Map<String, dynamic>);
      }

      // Pastikan ketegasan peran:
      // Hanya pembuat (creatorId) yang berhak menjadi Admin. Anggota lain selalu 'member'.
      String effectiveRole = rawMember.role;
      if (creatorId != null) {
        if (rawMember.userId == creatorId) {
          effectiveRole = 'admin';
        } else if (rawMember.role == 'admin') {
          // Normalisasi anomali database lama ke member
          effectiveRole = 'member';
          needsRoleNormalization = true;
        }
      }

      final member = rawMember.copyWith(role: effectiveRole, profile: prof);
      members.add(member);
      userIds.add(member.userId);
    }

    if (needsRoleNormalization) {
      try {
        final fixedRows = await _client.rpc('normalize_circle_roles', params: {'p_circle_id': circleId});
        debugPrint('[SupabaseService] normalize_circle_roles berhasil memperbaiki $fixedRows baris admin di circle $circleId');
      } catch (e, st) {
        debugPrint('[SupabaseService] GAGAL menjalankan normalize_circle_roles untuk circle $circleId: $e\n$st');
      }
    }

    // Fetch locations for all users in circle
    if (userIds.isNotEmpty) {
      final locsData = await _client
          .from('user_locations')
          .select()
          .filter('user_id', 'in', userIds);

      final Map<String, UserLocation> locMap = {};
      for (var l in locsData) {
        final loc = UserLocation.fromMap(l);
        locMap[loc.userId] = loc;
      }

      for (int i = 0; i < members.length; i++) {
        final m = members[i];
        if (locMap.containsKey(m.userId)) {
          members[i] = m.copyWith(location: locMap[m.userId]);
        }
      }
    }

    return members;
  }

  Future<void> leaveCircle(String circleId) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');
    await _client
        .from('circle_members')
        .delete()
        .eq('circle_id', circleId)
        .eq('user_id', uid);
  }

  Future<void> removeMember(String circleId, String memberUserId) async {
    await _client
        .from('circle_members')
        .delete()
        .eq('circle_id', circleId)
        .eq('user_id', memberUserId);
  }

  Future<void> deleteMyAccount() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');
    try {
      await _client.rpc('delete_my_account');
    } catch (_) {
      // Fallback penghapusan profil relasional mandiri
      await _client.from('profiles').delete().eq('id', uid);
    }
    await signOut();
  }

  // ---------------- REALTIME LOCATIONS & RIWAYAT PERJALANAN ----------------
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    required int batteryLevel,
    bool isCharging = false,
    double speed = 0.0,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    await _client.from('user_locations').upsert({
      'user_id': uid,
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': batteryLevel,
      'is_charging': isCharging,
      'speed': speed,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Catat juga ke linimasa / riwayat perjalanan
    await recordLocationHistory(
      latitude: latitude,
      longitude: longitude,
      batteryLevel: batteryLevel,
      speed: speed,
    );
  }

  Future<void> recordLocationHistory({
    required double latitude,
    required double longitude,
    required int batteryLevel,
    double speed = 0.0,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    // Filter pergeseran minimal 15 meter untuk menghemat kuota database & baterai
    if (_lastRecordedLat != null && _lastRecordedLng != null) {
      final distance = Geolocator.distanceBetween(
        _lastRecordedLat!,
        _lastRecordedLng!,
        latitude,
        longitude,
      );
      if (distance < 15.0) {
        return; // Belum bergeser 15 meter, lewati
      }
    }

    _lastRecordedLat = latitude;
    _lastRecordedLng = longitude;

    final now = DateTime.now();
    final newPoint = TripPoint(
      id: 'local_${now.millisecondsSinceEpoch}',
      userId: uid,
      latitude: latitude,
      longitude: longitude,
      batteryLevel: batteryLevel,
      speed: speed,
      recordedAt: now,
    );

    // 1. Simpan ke cache lokal perangkat
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'loc_history_$uid';
      final cachedList = prefs.getStringList(cacheKey) ?? [];
      cachedList.insert(0, jsonEncode(newPoint.toMap()));
      if (cachedList.length > 200) {
        cachedList.removeRange(200, cachedList.length);
      }
      await prefs.setStringList(cacheKey, cachedList);
    } catch (_) {}

    // 2. Simpan ke tabel Supabase jika tersedia
    try {
      await _client.from('location_history').insert({
        'user_id': uid,
        'latitude': latitude,
        'longitude': longitude,
        'battery_level': batteryLevel,
        'speed': speed,
        'recorded_at': now.toIso8601String(),
      });
    } catch (_) {}
  }

  Future<List<TripPoint>> getLocationHistory(String userId, {int limit = 60}) async {
    final List<TripPoint> points = [];

    // 1. Coba ambil dari database Supabase
    try {
      final res = await _client
          .from('location_history')
          .select()
          .eq('user_id', userId)
          .order('recorded_at', ascending: false)
          .limit(limit);

      for (var row in res) {
        points.add(TripPoint.fromMap(row));
      }
    } catch (_) {}

    // 2. Jika database kosong atau offline, ambil dari cache lokal
    if (points.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'loc_history_$userId';
        final cachedList = prefs.getStringList(cacheKey) ?? [];
        for (var item in cachedList.take(limit)) {
          final map = jsonDecode(item) as Map<String, dynamic>;
          points.add(TripPoint.fromMap(map));
        }
      } catch (_) {}
    }

    // 3. Sertakan posisi terakhir dari user_locations jika points masih kosong
    if (points.isEmpty) {
      try {
        final lastLoc = await _client
            .from('user_locations')
            .select()
            .eq('user_id', userId)
            .maybeSingle();

        if (lastLoc != null) {
          points.add(TripPoint(
            id: 'current',
            userId: userId,
            latitude: (lastLoc['latitude'] as num).toDouble(),
            longitude: (lastLoc['longitude'] as num).toDouble(),
            batteryLevel: (lastLoc['battery_level'] as num?)?.toInt() ?? 100,
            speed: (lastLoc['speed'] as num?)?.toDouble() ?? 0.0,
            recordedAt: DateTime.parse(lastLoc['updated_at'] as String),
          ));
        }
      } catch (_) {}
    }

    return points;
  }

  RealtimeChannel subscribeToLocations(void Function(UserLocation) onLocationUpdate) {
    return _client
        .channel('public:user_locations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_locations',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              final loc = UserLocation.fromMap(payload.newRecord);
              onLocationUpdate(loc);
            }
          },
        )
        .subscribe();
  }

  // ---------------- EMERGENCY SOS ----------------
  Future<SosAlert> triggerSOS({
    required double latitude,
    required double longitude,
    String? circleId,
    String? customMessage,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');

    final data = await _client
        .from('sos_alerts')
        .insert({
          'user_id': uid,
          'circle_id': circleId,
          'latitude': latitude,
          'longitude': longitude,
          'message': customMessage ?? 'DARURAT! Saya butuh bantuan segera.',
          'status': 'active',
          'triggered_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return SosAlert.fromMap(data);
  }

  Future<void> resolveSOS(String alertId) async {
    await _client.from('sos_alerts').update({
      'status': 'resolved',
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('id', alertId);
  }

  Future<List<SosAlert>> getActiveAlerts([String? circleId]) async {
    var query = _client.from('sos_alerts').select('*, profiles(*)').eq('status', 'active');
    if (circleId != null) {
      query = query.or('circle_id.eq.$circleId,circle_id.is.null');
    }
    final data = await query.order('triggered_at', ascending: false);

    return data.map((d) {
      final alert = SosAlert.fromMap(d);
      UserProfile? prof;
      if (d['profiles'] != null) {
        prof = UserProfile.fromMap(d['profiles'] as Map<String, dynamic>);
      }
      return SosAlert(
        id: alert.id,
        userId: alert.userId,
        circleId: alert.circleId,
        latitude: alert.latitude,
        longitude: alert.longitude,
        message: alert.message,
        status: alert.status,
        triggeredAt: alert.triggeredAt,
        resolvedAt: alert.resolvedAt,
        senderProfile: prof,
      );
    }).toList();
  }

  RealtimeChannel subscribeToSosAlerts(void Function(SosAlert) onAlert) {
    return _client
        .channel('public:sos_alerts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sos_alerts',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              final alert = SosAlert.fromMap(payload.newRecord);
              onAlert(alert);
            }
          },
        )
        .subscribe();
  }

  // ---------------- CHAT / KOMUNITAS ----------------
  Future<void> sendMessage(String circleId, String message) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');

    await _client.from('circle_messages').insert({
      'circle_id': circleId,
      'user_id': uid,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<CircleMessage>> getMessages(String circleId, {int limit = 50}) async {
    final data = await _client
        .from('circle_messages')
        .select('*, profiles(*)')
        .eq('circle_id', circleId)
        .order('created_at', ascending: true)
        .limit(limit);

    return data.map((d) {
      final msg = CircleMessage.fromMap(d);
      UserProfile? prof;
      if (d['profiles'] != null) {
        prof = UserProfile.fromMap(d['profiles'] as Map<String, dynamic>);
      }
      return CircleMessage(
        id: msg.id,
        circleId: msg.circleId,
        userId: msg.userId,
        message: msg.message,
        createdAt: msg.createdAt,
        senderProfile: prof,
      );
    }).toList();
  }

  RealtimeChannel subscribeToMessages(String circleId, void Function(CircleMessage) onMessage, {String channelSuffix = 'global'}) {
    return _client
        .channel('public:circle_messages:${circleId}_$channelSuffix')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'circle_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'circle_id',
            value: circleId,
          ),
          callback: (payload) async {
            if (payload.newRecord.isNotEmpty) {
              final msg = CircleMessage.fromMap(payload.newRecord);
              try {
                final profData = await _client.from('profiles').select().eq('id', msg.userId).maybeSingle();
                if (profData != null) {
                  final prof = UserProfile.fromMap(profData);
                  onMessage(CircleMessage(
                    id: msg.id,
                    circleId: msg.circleId,
                    userId: msg.userId,
                    message: msg.message,
                    createdAt: msg.createdAt,
                    senderProfile: prof,
                  ));
                  return;
                }
              } catch (_) {}
              onMessage(msg);
            }
          },
        )
        .subscribe();
  }

  // ---------------- AMBIENT AUDIO REQUESTS ----------------
  Future<AudioRequestModel> createAudioRequest({
    required String targetUserId,
    String? circleId,
    int durationSeconds = 15,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Belum login');

    final data = await _client.from('audio_requests').insert({
      'circle_id': circleId,
      'requester_id': uid,
      'target_id': targetUserId,
      'status': 'pending',
      'duration_seconds': durationSeconds,
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    return AudioRequestModel.fromMap(data);
  }

  Future<void> updateAudioRequest(
    String requestId, {
    required String status,
    String? audioUrl,
  }) async {
    final updateData = <String, dynamic>{
      'status': status,
    };
    if (audioUrl != null) {
      updateData['audio_url'] = audioUrl;
      updateData['completed_at'] = DateTime.now().toIso8601String();
    }
    await _client.from('audio_requests').update(updateData).eq('id', requestId);
  }

  Future<String> uploadAudioFile(String localFilePath, String storagePath) async {
    final file = File(localFilePath);
    final bytes = await file.readAsBytes();
    await _client.storage.from('ambient_audio').uploadBinary(
      storagePath,
      bytes,
      fileOptions: const FileOptions(contentType: 'audio/m4a', upsert: true),
    );
    return _client.storage.from('ambient_audio').getPublicUrl(storagePath);
  }

  Future<AudioRequestModel?> getAudioRequestById(String requestId) async {
    final data = await _client
        .from('audio_requests')
        .select()
        .eq('id', requestId)
        .maybeSingle();

    if (data == null) return null;
    return AudioRequestModel.fromMap(data);
  }

  Future<List<AudioRequestModel>> getAudioRequestsForTarget(String targetUserId, {int limit = 10}) async {
    final data = await _client
        .from('audio_requests')
        .select()
        .eq('target_id', targetUserId)
        .eq('status', 'completed')
        .order('created_at', ascending: false)
        .limit(limit);

    return data.map((d) => AudioRequestModel.fromMap(d)).toList();
  }

  RealtimeChannel subscribeToMyAudioRequests(void Function(AudioRequestModel) onRequest) {
    final uid = currentUser?.id;
    return _client
        .channel('public:audio_requests:target_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'audio_requests',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              final req = AudioRequestModel.fromMap(payload.newRecord);
              if (req.targetId == uid && req.status == 'pending') {
                onRequest(req);
              }
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel subscribeToSpecificAudioRequest(
    String requestId,
    void Function(AudioRequestModel) onUpdate,
  ) {
    return _client
        .channel('public:audio_requests:$requestId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'audio_requests',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              final req = AudioRequestModel.fromMap(payload.newRecord);
              if (req.id == requestId) {
                onUpdate(req);
              }
            }
          },
        )
        .subscribe();
  }
}

