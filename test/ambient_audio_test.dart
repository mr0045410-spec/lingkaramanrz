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

  final userAEmail = 'usera_$timestamp@lingkaraman.test';
  final userBEmail = 'userb_$timestamp@lingkaraman.test';
  final password = 'Password123!';

  String? userAId;
  String? userBId;
  String? circleId;
  String? audioRequestId;

  setUpAll(() async {
    print('\n======================================================');
    print('  STARTING REMOTE AMBIENT AUDIO INTEGRATION TEST      ');
    print('======================================================\n');

    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
    supa = SupabaseService();
  });

  test('STEP 1: Register User A and User B', () async {
    print('[*] Registering User A...');
    final resA = await supa.signUp(
      email: userAEmail,
      password: password,
      fullName: 'User A (Keluarga) $timestamp',
    );
    userAId = resA.user?.id;
    expect(userAId, isNotNull);
    print('    -> User A registered with ID: $userAId');

    print('[*] Registering User B (Target)...');
    final resB = await supa.signUp(
      email: userBEmail,
      password: password,
      fullName: 'User B (Ponsel Target) $timestamp',
    );
    userBId = resB.user?.id;
    expect(userBId, isNotNull);
    print('    -> User B registered with ID: $userBId');
  });

  test('STEP 2: User A creates Circle and User B joins', () async {
    // Login as User A
    await supa.signIn(email: userAEmail, password: password);
    final circle = await supa.createCircle('Lingkaran Perlindungan $timestamp');
    circleId = circle.id;
    print('    -> Circle created with ID: $circleId, Invite: ${circle.inviteCode}');

    // Login as User B and join circle
    await supa.signIn(email: userBEmail, password: password);
    await supa.joinCircleByCode(circle.inviteCode);
    print('    -> User B joined circle successfully.');
  });

  test('STEP 3: User A initiates Remote Ambient Audio Request to User B', () async {
    // Login as User A
    await supa.signIn(email: userAEmail, password: password);

    print('[*] User A requesting ambient audio from User B (Target: $userBId)...');
    final req = await supa.createAudioRequest(
      targetUserId: userBId!,
      circleId: circleId,
      durationSeconds: 15,
    );

    audioRequestId = req.id;
    expect(audioRequestId, isNotNull);
    expect(req.status, equals('pending'));
    expect(req.targetId, equals(userBId));
    print('    -> Audio request created. ID: $audioRequestId, Status: ${req.status}');
  });

  test('STEP 4: User B detects request, records, uploads to Storage, and completes', () async {
    // Login as User B
    await supa.signIn(email: userBEmail, password: password);

    print('[*] User B updating request to recording...');
    await supa.updateAudioRequest(audioRequestId!, status: 'recording');

    // Create a temporary mock audio file
    final tempDir = Directory.systemTemp;
    final testAudioFile = File('${tempDir.path}/test_ambient_$audioRequestId.m4a');
    await testAudioFile.writeAsBytes([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]); // mock header bytes

    print('[*] User B uploading audio clip to Supabase Storage (ambient_audio)...');
    final storagePath = 'clips/$userBId/$audioRequestId.m4a';
    final audioUrl = await supa.uploadAudioFile(testAudioFile.path, storagePath);
    expect(audioUrl, isNotEmpty);
    print('    -> Audio uploaded to: $audioUrl');

    print('[*] User B completing audio request with URL...');
    await supa.updateAudioRequest(audioRequestId!, status: 'completed', audioUrl: audioUrl);

    if (await testAudioFile.exists()) {
      await testAudioFile.delete();
    }
  });

  test('STEP 5: User A retrieves and verifies completed ambient audio', () async {
    // Login as User A
    await supa.signIn(email: userAEmail, password: password);

    print('[*] User A querying audio recordings for User B...');
    final pastRecords = await supa.getAudioRequestsForTarget(userBId!);
    expect(pastRecords, isNotEmpty);
    final latest = pastRecords.first;

    expect(latest.id, equals(audioRequestId));
    expect(latest.status, equals('completed'));
    expect(latest.audioUrl, isNotNull);
    expect(latest.audioUrl, contains('ambient_audio'));

    print('    -> Verified! Latest recording ID: ${latest.id}');
    print('    -> Audio URL: ${latest.audioUrl}');
    print('\n======================================================');
    print('  ALL REMOTE AMBIENT AUDIO TESTS PASSED SUCCESSFULLY! ');
    print('======================================================\n');
  });
}
