import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'supabase_service.dart';

class GeofenceTransition {
  final GeofenceModel geofence;
  final String userId;
  final String userName;
  final String eventType; // 'entered' or 'exited'
  final DateTime timestamp;

  GeofenceTransition({
    required this.geofence,
    required this.userId,
    required this.userName,
    required this.eventType,
    required this.timestamp,
  });

  String get notificationText {
    if (eventType == 'entered') {
      return '$userName telah tiba di ${geofence.name}';
    } else {
      return '$userName telah meninggalkan ${geofence.name}';
    }
  }
}

class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  final SupabaseService _supa = SupabaseService();

  final Map<String, Set<String>> _memberInsideGeofences = {}; // userId -> Set<geofenceId>
  final StreamController<GeofenceTransition> _transitionController = StreamController<GeofenceTransition>.broadcast();
  Stream<GeofenceTransition> get onTransition => _transitionController.stream;

  RealtimeChannel? _eventsSub;

  Future<List<GeofenceModel>> getGeofences(String circleId) async {
    try {
      final data = await _supa.client
          .from('geofences')
          .select()
          .eq('circle_id', circleId)
          .order('created_at', ascending: true);

      return (data as List).map((d) => GeofenceModel.fromMap(d)).toList();
    } catch (e) {
      debugPrint('Error getting geofences: $e');
      return [];
    }
  }

  Future<GeofenceModel> createGeofence({
    required String circleId,
    required String name,
    required String category,
    required double latitude,
    required double longitude,
    double radiusMeters = 150.0,
  }) async {
    final uid = _supa.currentUser?.id;

    final data = await _supa.client
        .from('geofences')
        .insert({
          'circle_id': circleId,
          'name': name,
          'category': category,
          'latitude': latitude,
          'longitude': longitude,
          'radius_meters': radiusMeters,
          'created_by': uid,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return GeofenceModel.fromMap(data);
  }

  Future<void> deleteGeofence(String id) async {
    await _supa.client.from('geofences').delete().eq('id', id);
  }

  Future<List<GeofenceEventModel>> getRecentEvents(String circleId, {int limit = 20}) async {
    try {
      final data = await _supa.client
          .from('geofence_events')
          .select('*, geofences(*), profiles(*)')
          .eq('circle_id', circleId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List).map((d) {
        final event = GeofenceEventModel.fromMap(d);
        GeofenceModel? g;
        if (d['geofences'] != null) {
          g = GeofenceModel.fromMap(d['geofences'] as Map<String, dynamic>);
        }
        UserProfile? p;
        if (d['profiles'] != null) {
          p = UserProfile.fromMap(d['profiles'] as Map<String, dynamic>);
        }
        return event.copyWith(geofence: g, userProfile: p);
      }).toList();
    } catch (e) {
      debugPrint('Error getting recent geofence events: $e');
      return [];
    }
  }

  void subscribeToCircleEvents(String circleId) {
    subscribeToEvents(circleId, (event) {
      if (event.userProfile?.id != _supa.currentUser?.id) {
        final transition = GeofenceTransition(
          geofence: event.geofence ??
              GeofenceModel(
                id: event.geofenceId,
                circleId: circleId,
                name: 'Zona Aman',
                category: 'other',
                latitude: 0,
                longitude: 0,
                radiusMeters: 150,
                createdAt: DateTime.now(),
              ),
          userId: event.userId,
          userName: event.userProfile?.fullName ?? 'Anggota',
          eventType: event.eventType,
          timestamp: event.createdAt,
        );
        _transitionController.add(transition);
      }
    });
  }

  void subscribeToEvents(String circleId, Function(GeofenceEventModel) onEvent) {
    _eventsSub?.unsubscribe();
    _eventsSub = _supa.client
        .channel('public:geofence_events:$circleId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'geofence_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'circle_id',
            value: circleId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isEmpty) return;

            final event = GeofenceEventModel.fromMap(newRecord);
            // Fetch associated geofence & profile
            try {
              final gData = await _supa.client.from('geofences').select().eq('id', event.geofenceId).maybeSingle();
              final pData = await _supa.client.from('profiles').select().eq('id', event.userId).maybeSingle();

              final enriched = event.copyWith(
                geofence: gData != null ? GeofenceModel.fromMap(gData) : null,
                userProfile: pData != null ? UserProfile.fromMap(pData) : null,
              );
              onEvent(enriched);
            } catch (_) {
              onEvent(event);
            }
          },
        )
        .subscribe();
  }

  void stopListening() {
    unsubscribeFromEvents();
  }

  void unsubscribeFromEvents() {
    _eventsSub?.unsubscribe();
    _eventsSub = null;
  }

  Future<void> evaluateCircleGeofences({
    required String circleId,
    required List<CircleMember> members,
  }) async {
    final geofences = await getGeofences(circleId);
    if (geofences.isEmpty) return;

    for (var m in members) {
      final loc = m.location;
      if (loc != null) {
        await checkMemberLocationAgainstGeofences(
          geofences: geofences,
          circleId: circleId,
          userId: m.userId,
          latitude: loc.latitude,
          longitude: loc.longitude,
          userName: m.profile?.fullName ?? 'Anggota',
        );
      }
    }
  }

  /// Evaluates member's coordinate against circle geofences
  Future<void> checkMemberLocationAgainstGeofences({
    required List<GeofenceModel> geofences,
    required String circleId,
    required String userId,
    required double latitude,
    required double longitude,
    required String userName,
  }) async {
    if (geofences.isEmpty) return;

    final currentInside = _memberInsideGeofences[userId] ?? <String>{};
    final nowInside = <String>{};

    for (var g in geofences) {
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        g.latitude,
        g.longitude,
      );

      final isInside = distance <= g.radiusMeters;
      if (isInside) {
        nowInside.add(g.id);

        if (!currentInside.contains(g.id)) {
          // Just entered
          await _recordEvent(
            geofence: g,
            circleId: circleId,
            userId: userId,
            userName: userName,
            eventType: 'entered',
          );
        }
      } else {
        if (currentInside.contains(g.id)) {
          // Just exited
          await _recordEvent(
            geofence: g,
            circleId: circleId,
            userId: userId,
            userName: userName,
            eventType: 'exited',
          );
        }
      }
    }

    _memberInsideGeofences[userId] = nowInside;
  }

  Future<void> _recordEvent({
    required GeofenceModel geofence,
    required String circleId,
    required String userId,
    required String userName,
    required String eventType,
  }) async {
    try {
      await _supa.client.from('geofence_events').insert({
        'geofence_id': geofence.id,
        'circle_id': circleId,
        'user_id': userId,
        'event_type': eventType,
        'created_at': DateTime.now().toIso8601String(),
      });

      final transition = GeofenceTransition(
        geofence: geofence,
        userId: userId,
        userName: userName,
        eventType: eventType,
        timestamp: DateTime.now(),
      );

      _transitionController.add(transition);
    } catch (e) {
      debugPrint('Error recording geofence event: $e');
    }
  }
}
