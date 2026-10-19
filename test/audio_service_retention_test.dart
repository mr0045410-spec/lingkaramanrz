import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingkar_aman/services/audio_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDocDir;
  late AudioService audioService;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (call) async {
      return null;
    });
  });

  setUp(() async {
    testDocDir = await Directory.systemTemp.createTemp('audio_retention_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(testDocDir);
    audioService = AudioService();
  });

  tearDown(() async {
    if (await testDocDir.exists()) {
      await testDocDir.delete(recursive: true);
    }
  });

  test('AudioService saves files locally and deletes files older than 7 days only', () async {
    final recordingsDir = await audioService.getRecordingsDirectory();
    expect(await recordingsDir.exists(), isTrue);

    // 1. Create a fresh file (1 hour old)
    final freshFile = File(p.join(recordingsDir.path, 'ambient_fresh.m4a'));
    await freshFile.writeAsString('fresh audio bytes');

    // 2. Create an old file (> 7 days old, e.g. 8 days old)
    final oldFile = File(p.join(recordingsDir.path, 'ambient_old.m4a'));
    await oldFile.writeAsString('old audio bytes');
    final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
    await oldFile.setLastModified(eightDaysAgo);

    // Verify both exist before cleanup
    expect(await freshFile.exists(), isTrue);
    expect(await oldFile.exists(), isTrue);

    final localListBefore = await audioService.getLocalRecordings();
    expect(localListBefore.length, equals(2));

    // Run weekly cleanup
    await audioService.cleanOldRecordings(maxAge: const Duration(days: 7));

    // Fresh file MUST be preserved
    expect(await freshFile.exists(), isTrue);

    // Old file MUST be deleted
    expect(await oldFile.exists(), isFalse);

    final localListAfter = await audioService.getLocalRecordings();
    expect(localListAfter.length, equals(1));
    expect(p.normalize(localListAfter.first.path), equals(p.normalize(freshFile.path)));
  });
}
