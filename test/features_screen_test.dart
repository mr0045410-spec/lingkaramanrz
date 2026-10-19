import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingkar_aman/models/models.dart';
import 'package:lingkar_aman/screens/features_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'lost_mode_pin': '1234',
      'sos_power_button_enabled': true,
      'sos_power_button_count': 3,
    });
  });

  final testCircle = CircleModel(
    id: 'circle_test_1',
    name: 'Keluarga Utama',
    inviteCode: 'A8UK6J',
    createdBy: 'owner_user_1',
    createdAt: DateTime.now(),
  );

  testWidgets('FeaturesScreen renders all categories and header', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          circles: [testCircle],
          selectedCircle: testCircle,
          onNavigateToTab: (_) {},
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title & Header
    expect(find.text('Pusat Fitur LingkarAman'), findsOneWidget);
    expect(find.text('Sistem Keamanan Aktif'), findsOneWidget);
    expect(find.text('Cari fitur (misal: anti-maling, sirine, geofence)...'), findsOneWidget);

    // Verify Main Categories
    expect(find.text('Perlindungan HP & Anti-Maling'), findsOneWidget);
    expect(find.text('Mode HP Hilang (Lost Mode)'), findsOneWidget);
    expect(find.text('Kamuflase Pura-pura Mati (Fake Shutdown)'), findsOneWidget);
    expect(find.text('Jebakan Penyusup (Intruder Trap)'), findsOneWidget);
    expect(find.text('Last Breath Beacon'), findsOneWidget);
    expect(find.text('Kunci Brankas Darurat (Remote Wipe)'), findsOneWidget);

    // Scroll to see remaining sections
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('Respon Cepat & Keselamatan'), findsOneWidget);
    expect(find.text('Sinyal Keras Darurat (Loud Siren)'), findsOneWidget);
    expect(find.text('Monitor Suara Sekitar (Ambient Audio)'), findsOneWidget);
    expect(find.text('Pemicu Cepat Tombol Daya (SOS Shortcut)'), findsOneWidget);
    expect(find.text('Pusat Alarm Darurat (Layar SOS)'), findsOneWidget);

    // Scroll further to see Location and Family sections
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('Lokasi & Zona Aman'), findsOneWidget);
    expect(find.text('Zona Aman Virtual (Geofencing)'), findsOneWidget);
    expect(find.text('Peta Langsung Real-time'), findsOneWidget);
    expect(find.text('Riwayat Perjalanan (Timeline)'), findsOneWidget);

    expect(find.text('Lingkaran Keluarga'), findsOneWidget);
    expect(find.text('Manajemen Anggota Lingkaran'), findsOneWidget);
    expect(find.text('Bagikan Kode Undangan'), findsOneWidget);
  });

  testWidgets('FeaturesScreen search filter functions properly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          circles: [testCircle],
          selectedCircle: testCircle,
          onNavigateToTab: (_) {},
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Type "kamuflase" into search box
    final searchInput = find.byType(TextField);
    await tester.enterText(searchInput, 'kamuflase');
    await tester.pumpAndSettle();

    // Kamuflase should be present
    expect(find.text('Kamuflase Pura-pura Mati (Fake Shutdown)'), findsOneWidget);

    // Other categories should be filtered out
    expect(find.text('Lokasi & Zona Aman'), findsNothing);
    expect(find.text('Lingkaran Keluarga'), findsNothing);

    // Clear search
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    // All should be visible again
    expect(find.text('Perlindungan HP & Anti-Maling'), findsOneWidget);
  });

  testWidgets('FeaturesScreen Ganti PIN dialog opens and validates', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          circles: [testCircle],
          selectedCircle: testCircle,
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gantiPinBtn = find.text('Ganti PIN');
    expect(gantiPinBtn, findsOneWidget);
    await tester.tap(gantiPinBtn);
    await tester.pumpAndSettle();

    expect(find.text('Ubah PIN Pemilik'), findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
    expect(find.text('Batal'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah PIN Pemilik'), findsNothing);
  });
}
