import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingkar_aman/screens/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermissionStatus') {
          return 1; // PermissionStatus.granted
        }
        return null;
      },
    );
  });

  testWidgets('OnboardingScreen displays overlay permission card', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: () {},
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify all permission cards exist
    expect(find.text('Lokasi Sepanjang Waktu'), findsOneWidget);
    expect(find.text('Notifikasi Darurat & Sinyal Keras'), findsOneWidget);
    expect(find.text('Kamera Depan (Jebakan Penyusup)'), findsOneWidget);
    expect(find.text('Mikrofon & Audio Sekitar'), findsOneWidget);
    expect(find.text('Aplikasi Berjalan di Latar Belakang'), findsOneWidget);

    // Verify the newly added Overlay permission card
    expect(find.text('Tampil di Atas Layar Kunci & Aplikasi'), findsOneWidget);
    expect(
      find.text('Wajib agar layar kunci darurat & perlindungan anti-maling langsung tampil di atas layar saat HP hilang atau dicuri.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
  });
}
