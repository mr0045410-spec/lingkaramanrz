DateTime _parseDateTime(dynamic val) {
  if (val == null) return DateTime.now();
  if (val is DateTime) return val;
  return DateTime.tryParse(val.toString()) ?? DateTime.now();
}

DateTime? _parseDateTimeNullable(dynamic val) {
  if (val == null) return null;
  if (val is DateTime) return val;
  return DateTime.tryParse(val.toString());
}

class UserProfile {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? emergencyContactPhone;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.emergencyContactPhone,
    this.avatarUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      fullName: (map['full_name'] as String?) ?? 'Pengguna',
      phoneNumber: map['phone_number'] as String?,
      emergencyContactPhone: map['emergency_contact_phone'] as String?,
      avatarUrl: map['avatar_url'] as String?,
    );
  }
}

class CircleModel {
  final String id;
  final String name;
  final String inviteCode;
  final String? createdBy;
  final DateTime createdAt;

  CircleModel({
    required this.id,
    required this.name,
    required this.inviteCode,
    this.createdBy,
    required this.createdAt,
  });

  factory CircleModel.fromMap(Map<String, dynamic> map) {
    return CircleModel(
      id: map['id'] as String,
      name: map['name'] as String,
      inviteCode: map['invite_code'] as String,
      createdBy: map['created_by'] as String?,
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

class CircleMember {
  final String id;
  final String circleId;
  final String userId;
  final String role;
  final bool isSharingLocation;
  final DateTime joinedAt;
  final UserProfile? profile;
  final UserLocation? location;

  CircleMember({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.role,
    required this.isSharingLocation,
    required this.joinedAt,
    this.profile,
    this.location,
  });

  CircleMember copyWith({
    String? role,
    UserProfile? profile,
    UserLocation? location,
  }) {
    return CircleMember(
      id: id,
      circleId: circleId,
      userId: userId,
      role: role ?? this.role,
      isSharingLocation: isSharingLocation,
      joinedAt: joinedAt,
      profile: profile ?? this.profile,
      location: location ?? this.location,
    );
  }

  bool get isAdmin => role == 'admin';

  factory CircleMember.fromMap(Map<String, dynamic> map) {
    return CircleMember(
      id: map['id'] as String,
      circleId: map['circle_id'] as String,
      userId: map['user_id'] as String,
      role: (map['role'] as String?) ?? 'member',
      isSharingLocation: (map['is_sharing_location'] as bool?) ?? true,
      joinedAt: _parseDateTime(map['joined_at']),
    );
  }
}

class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final bool isCharging;
  final double speed;
  final DateTime updatedAt;

  UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.isCharging,
    required this.speed,
    required this.updatedAt,
  });

