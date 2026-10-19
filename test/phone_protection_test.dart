import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingkar_aman/models/models.dart';
import 'package:lingkar_aman/screens/lost_mode_screen.dart';
import 'package:lingkar_aman/services/phone_protection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Mode HP Hilang (Lost Mode) Model & Command Tests', () {
    test('LostModeCommand serialization & deserialization', () {
      final now = DateTime.now();
      final cmd = LostModeCommand(
        id: 'lost_101',
        targetUserId: 'target_user_abc',
        senderId: 'parent_user_xyz',
        circleId: 'circle_main_1',
        isActive: true,
        contactPhone: '081234567890',
        message: 'Tolong kembalikan ke pemilik, hubungi nomor tertera.',
        enableSiren: true,
        enableFakeShutdown: false,
        updatedAt: now,
      );

      final map = cmd.toMap();
      expect(map['id'], 'lost_101');
      expect(map['target_user_id'], 'target_user_abc');
      expect(map['is_active'], true);
      expect(map['contact_phone'], '081234567890');
      expect(map['enable_siren'], true);
      expect(map['enable_fake_shutdown'], false);

      final reconstructed = LostModeCommand.fromMap(map);
      expect(reconstructed.id, cmd.id);
      expect(reconstructed.targetUserId, cmd.targetUserId);
      expect(reconstructed.senderId, cmd.senderId);
      expect(reconstructed.circleId, cmd.circleId);
      expect(reconstructed.isActive, true);
      expect(reconstructed.contactPhone, '081234567890');
      expect(reconstructed.message, 'Tolong kembalikan ke pemilik, hubungi nomor tertera.');
      expect(reconstructed.enableSiren, true);
      expect(reconstructed.enableFakeShutdown, false);
    });
  });

  group('2. Last Breath Beacon Model Tests', () {
    test('LastBreathBeaconModel correctly captures critical battery & coordinates', () {
      final now = DateTime.now();
      final beacon = LastBreathBeaconModel(
        userId: 'user_target_456',
        latitude: -6.2088,
        longitude: 106.8456,
        batteryLevel: 4,
        timestamp: now,
      );

      final map = beacon.toMap();
      expect(map['user_id'], 'user_target_456');
      expect(map['latitude'], -6.2088);
      expect(map['longitude'], 106.8456);
      expect(map['battery_level'], 4);

      final fromMap = LastBreathBeaconModel.fromMap(map);
      expect(fromMap.userId, beacon.userId);
      expect(fromMap.latitude, -6.2088);
      expect(fromMap.longitude, 106.8456);
      expect(fromMap.batteryLevel, 4);
      expect(fromMap.timestamp.toIso8601String(), now.toIso8601String());
    });
  });

  group('3. Jebakan Penyusup (Intruder Trap) Model Tests', () {
    test('IntruderAlertModel captures attempt count and location telemetry', () {
      final now = DateTime.now();
      final alert = IntruderAlertModel(
        id: 'intruder_999',
        userId: 'user_target_456',
        circleId: 'circle_main_1',
        attemptCount: 3,
        latitude: -6.1754,
        longitude: 106.8272,
        alertType: 'wrong_pin',
        createdAt: now,
      );

      final map = alert.toMap();
      expect(map['id'], 'intruder_999');
      expect(map['attempt_count'], 3);
      expect(map['alert_type'], 'wrong_pin');
      expect(map['latitude'], -6.1754);
      expect(map['longitude'], 106.8272);

      final fromMap = IntruderAlertModel.fromMap(map);
      expect(fromMap.id, 'intruder_999');
      expect(fromMap.attemptCount, 3);
      expect(fromMap.alertType, 'wrong_pin');
    });
  });

  group('4. PhoneProtectionService Business Logic & State Tests', () {
    late PhoneProtectionService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lost_mode_pin': '4321',
        'vault_locked': false,
        'intruder_failed_attempts': 0,
      });
      service = PhoneProtectionService();
      await service.initialize();
    });

    test('Owner PIN verification and intruder attempt counting', () async {
      expect(await service.getOwnerPin(), '4321');

      // 1st wrong attempt
      final attempt1 = await service.verifyUnlockPin('0000');
      expect(attempt1, isFalse);
      expect(service.failedPinAttempts, 1);

      // 2nd wrong attempt
      final attempt2 = await service.verifyUnlockPin('1111');
      expect(attempt2, isFalse);
      expect(service.failedPinAttempts, 2);

      // 3rd wrong attempt (triggers intruder trap threshold)
      final attempt3 = await service.verifyUnlockPin('9999');
      expect(attempt3, isFalse);
      expect(service.failedPinAttempts, 3);

      // Correct PIN unlocks and resets failed attempts
      final attemptCorrect = await service.verifyUnlockPin('4321');
      expect(attemptCorrect, isTrue);
      expect(service.failedPinAttempts, 0);
    });

    test('Changing owner security PIN', () async {
      await service.setOwnerPin('8888');
      expect(await service.getOwnerPin(), '8888');

      // Old PIN fails
      expect(await service.verifyUnlockPin('4321'), isFalse);
      // New PIN succeeds
      expect(await service.verifyUnlockPin('8888'), isTrue);
    });

    test('Fake Shutdown (Kamuflase Layar Mati) toggle', () {
      expect(service.isFakeShutdownActive, isFalse);
      service.toggleFakeShutdown(true);
      expect(service.isFakeShutdownActive, isTrue);
      service.toggleFakeShutdown(false);
      expect(service.isFakeShutdownActive, isFalse);
    });

    test('Remote Vault Lockdown and Unlock Flow', () async {
      expect(service.isVaultLocked, isFalse);

      // Lock Vault
      await service.executeLocalVaultLock();
      expect(service.isVaultLocked, true);

      // Unlock with wrong PIN fails
      final wrongUnlock = await service.unlockVault('0000');
      expect(wrongUnlock, isFalse);
      expect(service.isVaultLocked, true);

      // Unlock with correct PIN succeeds
      final correctUnlock = await service.unlockVault('4321');
      expect(correctUnlock, isTrue);
      expect(service.isVaultLocked, false);
    });

    test('Last Breath Beacon battery threshold logic', () async {
      LastBreathBeaconModel? emittedBeacon;
      final sub = service.onLastBreathBeacon.listen((beacon) {
        emittedBeacon = beacon;
      });

      // Normal battery (80%) -> Should NOT trigger
      await service.checkBatteryAndTriggerLastBreath(
        lat: -6.2000,
        lng: 106.8000,
        batteryLevel: 80,
        isCharging: false,
      );
      expect(emittedBeacon, isNull);

      // Critical battery (4%) but charging -> Should NOT trigger
      await service.checkBatteryAndTriggerLastBreath(
        lat: -6.2000,
        lng: 106.8000,
        batteryLevel: 4,
        isCharging: true,
      );
      expect(emittedBeacon, isNull);

      // Critical battery (4%) NOT charging -> TRIGGERS BEACON!
      await service.checkBatteryAndTriggerLastBreath(
        lat: -6.2000,
        lng: 106.8000,
        batteryLevel: 4,
        isCharging: false,
      );
      await Future.delayed(Duration.zero);
      expect(emittedBeacon, isNotNull);
      expect(emittedBeacon!.batteryLevel, 4);
      expect(emittedBeacon!.latitude, -6.2000);
      expect(emittedBeacon!.longitude, 106.8000);

      await sub.cancel();
    });

    testWidgets('LostModeScreen PIN unlock dialog does not overflow with small viewport or keyboard', (tester) async {
      // Simulate viewport constrained by keyboard (e.g. height 450)
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cmd = LostModeCommand(
        id: 'cmd_overflow_test',
        targetUserId: 'target_u',
        senderId: 'sender_u',
        isActive: true,
        contactPhone: '08123456789',
        message: 'Tolong kembalikan ke pemilik, hubungi nomor ini segera.',
        enableSiren: false,
        enableFakeShutdown: false,
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LostModeScreen(command: cmd),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Ensure visible in scroll view and tap
      final openPinBtn = find.text('Buka Kunci Pemilik (PIN)');
      expect(openPinBtn, findsOneWidget);
      await tester.ensureVisible(openPinBtn);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(openPinBtn);
      await tester.pump(const Duration(milliseconds: 500));

      // Verify dialog is visible and NO overflow occurred
      expect(find.text('Buka Kunci Pemilik'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
