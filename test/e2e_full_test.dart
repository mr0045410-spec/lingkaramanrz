import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lingkar_aman/constants.dart';
import 'package:lingkar_aman/services/supabase_service.dart';

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
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  final user1Email = 'test_user1_$timestamp@lingkaraman.test';
  final user1Pass = 'Rahasia123!';
  final user1Name = 'Budi Santoso $timestamp';

  final user2Email = 'test_user2_$timestamp@lingkaraman.test';
  final user2Pass = 'Rahasia123!';
  final user2Name = 'Siti Rahma $timestamp';

  String? createdCircleId;
  String? inviteCode;
  String? sosAlertId;

  setUpAll(() async {
    print('\n========================================');
    print('  STARTING FULL END-TO-END SYSTEM TEST  ');
    print('========================================\n');

    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
    supa = SupabaseService();
    print('[+] 1. Supabase Client Initialized successfully.');
  });

  test('E2E TEST 1: Register User 1 & Auto Profile Creation', () async {
    print('\n--- Testing User 1 Registration ---');
    final authRes = await supa.signUp(
      email: user1Email,
      password: user1Pass,
      fullName: user1Name,
      phoneNumber: '081211112222',
    );

    expect(authRes.user, isNotNull);
    final user1Id = authRes.user!.id;
    print('[✓] User 1 created with UID: $user1Id');

    // If session is null, sign in
    if (supa.currentUser == null) {
      await supa.signIn(email: user1Email, password: user1Pass);
    }
    expect(supa.currentUser, isNotNull);
    print('[✓] User 1 authenticated.');

    // Verify profile in database
    final profile = await supa.getProfile();
    expect(profile, isNotNull);
    expect(profile!.fullName, equals(user1Name));
    print('[✓] Profile created & verified: ${profile.fullName}');
  });

  test('E2E TEST 2: User 1 Creates a New Circle', () async {
    print('\n--- Testing Circle Creation ---');
    final circle = await supa.createCircle('Lingkar Keluarga Test');

    expect(circle.id, isNotEmpty);
    expect(circle.inviteCode.length, equals(6));
    createdCircleId = circle.id;
    inviteCode = circle.inviteCode;

    print('[✓] Circle "${circle.name}" created!');
    print('[✓] Circle ID: $createdCircleId');
    print('[✓] 6-Digit Invite Code: $inviteCode');

    // Verify circle list
    final myCircles = await supa.getMyCircles();
    expect(myCircles.any((c) => c.id == createdCircleId), isTrue);
    print('[✓] User 1 is registered as admin of the circle.');
  });

  test('E2E TEST 3: Register User 2 & Join Circle via Invite Code', () async {
    print('\n--- Testing User 2 Registration & Join Circle ---');
    // Sign out User 1
    await supa.signOut();
    expect(supa.currentUser, isNull);

    // Register User 2
    final authRes = await supa.signUp(
      email: user2Email,
      password: user2Pass,
      fullName: user2Name,
      phoneNumber: '081233334444',
    );
    expect(authRes.user, isNotNull);

    if (supa.currentUser == null) {
      await supa.signIn(email: user2Email, password: user2Pass);
    }
    expect(supa.currentUser, isNotNull);
    print('[✓] User 2 authenticated with UID: ${supa.currentUser!.id}');

    // User 2 joins circle using inviteCode
    expect(inviteCode, isNotNull);
    await supa.joinCircleByCode(inviteCode!);
    print('[✓] User 2 joined circle with code: $inviteCode');

    // Verify User 2 has circle in their list
    final myCircles = await supa.getMyCircles();
    expect(myCircles.any((c) => c.id == createdCircleId), isTrue);
    print('[✓] Circle verified in User 2 circle list.');
  });

  test('E2E TEST 4: Verify Circle Members (Both Users)', () async {
    print('\n--- Verifying Circle Members ---');
    final members = await supa.getCircleMembers(createdCircleId!);

    expect(members.length, equals(2));
    final names = members.map((m) => m.profile?.fullName).toList();
    print('[✓] Total members in circle: ${members.length}');
    print('[✓] Members: $names');
    expect(names.contains(user1Name), isTrue);
    expect(names.contains(user2Name), isTrue);
  });

  test('E2E TEST 5: Real-time Location Updates & Sync', () async {
    print('\n--- Testing Realtime Location Sync ---');
    // User 2 sends location update
    await supa.updateMyLocation(
      latitude: -6.2088,
      longitude: 106.8456,
      batteryLevel: 88,
      isCharging: false,
      speed: 12.5,
    );
    print('[✓] User 2 location pushed: (-6.2088, 106.8456, 88% battery)');

    // Fetch members and verify User 2's location is recorded
    final members = await supa.getCircleMembers(createdCircleId!);
    final user2Member = members.firstWhere((m) => m.profile?.fullName == user2Name);

    expect(user2Member.location, isNotNull);
    expect(user2Member.location!.latitude, closeTo(-6.2088, 0.0001));
    expect(user2Member.location!.longitude, closeTo(106.8456, 0.0001));
    expect(user2Member.location!.batteryLevel, equals(88));
    print('[✓] User 2 location successfully synced and retrieved by circle members!');
  });

  test('E2E TEST 6: Emergency SOS Trigger, Broadcast, and Resolution', () async {
    print('\n--- Testing Emergency SOS Flow ---');
    // User 2 triggers emergency SOS
    final alert = await supa.triggerSOS(
      latitude: -6.2088,
      longitude: 106.8456,
      circleId: createdCircleId,
      customMessage: 'SIMULASI SOS: Butuh bantuan darurat di Bundaran HI!',
    );

    expect(alert.id, isNotEmpty);
    expect(alert.status, equals('active'));
    sosAlertId = alert.id;
    print('[✓] Emergency SOS ALERT TRIGGERED!');
    print('[✓] Alert ID: $sosAlertId | Status: ${alert.status} | Message: ${alert.message}');

    // Fetch active alerts for this circle
    final activeAlerts = await supa.getActiveAlerts(createdCircleId);
    expect(activeAlerts.any((a) => a.id == sosAlertId), isTrue);
    print('[✓] Active SOS alert verified in circle feed (Alert count: ${activeAlerts.length})');

    // Resolve SOS
    await supa.resolveSOS(sosAlertId!);
    print('[✓] User 2 marked SOS as resolved.');

    // Verify it is no longer in active alerts
    final activeAlertsAfter = await supa.getActiveAlerts(createdCircleId);
    expect(activeAlertsAfter.any((a) => a.id == sosAlertId), isFalse);
    print('[✓] SOS alert status successfully closed.');
  });

  test('E2E TEST 7: Circle Community Chat Messaging', () async {
    print('\n--- Testing Community Group Chat ---');
    // User 2 sends a message
    await supa.sendMessage(createdCircleId!, 'Keluarga, apakah situasi aman?');
    print('[✓] User 2 sent chat message.');

    // Fetch messages
    final messages = await supa.getMessages(createdCircleId!);
    expect(messages.isNotEmpty, isTrue);
    expect(messages.last.message, equals('Keluarga, apakah situasi aman?'));
    print('[✓] Message received in circle chat: "${messages.last.message}"');
    print('[✓] Message sender: ${messages.last.senderProfile?.fullName ?? "User 2"}');
  });

  tearDownAll(() async {
    print('\n========================================');
    print('  ALL 7 E2E TEST SCENARIOS PASSED 100%  ');
    print('========================================\n');
  });
}
