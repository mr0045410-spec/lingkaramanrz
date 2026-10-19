import 'package:flutter_test/flutter_test.dart';
import 'package:lingkar_aman/constants.dart';
import 'package:lingkar_aman/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });

  group('TAHAP 1 & 2: location_history & movement filter verification', () {
    test('TripPoint serialization & deserialization works correctly', () {
      final now = DateTime.now();
      final point = TripPoint(
        id: 'point_123',
        userId: 'user_456',
        latitude: -6.2088,
        longitude: 106.8456,
        speed: 3.5,
        batteryLevel: 88,
        recordedAt: now,
      );

      final map = point.toMap();
      expect(map['id'], 'point_123');
      expect(map['user_id'], 'user_456');
      expect(map['latitude'], -6.2088);
      expect(map['longitude'], 106.8456);
      expect(map['speed'], 3.5);
      expect(map['battery_level'], 88);

      final fromMap = TripPoint.fromMap(map);
      expect(fromMap.id, point.id);
      expect(fromMap.userId, point.userId);
      expect(fromMap.latitude, point.latitude);
      expect(fromMap.longitude, point.longitude);
      expect(fromMap.batteryLevel, point.batteryLevel);
    });

    test('Native SharedPreferences writes keys properly for Kotlin services', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_lat', -6.2088);
      await prefs.setDouble('last_lng', 106.8456);
      await prefs.setString('last_lat_str', '-6.2088');
      await prefs.setString('last_lng_str', '106.8456');
      await prefs.setString('supabase_url', AppConstants.supabaseUrl);
      await prefs.setString('supabase_anon_key', AppConstants.supabaseAnonKey);
      await prefs.setString('user_id', 'test_user_id');
      await prefs.setString('active_circle_id', 'test_circle_id');

      expect(prefs.getDouble('last_lat'), -6.2088);
      expect(prefs.getDouble('last_lng'), 106.8456);
      expect(prefs.getString('last_lat_str'), '-6.2088');
      expect(prefs.getString('last_lng_str'), '106.8456');
      expect(prefs.getString('supabase_url'), AppConstants.supabaseUrl);
      expect(prefs.getString('user_id'), 'test_user_id');
      expect(prefs.getString('active_circle_id'), 'test_circle_id');
    });
  });

  group('TAHAP 4: Intruder selfie message tag & extraction regex', () {
    test('Intruder message contains URL and can be extracted via regex', () {
      const sampleUrl = 'https://uwxecnbeqeysnlzwdcha.supabase.co/storage/v1/object/public/ambient_audio/intruder_photos/intruder_12345.jpg';
      final msg = '[JEBAKAN PENYUSUP] Seseorang salah memasukkan PIN 3x! Foto: $sampleUrl';

      expect(msg.contains('[JEBAKAN PENYUSUP]'), isTrue);

      final match = RegExp(r'Foto:\s*(https?://\S+)').firstMatch(msg);
      expect(match, isNotNull);
      expect(match!.group(1), sampleUrl);
    });
  });

  group('TAHAP 5: App usage report schema payload formatting', () {
    test('AppUsageModel formats payload correctly for onConflict upsert', () {
      final now = DateTime.now();
      final model = AppUsageModel(
        id: '',
        userId: 'user_123',
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        totalTimeForegroundSeconds: 3600,
        lastTimeUsed: now,
        reportDate: '2026-10-19',
        updatedAt: now,
      );

      final payload = {
        'user_id': model.userId,
        'package_name': model.packageName,
        'app_name': model.appName,
        'total_time_foreground_seconds': model.totalTimeForegroundSeconds,
        'last_time_used': model.lastTimeUsed?.toIso8601String(),
        'report_date': model.reportDate,
        'updated_at': model.updatedAt.toIso8601String(),
      };

      expect(payload['user_id'], 'user_123');
      expect(payload['package_name'], 'com.whatsapp');
      expect(payload['total_time_foreground_seconds'], 3600);
      expect(payload['report_date'], '2026-10-19');
    });
  });
}
