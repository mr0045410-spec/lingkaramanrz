import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lingkar_aman/models/models.dart';
import 'package:lingkar_aman/services/geofence_service.dart';

void main() {
  group('Sinyal Keras (Loud Signal) Model Tests', () {
    test('LoudSignalModel parsing from Map', () {
      final now = DateTime.now().toIso8601String();
      final map = {
        'id': 'sig-123',
        'sender_id': 'user-a',
        'target_user_id': 'user-b',
        'circle_id': 'circle-1',
        'status': 'pending',
        'created_at': now,
        'stopped_at': null,
      };

      final model = LoudSignalModel.fromMap(map);
      expect(model.id, 'sig-123');
      expect(model.senderId, 'user-a');
      expect(model.targetUserId, 'user-b');
      expect(model.circleId, 'circle-1');
      expect(model.status, 'pending');
      expect(model.stoppedAt, isNull);

      final ringing = model.copyWith(status: 'ringing');
      expect(ringing.status, 'ringing');
      expect(ringing.id, 'sig-123');
    });
  });

  group('Statistik Penggunaan Aplikasi (App Usage) Tests', () {
    test('AppUsageModel parsing from Map', () {
      final now = DateTime.now().toIso8601String();
      final map = {
        'id': 'app-1',
        'user_id': 'user-child',
        'package_name': 'com.google.android.youtube',
        'app_name': 'YouTube',
        'total_time_foreground_seconds': 5400, // 1 hour 30 mins
        'last_time_used': now,
        'report_date': '2026-10-17',
        'updated_at': now,
      };

      final model = AppUsageModel.fromMap(map);
      expect(model.packageName, 'com.google.android.youtube');
      expect(model.appName, 'YouTube');
      expect(model.totalTimeForegroundSeconds, 5400);
      expect(model.reportDate, '2026-10-17');
    });

    test('Screen time calculation and formatting', () {
      final apps = [
        AppUsageModel(
          id: '1',
          userId: 'u1',
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          totalTimeForegroundSeconds: 3600, // 1 hour
          reportDate: '2026-10-17',
          updatedAt: DateTime.now(),
        ),
        AppUsageModel(
          id: '2',
          userId: 'u1',
          packageName: 'com.zhiliaoapp.musically',
          appName: 'TikTok',
          totalTimeForegroundSeconds: 2700, // 45 mins
          reportDate: '2026-10-17',
          updatedAt: DateTime.now(),
        ),
      ];

      final totalSeconds = apps.fold<int>(0, (sum, a) => sum + a.totalTimeForegroundSeconds);
      expect(totalSeconds, 6300); // 1h 45m = 6300s

      String format(int seconds) {
        if (seconds < 60) return '$seconds dtk';
        final mins = seconds ~/ 60;
        final hours = mins ~/ 60;
        final remMins = mins % 60;
        if (hours > 0) return '$hours j $remMins m';
        return '$mins m';
      }

      expect(format(totalSeconds), '1 j 45 m');
    });
  });

  group('Geofencing Otomatis Tests', () {
    test('GeofenceModel & GeofenceEventModel parsing', () {
      final now = DateTime.now().toIso8601String();
      final geoMap = {
        'id': 'geo-home-1',
        'circle_id': 'circle-1',
        'name': 'Rumah',
        'category': 'home',
        'latitude': -6.2088,
        'longitude': 106.8456,
        'radius_meters': 200.0,
        'created_by': 'user-a',
        'created_at': now,
      };

      final geo = GeofenceModel.fromMap(geoMap);
      expect(geo.name, 'Rumah');
      expect(geo.category, 'home');
      expect(geo.radiusMeters, 200.0);

      final eventMap = {
        'id': 'event-1',
        'geofence_id': 'geo-home-1',
        'circle_id': 'circle-1',
        'user_id': 'user-child',
        'event_type': 'entered',
        'created_at': now,
      };

      final event = GeofenceEventModel.fromMap(eventMap);
      expect(event.eventType, 'entered');
      expect(event.geofenceId, 'geo-home-1');

      final enriched = event.copyWith(geofence: geo);
      expect(enriched.geofence?.name, 'Rumah');
    });

    test('Geofence boundary distance calculation', () {
      // Monas Jakarta: -6.175392, 106.827153
      const centerLat = -6.175392;
      const centerLng = 106.827153;
      const radiusMeters = 200.0;

      // Inside Monas courtyard (50m away)
      final insideDistance = Geolocator.distanceBetween(
        centerLat,
        centerLng,
        -6.175700,
        106.827200,
      );
      expect(insideDistance < radiusMeters, isTrue);

      // Outside at Gambir station (~600m away)
      final outsideDistance = Geolocator.distanceBetween(
        centerLat,
        centerLng,
        -6.176600,
        106.832500,
      );
      expect(outsideDistance > radiusMeters, isTrue);
    });

    test('GeofenceTransition notification text', () {
      final geo = GeofenceModel(
        id: 'g1',
        circleId: 'c1',
        name: 'Sekolah SMA 1',
        category: 'school',
        latitude: -6.2,
        longitude: 106.8,
        radiusMeters: 150,
        createdAt: DateTime.now(),
      );

      final enteredTransition = GeofenceTransition(
        geofence: geo,
        userId: 'u1',
        userName: 'Ahmad',
        eventType: 'entered',
        timestamp: DateTime.now(),
      );
      expect(enteredTransition.notificationText, 'Ahmad telah tiba di Sekolah SMA 1');

      final exitedTransition = GeofenceTransition(
        geofence: geo,
        userId: 'u1',
        userName: 'Ahmad',
        eventType: 'exited',
        timestamp: DateTime.now(),
      );
      expect(exitedTransition.notificationText, 'Ahmad telah meninggalkan Sekolah SMA 1');
    });
  });
}
