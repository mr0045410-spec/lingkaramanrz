import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingkar_aman/screens/auth_screen.dart';

void main() {
  testWidgets('AuthScreen renders Email OTP screen and validates temp mail', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(onAuthenticated: () {}),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and Email Input
    expect(find.text('LingkarAman'), findsOneWidget);
    expect(find.text('Kirim Kode OTP Masuk'), findsOneWidget);
    expect(find.text('Lanjutkan dengan Google'), findsOneWidget);

    // Switch to "Daftar Baru"
    await tester.tap(find.text('Daftar Baru'));
    await tester.pumpAndSettle();

    expect(find.text('Nama Lengkap'), findsOneWidget);
    expect(find.text('Nomor WhatsApp / HP (Opsional)'), findsOneWidget);
    expect(find.text('Kirim Kode OTP Pendaftaran'), findsOneWidget);

    // Enter temporary email
    final emailField = find.widgetWithText(TextFormField, 'Alamat Email Pribadi');
    await tester.enterText(emailField, 'test@tempmail.com');
    await tester.pumpAndSettle();

    // Tap Kirim Kode OTP
    await tester.tap(find.text('Kirim Kode OTP Pendaftaran'));
    await tester.pumpAndSettle();

    // Error should be displayed blocking temp mail
    expect(
      find.textContaining('Email sementara (temp mail) dilarang'),
      findsOneWidget,
    );

    // Now enter valid trusted email
    await tester.enterText(emailField, 'budi.santoso@gmail.com');
    await tester.pumpAndSettle();

    // Re-check: the temp mail error should not appear for gmail
    // (Note: it will fail on empty name because Daftar Baru requires name)
    await tester.tap(find.text('Kirim Kode OTP Pendaftaran'));
    await tester.pumpAndSettle();

    expect(find.text('Nama lengkap wajib diisi'), findsOneWidget);
  });
}