  factory UserLocation.fromMap(Map<String, dynamic> map) {
    return UserLocation(
      userId: map['user_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      batteryLevel: (map['battery_level'] as num?)?.toInt() ?? 100,
      isCharging: (map['is_charging'] as bool?) ?? false,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }
}

class SosAlert {
  final String id;
  final String userId;
  final String? circleId;
  final double latitude;
  final double longitude;
  final String message;
  final String status;
  final DateTime triggeredAt;
  final DateTime? resolvedAt;
  final UserProfile? senderProfile;

  SosAlert({
    required this.id,
    required this.userId,
    this.circleId,
    required this.latitude,
    required this.longitude,
    required this.message,
    required this.status,
    required this.triggeredAt,
    this.resolvedAt,
    this.senderProfile,
  });

  factory SosAlert.fromMap(Map<String, dynamic> map) {
    return SosAlert(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      circleId: map['circle_id'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      message: (map['message'] as String?) ?? 'DARURAT! Butuh bantuan segera.',
      status: (map['status'] as String?) ?? 'active',
      triggeredAt: _parseDateTime(map['triggered_at']),
      resolvedAt: _parseDateTimeNullable(map['resolved_at']),
    );
  }
}

class CircleMessage {
  final String id;
  final String circleId;
  final String userId;
  final String message;
  final DateTime createdAt;
  final UserProfile? senderProfile;

  CircleMessage({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.message,
    required this.createdAt,
    this.senderProfile,
  });

  factory CircleMessage.fromMap(Map<String, dynamic> map) {
    return CircleMessage(
      id: map['id'] as String,
      circleId: map['circle_id'] as String,
      userId: map['user_id'] as String,
      message: map['message'] as String,
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

class AudioRequestModel {
  final String id;
  final String? circleId;
  final String requesterId;
  final String targetId;
  final String status; // pending, recording, completed, failed
  final String? audioUrl;
  final int durationSeconds;
  final DateTime createdAt;
  final DateTime? completedAt;

  AudioRequestModel({
    required this.id,
    this.circleId,
    required this.requesterId,
    required this.targetId,
    required this.status,
    this.audioUrl,
    required this.durationSeconds,
    required this.createdAt,
    this.completedAt,
  });

  factory AudioRequestModel.fromMap(Map<String, dynamic> map) {
    return AudioRequestModel(
      id: map['id'] as String,
      circleId: map['circle_id'] as String?,
      requesterId: map['requester_id'] as String,
      targetId: map['target_id'] as String,
      status: (map['status'] as String?) ?? 'pending',
      audioUrl: map['audio_url'] as String?,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 15,
      createdAt: _parseDateTime(map['created_at']),
      completedAt: _parseDateTimeNullable(map['completed_at']),
    );
  }

  AudioRequestModel copyWith({
    String? id,
    String? circleId,
    String? requesterId,
    String? targetId,
    String? status,
    String? audioUrl,
    int? durationSeconds,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return AudioRequestModel(
      id: id ?? this.id,
      circleId: circleId ?? this.circleId,
      requesterId: requesterId ?? this.requesterId,
      targetId: targetId ?? this.targetId,
      status: status ?? this.status,
      audioUrl: audioUrl ?? this.audioUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class LoudSignalModel {
  final String id;
  final String senderId;
  final String targetUserId;
  final String? circleId;
  final String status; // pending, ringing, stopped, timeout
  final DateTime createdAt;
  final DateTime? stoppedAt;
  final UserProfile? senderProfile;

  LoudSignalModel({
    required this.id,
    required this.senderId,
    required this.targetUserId,
    this.circleId,
    required this.status,
    required this.createdAt,
    this.stoppedAt,
    this.senderProfile,
  });

  factory LoudSignalModel.fromMap(Map<String, dynamic> map) {
    return LoudSignalModel(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      targetUserId: map['target_user_id'] as String,
      circleId: map['circle_id'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      createdAt: _parseDateTime(map['created_at']),
      stoppedAt: _parseDateTimeNullable(map['stopped_at']),
    );
  }

  LoudSignalModel copyWith({
    String? status,
    DateTime? stoppedAt,
    UserProfile? senderProfile,
  }) {
    return LoudSignalModel(
      id: id,
      senderId: senderId,
      targetUserId: targetUserId,
      circleId: circleId,
      status: status ?? this.status,
      createdAt: createdAt,
      stoppedAt: stoppedAt ?? this.stoppedAt,
      senderProfile: senderProfile ?? this.senderProfile,
    );
  }
}

class AppUsageModel {
  final String id;
  final String userId;
  final String packageName;
  final String appName;
  final int totalTimeForegroundSeconds;
  final DateTime? lastTimeUsed;
  final String reportDate;
  final DateTime updatedAt;

  AppUsageModel({
    required this.id,
    required this.userId,
    required this.packageName,
    required this.appName,
    required this.totalTimeForegroundSeconds,
    this.lastTimeUsed,
    required this.reportDate,
    required this.updatedAt,
  });

  factory AppUsageModel.fromMap(Map<String, dynamic> map) {
    return AppUsageModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      packageName: map['package_name'] as String,
      appName: map['app_name'] as String,
      totalTimeForegroundSeconds: (map['total_time_foreground_seconds'] as num?)?.toInt() ?? 0,
      lastTimeUsed: _parseDateTimeNullable(map['last_time_used']),
      reportDate: map['report_date'] as String,
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }
}

class GeofenceModel {
  final String id;
  final String circleId;
  final String name;
  final String category; // home, school, work, other
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String? createdBy;
  final DateTime createdAt;

  GeofenceModel({
    required this.id,
    required this.circleId,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.createdBy,
    required this.createdAt,
  });

  factory GeofenceModel.fromMap(Map<String, dynamic> map) {
    return GeofenceModel(
      id: map['id'] as String,
      circleId: map['circle_id'] as String,
      name: map['name'] as String,
      category: (map['category'] as String?) ?? 'home',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 150.0,
      createdBy: map['created_by'] as String?,
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

class GeofenceEventModel {
  final String id;
  final String geofenceId;
  final String circleId;
  final String userId;
  final String eventType; // entered, exited
  final DateTime createdAt;
  final GeofenceModel? geofence;
  final UserProfile? userProfile;

  GeofenceEventModel({
    required this.id,
    required this.geofenceId,
    required this.circleId,
    required this.userId,
    required this.eventType,
    required this.createdAt,
    this.geofence,
    this.userProfile,
  });

  factory GeofenceEventModel.fromMap(Map<String, dynamic> map) {
    return GeofenceEventModel(
      id: map['id'] as String,
      geofenceId: map['geofence_id'] as String,
      circleId: map['circle_id'] as String,
      userId: map['user_id'] as String,
      eventType: (map['event_type'] as String?) ?? 'entered',
      createdAt: _parseDateTime(map['created_at']),
    );
  }

  GeofenceEventModel copyWith({
    GeofenceModel? geofence,
    UserProfile? userProfile,
  }) {
    return GeofenceEventModel(
      id: id,
      geofenceId: geofenceId,
      circleId: circleId,
      userId: userId,
      eventType: eventType,
      createdAt: createdAt,
      geofence: geofence ?? this.geofence,
      userProfile: userProfile ?? this.userProfile,
    );
  }
}

class LostModeCommand {
  final String id;
  final String targetUserId;
  final String senderId;
  final String? circleId;
  final bool isActive;
  final String contactPhone;
  final String message;
  final bool enableSiren;
  final bool enableFakeShutdown;
  final DateTime updatedAt;

  LostModeCommand({
    required this.id,
    required this.targetUserId,
    required this.senderId,
    this.circleId,
    required this.isActive,
    required this.contactPhone,
    required this.message,
    this.enableSiren = true,
    this.enableFakeShutdown = true,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'target_user_id': targetUserId,
      'sender_id': senderId,
      'circle_id': circleId,
      'is_active': isActive,
      'contact_phone': contactPhone,
      'message': message,
      'enable_siren': enableSiren,
      'enable_fake_shutdown': enableFakeShutdown,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LostModeCommand.fromMap(Map<String, dynamic> map) {
    return LostModeCommand(
      id: map['id'] as String,
      targetUserId: map['target_user_id'] as String,
      senderId: map['sender_id'] as String,
      circleId: map['circle_id'] as String?,
      isActive: (map['is_active'] as bool?) ?? true,
      contactPhone: (map['contact_phone'] as String?) ?? '',
      message: (map['message'] as String?) ?? 'HP ini dalam pengawasan keluarga.',
      enableSiren: (map['enable_siren'] as bool?) ?? true,
      enableFakeShutdown: (map['enable_fake_shutdown'] as bool?) ?? true,
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }

  static LostModeCommand? parseFromSosMessage({
    required String alertId,
    required String message,
    required String senderId,
    String? circleId,
  }) {
    if (!message.contains('[MODE HP HILANG]')) return null;

    final parts = message.replaceFirst('[MODE HP HILANG]', '').split('|');
    String targetId = '';
    String phone = '';
    bool siren = true;
    String textMsg = 'HP ini dalam mode hilang. Segera hubungi pemilik.';

    for (final part in parts) {
      final kv = part.split(':');
      if (kv.length >= 2) {
        final key = kv[0].trim().toLowerCase();
        final val = kv.sublist(1).join(':').trim();
        if (key == 'target') {
          targetId = val;
        } else if (key == 'kontak' || key == 'phone') {
          phone = val;
        } else if (key == 'sirine' || key == 'siren') {
          siren = val.toLowerCase() == 'aktif' || val.toLowerCase() == 'true';
        } else if (key == 'pesan' || key == 'msg') {
          textMsg = val;
        }
      }
    }

    if (targetId.isEmpty) return null;

    return LostModeCommand(
      id: alertId,
      targetUserId: targetId,
      senderId: senderId,
      circleId: circleId,
      isActive: true,
      contactPhone: phone,
      message: textMsg,
      enableSiren: siren,
      enableFakeShutdown: false,
      updatedAt: DateTime.now(),
    );
  }
}

class IntruderAlertModel {
  final String id;
  final String userId;
  final String? circleId;
  final int attemptCount;
  final double latitude;
  final double longitude;
  final String? photoUrl;
  final String alertType; // wrong_pin, sim_tamper, unauthorized_access
  final DateTime createdAt;

  IntruderAlertModel({
    required this.id,
    required this.userId,
    this.circleId,
    required this.attemptCount,
    required this.latitude,
    required this.longitude,
    this.photoUrl,
    required this.alertType,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'circle_id': circleId,
      'attempt_count': attemptCount,
      'latitude': latitude,
      'longitude': longitude,
      'photo_url': photoUrl,
      'alert_type': alertType,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory IntruderAlertModel.fromMap(Map<String, dynamic> map) {
    return IntruderAlertModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      circleId: map['circle_id'] as String?,
      attemptCount: (map['attempt_count'] as num?)?.toInt() ?? 1,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      photoUrl: map['photo_url'] as String?,
      alertType: (map['alert_type'] as String?) ?? 'wrong_pin',
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

class LastBreathBeaconModel {
  final String userId;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final DateTime timestamp;

  LastBreathBeaconModel({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': batteryLevel,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LastBreathBeaconModel.fromMap(Map<String, dynamic> map) {
    return LastBreathBeaconModel(
      userId: map['user_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      batteryLevel: (map['battery_level'] as num?)?.toInt() ?? 5,
      timestamp: _parseDateTime(map['timestamp']),
    );
  }
}

class TripPoint {
  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final double speed;
  final DateTime recordedAt;

  TripPoint({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.speed,
    required this.recordedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': batteryLevel,
      'speed': speed,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }

  factory TripPoint.fromMap(Map<String, dynamic> map) {
    return TripPoint(
      id: (map['id'] as String?) ?? '',
      userId: map['user_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      batteryLevel: (map['battery_level'] as num?)?.toInt() ?? 100,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      recordedAt: _parseDateTime(map['recorded_at']),
    );
  }
}


