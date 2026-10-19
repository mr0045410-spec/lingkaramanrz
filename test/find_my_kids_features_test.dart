import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lingkar_aman/constants.dart';
import 'package:lingkar_aman/services/supabase_service.dart';
import 'package:lingkar_aman/services/loud_signal_service.dart';
import 'package:lingkar_aman/services/app_usage_service.dart';
import 'package:lingkar_aman/services/geofence_service.dart';

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = TestHttpOverrides();

  late SupabaseService supa;
  late LoudSignalService loudSignalService;
  late AppUsageService appUsageService;
  late GeofenceService geofenceService;

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final parentEmail = 'parent_$timestamp@lingkaraman.test';
  final childEmail = 'child_$timestamp@lingkaraman.test';
  const password = 'Password123!';

  String? parentId;
  String? childId;
  String? circleId;
  String? inviteCode;
  String? loudSignalId;
  String? geofenceId;

  setUpAll(() async {
    // ignore: avoid_print
    print('\n======================================================');
    // ignore: avoid_print
    print('  INTEGRATION TEST: 3 FIND-MY-KIDS ADAPTED FEATURES    ');
    // ignore: avoid_print
    print('======================================================\n');

    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );

    supa = SupabaseService();
    loudSignalService = LoudSignalService();
    appUsageService = AppUsageService();
    geofenceService = GeofenceService();
  });

  test('STEP 1: Register Parent & Child, create Circle and join', () async {
    // 1. Sign up Parent
    final resP = await supa.signUp(
      email: parentEmail,
      password: password,
      fullName: 'Ayah Rudi $timestamp',
    );
    parentId = resP.user?.id;
    expect(parentId, isNotNull);

    // 2. Parent creates Circle
    final circle = await supa.createCircle('Keluarga Rudi $timestamp');
    circleId = circle.id;
    inviteCode = circle.inviteCode;
    expect(circleId, isNotNull);
    expect(inviteCode!.length, 6);

    // 3. Sign up Child
    final resC = await supa.signUp(
      email: childEmail,
      password: password,
      fullName: 'Anak Budi $timestamp',
    );
    childId = resC.user?.id;
    expect(childId, isNotNull);

    // 4. Child joins Circle
    await supa.joinCircleByCode(inviteCode!);
    final members = await supa.getCircleMembers(circleId!);
    expect(members.length, 2);
    // ignore: avoid_print
    print('[OK] Parent ($parentId) & Child ($childId) in Circle ($circleId)');
  });

  test('STEP 2: Fitur 1 - Sinyal Keras (Loud Signal - Tembus Silent/DND)', () async {
    // 1. Parent logs in
    await supa.signIn(email: parentEmail, password: password);

    // 2. Parent sends Loud Signal to Child
    final sig = await loudSignalService.sendLoudSignal(
      targetUserId: childId!,
      circleId: circleId,
    );
    loudSignalId = sig.id;
    expect(sig.status, 'pending');
    expect(sig.targetUserId, childId);
    expect(sig.senderId, parentId);

    // 3. Child logs in and receives signal (simulating ringing state)
    await supa.signIn(email: childEmail, password: password);
    await supa.client.from('loud_signals').update({'status': 'ringing'}).eq('id', loudSignalId!);

    final ringingSig = await supa.client
        .from('loud_signals')
        .select()
        .eq('id', loudSignalId!)
        .single();
    expect(ringingSig['status'], 'ringing');

    // 4. Signal is stopped by Child or Parent
    await loudSignalService.stopLoudSignal(loudSignalId!);

    final stoppedSig = await supa.client
        .from('loud_signals')
        .select()
        .eq('id', loudSignalId!)
        .single();
    expect(stoppedSig['status'], 'stopped');
    expect(stoppedSig['stopped_at'], isNotNull);
    // ignore: avoid_print
    print('[OK] Sinyal Keras berhasil dikirim, berdering, dan dihentikan!');
  });

  test('STEP 3: Fitur 2 - Statistik Penggunaan Aplikasi (Screen Time)', () async {
    // 1. Child logs in and syncs app usage stats
    await supa.signIn(email: childEmail, password: password);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final testReports = [
      {
        'user_id': childId!,
        'package_name': 'com.google.android.youtube',
        'app_name': 'YouTube',
        'total_time_foreground_seconds': 3600,
        'report_date': today,
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'user_id': childId!,
        'package_name': 'com.mobile.legends',
        'app_name': 'Mobile Legends: Bang Bang',
        'total_time_foreground_seconds': 2700,
        'report_date': today,
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'user_id': childId!,
        'package_name': 'com.whatsapp',
        'app_name': 'WhatsApp',
        'total_time_foreground_seconds': 1800,
        'report_date': today,
        'updated_at': DateTime.now().toIso8601String(),
      },
    ];

    for (var r in testReports) {
      await supa.client.from('app_usage_reports').upsert(
        r,
        onConflict: 'user_id,package_name,report_date',
      );
    }

    // 2. Parent logs in and queries Child\'s screen time & top apps
    await supa.signIn(email: parentEmail, password: password);
    final childUsage = await appUsageService.getMemberUsage(childId!);

    expect(childUsage.length, greaterThanOrEqualTo(3));
    expect(childUsage[0].appName, 'YouTube');
    expect(childUsage[0].totalTimeForegroundSeconds, 3600);

    final totalSeconds = childUsage.fold<int>(0, (sum, a) => sum + a.totalTimeForegroundSeconds);
    expect(totalSeconds, greaterThanOrEqualTo(8100)); // >= 2 hours 15 minutes
    // ignore: avoid_print
    print('[OK] Statistik Penggunaan Aplikasi berhasil dilaporkan & dipantau orang tua! (Total: ${totalSeconds ~/ 60} menit)');
  });

  test('STEP 4: Fitur 3 - Geofencing Otomatis (Zona Aman Rumah/Sekolah & Event)', () async {
    // 1. Parent logs in and creates Geofence "Rumah"
    await supa.signIn(email: parentEmail, password: password);

    // Coordinate: Bundaran HI Jakarta (-6.1950, 106.8230)
    const homeLat = -6.1950;
    const homeLng = 106.8230;

    final geo = await geofenceService.createGeofence(
      circleId: circleId!,
      name: 'Rumah Cemara',
      category: 'home',
      latitude: homeLat,
      longitude: homeLng,
      radiusMeters: 200.0,
    );
    geofenceId = geo.id;
    expect(geo.name, 'Rumah Cemara');
    expect(geo.category, 'home');

    // Verify list of geofences
    final list = await geofenceService.getGeofences(circleId!);
    expect(list.any((g) => g.id == geofenceId), isTrue);

    // 2. Simulate Child location arriving at Rumah (inside 200m radius)
    await geofenceService.checkMemberLocationAgainstGeofences(
      geofences: [geo],
      circleId: circleId!,
      userId: childId!,
      userName: 'Anak Budi',
      latitude: -6.1951, // ~15 meters away from home
      longitude: 106.8231,
    );

    // 3. Simulate Child location leaving Rumah (outside radius, ~1 km away)
    await geofenceService.checkMemberLocationAgainstGeofences(
      geofences: [geo],
      circleId: circleId!,
      userId: childId!,
      userName: 'Anak Budi',
      latitude: -6.2050,
      longitude: 106.8300,
    );

    // 4. Fetch recent geofence events
    final events = await geofenceService.getRecentEvents(circleId!);
    expect(events.length, greaterThanOrEqualTo(2));

    final entered = events.firstWhere((e) => e.eventType == 'entered');
    final exited = events.firstWhere((e) => e.eventType == 'exited');

    expect(entered.geofenceId, geofenceId);
    expect(exited.geofenceId, geofenceId);
    // ignore: avoid_print
    print('[OK] Geofencing Otomatis berhasil mencatat kedatangan dan kepulangan anggota!');
  });
}
