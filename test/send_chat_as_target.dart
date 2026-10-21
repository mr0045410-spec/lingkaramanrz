import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lingkar_aman/constants.dart';

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

  test('Send chat message as Target HP', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
    final client = Supabase.instance.client;

    final email = 'target_member_test@lingkaraman.test';
    final pass = 'Password123!';
    final res = await client.auth.signInWithPassword(email: email, password: pass);
    print('LOGGED_IN: ${res.user?.id}');

    // Cari circle id A8UK6J
    final circles = await client.from('circles').select('id, name').eq('invite_code', 'A8UK6J').limit(1);
    final circleId = circles.first['id'] as String;
    print('CIRCLE_ID: $circleId');

    // Kirim pesan
    await client.from('circle_messages').insert({
      'circle_id': circleId,
      'user_id': res.user!.id,
      'message': 'Halo keluarga, ini pesan realtime dari Target HP!',
      'created_at': DateTime.now().toIso8601String(),
    });
    print('MESSAGE_INSERTED_SUCCESSFULLY');
  });
}
