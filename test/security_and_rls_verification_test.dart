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

  late SupabaseClient client;
  final supa = SupabaseService();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
    client = Supabase.instance.client;
  });

  group('SECURITY & RLS COMPREHENSIVE VERIFICATION', () {

    test('1. Query verifikasi admin palsu = 0 baris di database LIVE', () async {
      print('\n--- Verifikasi 1: Admin Palsu di Database Live ---');
      final res = await client
          .from('circle_members')
          .select('id, circle_id, user_id, role, circles!inner(created_by)')
          .eq('role', 'admin');

      int fakeAdminCount = 0;
      for (var row in res) {
        final circleData = row['circles'] as Map<String, dynamic>;
        final createdBy = circleData['created_by'] as String?;
        final memberUid = row['user_id'] as String;
        if (createdBy == null || memberUid != createdBy) {
          fakeAdminCount++;
          print('[!] DITEMUKAN ADMIN PALSU: $row');
        }
      }

      print('[✓] Total baris admin yang diperiksa: ${res.length}');
      print('[✓] Jumlah admin palsu ditemukan: $fakeAdminCount');
      expect(fakeAdminCount, equals(0), reason: 'Admin palsu harus 0 baris');
    });

    test('2. Isolasi Cross-Circle: Akun A TIDAK BOLEH bisa membaca data Circle Akun B', () async {
      print('\n--- Verifikasi 2: Isolasi RLS Antar-Circle (Akun A vs Akun B) ---');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final emailA = 'user_sec_a_$ts@lingkaraman.test';
      final emailB = 'user_sec_b_$ts@lingkaraman.test';
      final pass = 'Password123!';

      // 1. Register & Login Akun A -> Buat Circle A
      await supa.signOut();
      final authA = await supa.signUp(email: emailA, password: pass, fullName: 'User A $ts');
      final uidA = authA.user!.id;
      final circleA = await supa.createCircle('Circle A $ts');
      await supa.updateMyLocation(latitude: -6.2000, longitude: 106.8166, batteryLevel: 95);
      await supa.sendMessage(circleA.id, 'Pesan rahasia Circle A');

      // 2. Register & Login Akun B -> Buat Circle B
      await supa.signOut();
      final authB = await supa.signUp(email: emailB, password: pass, fullName: 'User B $ts');
      final uidB = authB.user!.id;
      final circleB = await supa.createCircle('Circle B $ts');
      await supa.updateMyLocation(latitude: -6.9175, longitude: 107.6191, batteryLevel: 80);
      await supa.sendMessage(circleB.id, 'Pesan rahasia Circle B');

      // 3. User B mencoba MENGINTIP data User A & Circle A
      print('[*] Pengujian 2a: User B mencoba membaca anggota Circle A...');
      final membersA = await client.from('circle_members').select().eq('circle_id', circleA.id);
      print('    -> Hasil query circle_members Circle A: ${membersA.length} baris');
      expect(membersA, isEmpty, reason: 'User B tidak boleh melihat anggota Circle A');

      print('[*] Pengujian 2b: User B mencoba membaca lokasi realtime User A...');
      final locA = await client.from('user_locations').select().eq('user_id', uidA);
      print('    -> Hasil query user_locations User A: ${locA.length} baris');
      expect(locA, isEmpty, reason: 'User B tidak boleh melihat koordinat lokasi User A');

      print('[*] Pengujian 2c: User B mencoba membaca chat Circle A...');
      final msgsA = await client.from('circle_messages').select().eq('circle_id', circleA.id);
      print('    -> Hasil query circle_messages Circle A: ${msgsA.length} baris');
      expect(msgsA, isEmpty, reason: 'User B tidak boleh melihat pesan rahasia Circle A');

      print('[*] Pengujian 2d: User B mencoba membaca profil privat User A...');
      final profA = await client.from('profiles').select().eq('id', uidA);
      print('    -> Hasil query profiles User A: ${profA.length} baris');
      expect(profA, isEmpty, reason: 'User B tidak boleh melihat profil orang di luar circle');

      print('[✓] SEMUA 4 PENGUJIAN ISOLASI DATA LOLOS 100%! Data Circle A aman dari User B.');
    });

    test('3. Tanpa login (Anon): Akses ke loud_signals, geofences, app_usage_reports harus DITOLAK', () async {
      print('\n--- Verifikasi 3: Pencegahan Akses Tanpa Login (Anon Client) ---');
      await supa.signOut();

      // Gunakan instance SupabaseClient anon murni tanpa token sesi
      final anonClient = SupabaseClient(
        AppConstants.supabaseUrl,
        AppConstants.supabaseAnonKey,
      );

      // 3a. loud_signals
      print('[*] Menguji SELECT loud_signals tanpa login...');
      final signals = await anonClient.from('loud_signals').select();
      expect(signals, isEmpty, reason: 'Anon tidak boleh membaca loud_signals');

      print('[*] Menguji INSERT loud_signals tanpa login...');
      bool insertSignalBlocked = false;
      try {
        await anonClient.from('loud_signals').insert({
          'sender_id': '00000000-0000-0000-0000-000000000000',
          'target_user_id': '00000000-0000-0000-0000-000000000000',
          'status': 'ringing',
        });
      } on PostgrestException catch (e) {
        insertSignalBlocked = true;
        print('    -> Akses INSERT loud_signals DITOLAK: ${e.message} (code: ${e.code})');
      }
      expect(insertSignalBlocked, isTrue, reason: 'Anon tidak boleh insert loud_signals');

      // 3b. geofences
      print('[*] Menguji SELECT geofences tanpa login...');
      final geofences = await anonClient.from('geofences').select();
      expect(geofences, isEmpty, reason: 'Anon tidak boleh membaca geofences');

      print('[*] Menguji INSERT geofences tanpa login...');
      bool insertGeofenceBlocked = false;
      try {
        await anonClient.from('geofences').insert({
          'circle_id': '00000000-0000-0000-0000-000000000000',
          'name': 'Zona Terlarang',
          'latitude': 0.0,
          'longitude': 0.0,
        });
      } on PostgrestException catch (e) {
        insertGeofenceBlocked = true;
        print('    -> Akses INSERT geofences DITOLAK: ${e.message} (code: ${e.code})');
      }
      expect(insertGeofenceBlocked, isTrue, reason: 'Anon tidak boleh insert geofences');

      // 3c. app_usage_reports
      print('[*] Menguji SELECT app_usage_reports tanpa login...');
      final reports = await anonClient.from('app_usage_reports').select();
      expect(reports, isEmpty, reason: 'Anon tidak boleh membaca app_usage_reports');

      print('[*] Menguji INSERT app_usage_reports tanpa login...');
      bool insertUsageBlocked = false;
      try {
        await anonClient.from('app_usage_reports').insert({
          'user_id': '00000000-0000-0000-0000-000000000000',
          'package_name': 'com.hacker.app',
          'app_name': 'Hacker',
        });
      } on PostgrestException catch (e) {
        insertUsageBlocked = true;
        print('    -> Akses INSERT app_usage_reports DITOLAK: ${e.message} (code: ${e.code})');
      }
      expect(insertUsageBlocked, isTrue, reason: 'Anon tidak boleh insert app_usage_reports');

      print('[✓] SEMUA 3 TABEL DILINDUNGI PENUH: Akses Anon ditolak 100%!');
    });

    test('4. Alur join via kode undangan tetap jalan: user baru join sebagai member', () async {
      print('\n--- Verifikasi 4: User Baru Join via Kode Undangan ---');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final emailOwner = 'owner_$ts@lingkaraman.test';
      final emailJoiner = 'joiner_$ts@lingkaraman.test';
      final pass = 'Password123!';

      // 1. Owner mendaftar & membuat Circle
      await supa.signOut();
      final authOwner = await supa.signUp(email: emailOwner, password: pass, fullName: 'Owner $ts');
      final uidOwner = authOwner.user!.id;
      final circle = await supa.createCircle('Keluarga Bahagia $ts');
      final inviteCode = circle.inviteCode;
      print('[✓] Circle dibuat dengan invite code: $inviteCode');

      // 2. Joiner mendaftar
      await supa.signOut();
      final authJoiner = await supa.signUp(email: emailJoiner, password: pass, fullName: 'Joiner $ts');
      final uidJoiner = authJoiner.user!.id;

      // 3. Joiner bergabung via kode
      await supa.joinCircleByCode(inviteCode);
      print('[✓] Joiner berhasil mengeksekusi joinCircleByCode');

      // 4. Verifikasi status role joiner di database
      final members = await supa.getCircleMembers(circle.id);
      expect(members.length, equals(2));

      final ownerMember = members.firstWhere((m) => m.userId == uidOwner);
      final joinerMember = members.firstWhere((m) => m.userId == uidJoiner);

      print('    -> Owner Role : ${ownerMember.role} (is_creator: true)');
      print('    -> Joiner Role: ${joinerMember.role} (is_creator: false)');

      expect(ownerMember.role, equals('admin'));
      expect(joinerMember.role, equals('member'), reason: 'Joiner wajib berstatus member, bukan admin');

      // Jalankan normalize_circle_roles untuk memastikan tidak ada baris yang perlu diperbaiki
      final fixed = await supa.normalizeCircleRoles(circle.id);
      print('[✓] normalize_circle_roles mengembalikan $fixed perbaikan (karena sudah berstatus member)');
      expect(fixed, equals(0));
    });

    test('5. Pembuktian normalize_circle_roles() berhasil memulihkan admin palsu jika terjadi anomali', () async {
      print('\n--- Verifikasi 5: Pembuktian Self-Healing normalize_circle_roles ---');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final emailOwner = 'owner_fix_$ts@lingkaraman.test';
      final emailJoiner = 'joiner_fix_$ts@lingkaraman.test';
      final pass = 'Password123!';

      // 1. Owner & Joiner buat dan join circle
      await supa.signOut();
      final authOwner = await supa.signUp(email: emailOwner, password: pass, fullName: 'Owner $ts');
      final uidOwner = authOwner.user!.id;
      final circle = await supa.createCircle('Circle Uji Coba $ts');

      await supa.signOut();
      final authJoiner = await supa.signUp(email: emailJoiner, password: pass, fullName: 'Joiner $ts');
      final uidJoiner = authJoiner.user!.id;
      await supa.joinCircleByCode(circle.inviteCode);

      // 2. Login kembali sebagai Owner (Admin) lalu simulasikan baris admin basi
      await supa.signOut();
      await supa.signIn(email: emailOwner, password: pass);

      // Update manual simulasi baris lama yang salah jadi admin
      await client.from('circle_members').update({'role': 'admin'}).eq('circle_id', circle.id).eq('user_id', uidJoiner);

      // Verifikasi bahwa joiner sekarang berstatus admin basi
      final staleData = await client.from('circle_members').select().eq('circle_id', circle.id).eq('user_id', uidJoiner).single();
      print('    -> Status Joiner sebelum dinormalisasi: ${staleData['role']} (Anomali: Admin Palsu)');
      expect(staleData['role'], equals('admin'));

      // 3. Panggil normalize_circle_roles
      final repairedCount = await supa.normalizeCircleRoles(circle.id);
      print('[✓] normalize_circle_roles berhasil memperbaiki: $repairedCount baris');
      expect(repairedCount, equals(1));

      // 4. Verifikasi status Joiner setelah dinormalisasi
      final cleanData = await client.from('circle_members').select().eq('circle_id', circle.id).eq('user_id', uidJoiner).single();
      print('    -> Status Joiner setelah dinormalisasi: ${cleanData['role']} (Terkoreksi menjadi: Member)');
      expect(cleanData['role'], equals('member'));

      // 5. Verifikasi via getCircleMembers
      final members = await supa.getCircleMembers(circle.id);
      final joinerCheck = members.firstWhere((m) => m.userId == uidJoiner);
      expect(joinerCheck.role, equals('member'));
      print('[✓] getCircleMembers() memvalidasi hierarki aman tanpa error!');
    });

    test('6. Keamanan SOS Alerts: Orang Asing TIDAK BISA mengubah status darurat orang lain', () async {
      print('\n--- Verifikasi 6: Keamanan UPDATE SOS Alerts dari Orang Asing ---');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final emailVictim = 'victim_$ts@lingkaraman.test';
      final emailAttacker = 'attacker_$ts@lingkaraman.test';
      final pass = 'Password123!';

      // 1. Victim mendaftar & memicu SOS
      await supa.signOut();
      await supa.signUp(email: emailVictim, password: pass, fullName: 'Korban $ts');
      final alert = await supa.triggerSOS(latitude: -6.2, longitude: 106.8, customMessage: 'BUTUH BANTUAN!');
      print('[✓] Korban memicu SOS. ID Alert: ${alert.id}, Status: ${alert.status}');

      // 2. Attacker mendaftar (lingkaran berbeda, orang asing)
      await supa.signOut();
      await supa.signUp(email: emailAttacker, password: pass, fullName: 'Penyerang $ts');
      final attackerCircle = await supa.createCircle('Lingkaran Penyerang $ts');

      // 3. Attacker mencoba UPDATE (resolve) alert korban
      print('[*] Penyerang mencoba menutup (resolve) status darurat korban...');
      final updateResult = await client
          .from('sos_alerts')
          .update({'status': 'resolved'})
          .eq('id', alert.id)
          .select();

      print('    -> Baris SOS korban yang berhasil diubah penyerang: ${updateResult.length} baris');
      expect(updateResult, isEmpty, reason: 'Penyerang tidak boleh bisa mengubah baris SOS korban!');

      // 4. Login kembali sebagai korban untuk memeriksa apakah status masih tetap 'active'
      await supa.signOut();
      await supa.signIn(email: emailVictim, password: pass);
      final activeAlerts = await supa.getActiveAlerts();
      final victimAlert = activeAlerts.firstWhere((a) => a.id == alert.id);
      print('[✓] Status SOS Korban tetap aman: ${victimAlert.status}');
      expect(victimAlert.status, equals('active'));

      // Clean up resolve by victim
      await supa.resolveSOS(alert.id);
    });
  });
}
