# LAPORAN AUDIT TEKNIS & KEAMANAN SISTEM LINGKARAMAN
**Status:** Tahap 1 — Audit Read-Only  
**Tanggal:** 21 Oktober 2026  
**Target:** Repositori LingkarAman (Flutter, Native Android Kotlin, Supabase PostgreSQL, RLS, Storage)

---

## 1. RINGKASAN EKSEKUTIF & MATRIKS TEMUAN

Audit teknis dan keamanan ini dilakukan secara murni **read-only** pada seluruh berkas kode sumber aplikasi Android LingkarAman, konfigurasi native, skrip migrasi SQL Supabase, fungsi PostgreSQL, Row Level Security (RLS), dan Storage Bucket.

Ditemukan **12 kerentanan dan masalah teknis nyata**:

| ID | Komponen | Ringkasan Temuan | Tingkat Risiko | Status Bukti |
| :--- | :--- | :--- | :---: | :---: |
| **SEC-01** | Supabase RLS | Seluruh kode undangan keluarga (*invite code*) terbuka untuk dibaca oleh seluruh user terautentikasi (`USING (true)`). | 🔴 **KRITIS** | Terbukti di Kode |
| **SEC-02** | Supabase Storage | Bucket rekaman audio rahasia & foto kamera penyusup disetel publik dan dapat diakses/diunduh oleh siapa pun. | 🔴 **KRITIS** | Terbukti di Kode |
| **SEC-03** | Supabase RLS | Eskalasi peran (*privilege escalation*): Anggota biasa dapat menaikkan rolenya sendiri menjadi `admin` via PostgREST UPDATE. | 🔴 **KRITIS** | Terbukti di Kode |
| **SEC-04** | Supabase RLS | *Bypass* privasi lokasi: Riwayat & lokasi realtime tetap terbaca meski `is_sharing_location = false`. | 🟠 **TINGGI** | Terbukti di Kode |
| **SEC-05** | Supabase RLS | Arbitrary Remote Command: Anggota lingkaran dapat mengirim perintah `remote_wipe` atau penguncian ke target mana pun. | 🟠 **TINGGI** | Terbukti di Kode |
| **SEC-06** | Supabase RLS | Injeksi sinyal sirene & penyadapan mikrofon lintas pengguna tanpa batasan lingkaran (`circle_id IS NULL`). | 🟠 **TINGGI** | Terbukti di Kode |
| **SEC-07** | Supabase RLS | Anggota biasa dapat menghapus (*DELETE*) zona aman (*geofences*) yang dibuat oleh kepala keluarga/admin. | 🟡 **SEDANG** | Terbukti di Kode |
| **SEC-08** | Database / Config | Inkonsistensi Project Ref Supabase antara migrasi SQL (`xtgumpluxciqesahpxuk`) dan runtime aplikasi (`uwxecnbeqeysnlzwdcha`). | 🟡 **SEDANG** | Terbukti di Kode |
| **APP-01** | Flutter / Push | Push notification & remote wakeup mati saat aplikasi ditutup (FCM SDK & `google-services.json` belum ada). | 🟠 **TINGGI** | Terbukti di Kode |
| **APP-02** | Android Native | Hilangnya deklarasi Foreground Service Tipe Lokasi di `AndroidManifest.xml` (Diblokir Android 14+). | 🟠 **TINGGI** | Terbukti di Kode |
| **APP-03** | Flutter / Storage | PIN Mode HP Hilang tersimpan teks polos (*plaintext*) dan default hardcoded `'1234'` di `SharedPreferences`. | 🟡 **SEDANG** | Terbukti di Kode |
| **APP-04** | Flutter / Network | Tidak ada antrean offline (*offline retry queue*) untuk lokasi, dan hilangnya alur hapus akun/keluar lingkaran. | 🟢 **RENDAH** | Terbukti di Kode |

---

## 2. DETAIL AUDIT SUPABASE (DATABASE, RLS & STORAGE)

---

### SEC-01: Kebocoran Seluruh Kode Undangan Keluarga (*Invite Code*)
* **Lokasi Kode:** 
  - `migration_full.sql` baris 325–329
  - `fix_relations.sql` baris 15–18
* **Bukti Teknis:**
  ```sql
  -- Policies for Circles (SELECT remains open so users can preview invite codes)
  DROP POLICY IF EXISTS "Authenticated users can view circles" ON public.circles;
  CREATE POLICY "Authenticated users can view circles" ON public.circles 
      FOR SELECT TO authenticated USING (true);
  ```
* **Dampak:** 
  Klausa `USING (true)` mengizinkan siapa pun yang login di aplikasi mengeksekusi `supabase.from('circles').select('name, invite_code, created_by')`. Penyerang dapat mengumpulkan seluruh kode undangan keluarga di database, lalu menyusup ke dalam keluarga mana pun menggunakan fungsi `join_circle_by_code()`.
* **Tingkat Risiko:** 🔴 **KRITIS**
* **Rekomendasi Perbaikan:**
  Batasi policy SELECT tabel `circles` hanya untuk anggota lingkaran atau pembuat lingkaran:
  ```sql
  DROP POLICY IF EXISTS "Authenticated users can view circles" ON public.circles;
  CREATE POLICY "Members or creators can view circles" ON public.circles 
      FOR SELECT TO authenticated 
      USING (created_by = auth.uid() OR public.is_member_of(id));
  ```
  Alur join circle tetap berfungsi normal tanpa policy terbuka ini karena ditangani oleh fungsi `SECURITY DEFINER` `join_circle_by_code(p_code)`.
* **Tes Verifikasi:**
  Login dengan Akun B (bukan anggota Circle A). Jalankan `client.from('circles').select().eq('id', circleA.id)`. Hasil kueri harus kosong (`[]`).

---

### SEC-02: Bucket Penyimpanan Audio & Foto Kamera Terbuka Bebas untuk Publik
* **Lokasi Kode:**
  - `migration_full.sql` baris 496–506
  - `ambient_audio_schema.sql` baris 1–14
  - `lib/services/intruder_camera_service.dart` baris 71–82
  - `lib/services/audio_service.dart` baris 133–135
* **Bukti Teknis:**
  ```sql
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('ambient_audio', 'ambient_audio', true)
  ON CONFLICT (id) DO NOTHING;

  CREATE POLICY "Authenticated users can upload audio" ON storage.objects 
      FOR INSERT TO authenticated WITH CHECK (bucket_id = 'ambient_audio');

  CREATE POLICY "Authenticated users can read audio" ON storage.objects 
      FOR SELECT TO authenticated USING (bucket_id = 'ambient_audio');
  ```
  Pada sisi client:
  ```dart
  final storagePath = 'intruder_photos/intruder_$timestamp.jpg';
  publicUrl = Supabase.instance.client.storage.from('ambient_audio').getPublicUrl(storagePath);
  ```
* **Dampak:** 
  1. Pengaturan `public: true` memungkinkan tautan URL file diakses siapa saja tanpa token autentikasi.
  2. Policy `storage.objects` mengizinkan seluruh user terautentikasi membaca objek apa pun di bucket `ambient_audio`.
  3. Foto wajah pemilik/anggota keluarga (hasil jepretan kamera depan saat PIN salah) dan rekaman audio mikrofon anak/keluarga dapat diakses dan diunduh oleh pengguna lain di luar lingkaran keluarga.
* **Tingkat Risiko:** 🔴 **KRITIS**
* **Rekomendasi Perbaikan:**
  1. Ubah konfigurasi bucket menjadi privat (`public = false`).
  2. Susun hierarki path folder: `recordings/<circle_id>/<user_id>/<filename>.m4a` dan `intruder_photos/<user_id>/<filename>.jpg`.
  3. Buat policy RLS `storage.objects` yang membatasi hak baca hanya kepada pemilik atau anggota lingkaran yang bersangkutan menggunakan *signed URL* bertenggang waktu singkat.
* **Tes Verifikasi:**
  Akun C di luar lingkaran mencoba mengambil file audio/foto Akun A melalui HTTP GET dan kueri storage. PostgREST/Storage API harus mengembalikan `403 Forbidden`.

---

### SEC-03: Eskalasi Peran (*Privilege Escalation*) pada Tabel `circle_members`
* **Lokasi Kode:**
  - `migration_full.sql` baris 336–338
* **Bukti Teknis:**
  ```sql
  CREATE POLICY "Admins or self can update circle members" ON public.circle_members 
      FOR UPDATE TO authenticated 
      USING (auth.uid() = user_id OR EXISTS (SELECT 1 FROM public.circles WHERE id = circle_members.circle_id AND created_by = auth.uid()));
  ```
* **Dampak:**
  Klausa `auth.uid() = user_id` memberikan akses UPDATE tanpa klausa pembatas kolom `WITH CHECK`. Akibatnya, anggota biasa (`role = 'member'`) dapat mengeksekusi:
  ```dart
  await client.from('circle_members').update({'role': 'admin'}).eq('user_id', myUid);
  ```
  dan berhasil mengangkat dirinya sendiri menjadi Admin lingkaran keluarga tanpa izin pemilik keluarga.
* **Tingkat Risiko:** 🔴 **KRITIS**
* **Rekomendasi Perbaikan:**
  Pisahkan hak pembaruan `circle_members`:
  ```sql
  DROP POLICY IF EXISTS "Admins or self can update circle members" ON public.circle_members;

  -- Pengguna biasa hanya boleh memperbarui status berbagi lokasi miliknya
  CREATE POLICY "Users can update own location sharing" ON public.circle_members
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id AND role = 'member');

  -- Hanya admin/pembuat lingkaran yang boleh mengubah role
  CREATE POLICY "Creators can update members" ON public.circle_members
      FOR UPDATE TO authenticated
      USING (EXISTS (SELECT 1 FROM public.circles WHERE id = circle_members.circle_id AND created_by = auth.uid()));
  ```
* **Tes Verifikasi:**
  Login sebagai joiner (role member), lakukan kueri update `{'role': 'admin'}`. Kueri harus gagal dengan pelanggaran RLS.

---

### SEC-04: Pelanggaran Privasi Lokasi saat Berbagi Lokasi Dinonaktifkan
* **Lokasi Kode:**
  - `migration_full.sql` baris 196–213 (`is_co_member_with`)
  - `migration_full.sql` baris 340–344 (`user_locations` policy)
  - `migration_full.sql` baris 408–413 (`location_history` policy)
* **Bukti Teknis:**
  Kolom `is_sharing_location` tersedia di `circle_members`, namun fungsi pembantu otorisasi lokasi hanya memeriksa:
  ```sql
  CREATE OR REPLACE FUNCTION public.is_co_member_with(p_user_id UUID)
  RETURNS BOOLEAN AS $$
  BEGIN
      IF p_user_id = auth.uid() THEN RETURN TRUE; END IF;
      RETURN EXISTS (
          SELECT 1 FROM public.circle_members cm1
          JOIN public.circle_members cm2 ON cm1.circle_id = cm2.circle_id
          WHERE cm1.user_id = auth.uid() AND cm2.user_id = p_user_id
      );
  END;
  $$;
  ```
* **Dampak:**
  Fungsi tersebut sama sekali tidak memeriksa `cm2.is_sharing_location = TRUE`. Saat anggota mematikan sakelar berbagi lokasi di UI, koordinat realtime dan riwayat linimasa perjalanannya **tetap dapat ditarik secara bebas oleh seluruh anggota lingkaran**.
* **Tingkat Risiko:** 🟠 **TINGGI**
* **Rekomendasi Perbaikan:**
  Buat fungsi otorisasi khusus lokasi `can_view_location_of(target_uid UUID)`:
  ```sql
  CREATE OR REPLACE FUNCTION public.can_view_location_of(p_user_id UUID)
  RETURNS BOOLEAN AS $$
  BEGIN
      IF p_user_id = auth.uid() THEN RETURN TRUE; END IF;
      
      -- Selalu izinkan jika target sedang dalam kondisi SOS darurat aktif
      IF EXISTS (SELECT 1 FROM public.sos_alerts WHERE user_id = p_user_id AND status = 'active') THEN
          RETURN TRUE;
      END IF;

      -- Izinkan jika target tergabung dalam lingkaran bersama pemanggil DAN is_sharing_location = TRUE
      RETURN EXISTS (
          SELECT 1 FROM public.circle_members cm_viewer
          JOIN public.circle_members cm_target ON cm_viewer.circle_id = cm_target.circle_id
          WHERE cm_viewer.user_id = auth.uid() 
            AND cm_target.user_id = p_user_id 
            AND cm_target.is_sharing_location = TRUE
      );
  END;
  $$;
  ```
* **Tes Verifikasi:**
  Akun A menyetel `is_sharing_location = false`. Akun B (satu lingkaran) melakukan SELECT pada `user_locations` dan `location_history` Akun A. Hasil kueri harus kosong.

---

### SEC-05: Injeksi Perintah Jarak Jauh Sembarangan (*Arbitrary Remote Commands*)
* **Lokasi Kode:**
  - `migration_full.sql` baris 415–427
* **Bukti Teknis:**
  ```sql
  CREATE POLICY "Circle members can manage remote commands"
  ON public.remote_commands FOR ALL TO authenticated
  USING (
      sender_id = auth.uid()
      OR target_user_id = auth.uid()
      OR (circle_id IS NOT NULL AND public.is_member_of(circle_id))
  )
  WITH CHECK (
      sender_id = auth.uid()
      OR target_user_id = auth.uid()
      OR (circle_id IS NOT NULL AND public.is_member_of(circle_id))
  );
  ```
* **Dampak:**
  1. Klausa `WITH CHECK` memperbolehkan insert apa pun jika `circle_id` adalah lingkaran di mana pemanggil menjadi anggota, tanpa memvalidasi `sender_id = auth.uid()`.
  2. Tidak ada pengecekan hak akses admin untuk tindakan destruktif: anggota mana pun dapat mengirimkan perintah `command_type = 'remote_wipe'`, `lost_mode_on`, atau `fake_shutdown` ke ponsel anggota lain di lingkaran tersebut.
* **Tingkat Risiko:** 🟠 **TINGGI**
* **Rekomendasi Perbaikan:**
  1. Wajibkan `sender_id = auth.uid()` pada operasi `INSERT`.
  2. Perintah `remote_wipe` dan `lost_mode_on` hanya boleh di-insert jika sender adalah `admin` atau pembuat lingkaran (`created_by`).
  3. Status perintah hanya boleh diubah menjadi `executed` oleh `target_user_id = auth.uid()`.
* **Tes Verifikasi:**
  Akun member biasa mengirim perintah `remote_wipe` ke akun anggota lain. Database harus menolak kueri INSERT tersebut.

---

### SEC-06: Injeksi Sirene Keras & Perekaman Audio Lintas Lingkaran
* **Lokasi Kode:**
  - `migration_full.sql` baris 365–366
  - `migration_full.sql` baris 403–404
* **Bukti Teknis:**
  ```sql
  CREATE POLICY "Members can send loud signals" ON public.loud_signals 
      FOR INSERT TO authenticated 
      WITH CHECK (sender_id = auth.uid() AND (circle_id IS NULL OR is_member_of(circle_id)));

  CREATE POLICY "Members can create audio requests" ON public.audio_requests 
      FOR INSERT TO authenticated 
      WITH CHECK (requester_id = auth.uid() AND (circle_id IS NULL OR is_member_of(circle_id)));
  ```
* **Dampak:**
  Adanya opsi `circle_id IS NULL` memungkinkan penyerang mengirim sinyal sirene keras atau permintaan perekaman mikrofon rahasia ke **pengguna mana pun di seluruh database** tanpa harus berada di lingkaran yang sama.
* **Tingkat Risiko:** 🟠 **TINGGI**
* **Rekomendasi Perbaikan:**
  Hapus klausa `circle_id IS NULL`. Wajibkan `circle_id IS NOT NULL`, pengirim adalah anggota lingkaran tersebut, dan target juga terdaftar di lingkaran yang sama.
* **Tes Verifikasi:**
  Kirim baris ke `loud_signals` dengan `circle_id: null` dan target pengguna di luar lingkaran. Kueri harus gagal.

---

### SEC-07: Anggota Biasa Dapat Menghapus Zona Aman Lingkaran (*Geofences*)
* **Lokasi Kode:**
  - `migration_full.sql` baris 389–390
* **Bukti Teknis:**
  ```sql
  CREATE POLICY "Members can delete geofences" ON public.geofences 
      FOR DELETE TO authenticated USING (is_member_of(circle_id));
  ```
* **Dampak:**
  Anggota biasa (termasuk anak yang dipantau) dapat menghapus zona aman penting (seperti "Rumah" atau "Sekolah") yang ditentukan oleh orang tua/kepala keluarga.
* **Tingkat Risiko:** 🟡 **SEDANG**
* **Rekomendasi Perbaikan:**
  Batasi operasi DELETE pada tabel `geofences` hanya untuk Admin lingkaran atau pembuat geofence (`created_by = auth.uid()`).
* **Tes Verifikasi:**
  Akun bertipe member mencoba menghapus baris geofence. Operasi harus ditolak oleh RLS.

---

### SEC-08: Inkonsistensi Project Ref Database Supabase
* **Lokasi Kode:**
  - `migration_full.sql` baris 3: `Project: xtgumpluxciqesahpxuk (rezayasha's Project)`
  - `lib/constants.dart` baris 3: `https://uwxecnbeqeysnlzwdcha.supabase.co`
  - `android/app/src/main/kotlin/.../SosDirectSender.kt` baris 37: `https://uwxecnbeqeysnlzwdcha.supabase.co`
* **Bukti Teknis:**
  Terdapat dua Project ID berbeda antara skrip SQL repositori (`xtgumpluxciqesahpxuk`) dan runtime aplikasi aktif (`uwxecnbeqeysnlzwdcha`).
* **Dampak:**
  Skrip migrasi di repositori mungkin tidak mencerminkan kebijakan RLS dan fungsi yang sedang aktif berjalan di instance Supabase produksi.
* **Tingkat Risiko:** 🟡 **SEDANG**
* **Rekomendasi Perbaikan:**
  Lakukan sinkronisasi skema dan audit langsung terhadap instance `uwxecnbeqeysnlzwdcha`.

---

## 3. DETAIL AUDIT FLUTTER & ANDROID NATIVE

---

### APP-01: FCM Push Notification & High-Priority Wakeup Belum Terintegrasi (Mocked)
* **Lokasi Kode:**
  - `pubspec.yaml`
  - `lib/services/push_notification_service.dart` baris 30–36
  - Berkas `android/app/google-services.json` (Tidak ditemukan)
* **Bukti Teknis:**
  1. `pubspec.yaml` tidak memuat dependensi `firebase_core` maupun `firebase_messaging`.
  2. Berkas konfigurasi `google-services.json` tidak ada di folder `android/app/`.
  3. `PushNotificationService` hanya membaca string simulasi dari `prefs.getString('cached_fcm_token')`.
* **Dampak:**
  Ketika aplikasi dimatikan dari Recent Apps atau proses ditutup oleh Android OS, **koneksi WebSocket Supabase Realtime terputus total**. Perangkat target **tidak dapat dibangunkan dari jarak jauh** untuk menerima perintah Mode HP Hilang, sirene keras, atau peringatan SOS darurat.
* **Tingkat Risiko:** 🟠 **TINGGI**
* **Rekomendasi Perbaikan:**
  Integrasikan SDK resmi `firebase_core` dan `firebase_messaging` dengan konfigurasi payload prioritas tinggi (*High Priority Data Messages*) yang mampu memicu `WakeLock` dan mengeksekusi receiver saat aplikasi mati.
* **Tes Verifikasi:**
  Tutup paksa aplikasi di emulator (`am force-stop`), picu SOS dari akun lain. Notifikasi darurat harus tetap muncul di bilah status.

---

### APP-02: Pelacakan Lokasi Latar Belakang Rentan Dibunuh Android 14+
* **Lokasi Kode:**
  - `android/app/src/main/AndroidManifest.xml` baris 7–8
  - `android/app/src/main/AndroidManifest.xml` baris 72–105
* **Bukti Teknis:**
  `AndroidManifest.xml` mendeklarasikan permission:
  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
  ```
  Tetapi di dalam tag `<application>`, tidak ada satu pun service dengan `android:foregroundServiceType="location"`. Service yang ada hanyalah bertipe `specialUse`.
* **Dampak:**
  Mulai Android 14 (API 34), sistem mewajibkan deklarasi eksplisit `foregroundServiceType="location"`. Tanpa service native ini, pelacakan lokasi di latar belakang hanya mengandalkan stream Dart `Geolocator`, yang akan dibekukan oleh sistem saat layar ponsel mati atau masuk mode Doze.
* **Tingkat Risiko:** 🟠 **TINGGI**
* **Rekomendasi Perbaikan:**
  Deklarasikan dan jalankan Foreground Service native bertipe `location` lengkap dengan notifikasi persisten aktif yang transparan bagi pengguna.
* **Tes Verifikasi:**
  Jalankan aplikasi di Android 14, kunci layar selama 15 menit. Pastikan titik koordinat di `user_locations` tetap terbarui secara berkala.

---

### APP-03: Penyimpanan PIN Mode HP Hilang dalam Bentuk Teks Polos (*Plaintext*)
* **Lokasi Kode:**
  - `lib/services/phone_protection_service.dart` baris 831–833
  - `lib/services/phone_protection_service.dart` baris 915–917
* **Bukti Teknis:**
  ```dart
  Future<String> getOwnerPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLostModePin) ?? '1234';
  }
  ```
* **Dampak:**
  1. Default PIN bernilai `'1234'`, sehingga sangat mudah ditebak oleh pihak yang menemukan/mencuri ponsel.
  2. PIN disimpan di `SharedPreferences` standar Android (file XML tidak terenkripsi), sehingga dapat dibaca dengan mudah jika perangkat di-root atau dicadangkan via ADB backup.
* **Tingkat Risiko:** 🟡 **SEDANG**
* **Rekomendasi Perbaikan:**
  Simpan PIN dalam bentuk *salted hash* (SHA-256 + salt) atau gunakan Android Keystore melalui `flutter_secure_storage`. Hapus nilai default PIN yang mudah ditebak dan wajibkan pengguna mengatur PIN sendiri.
* **Tes Verifikasi:**
  Periksa isi berkas XML SharedPreferences pada emulator. Pastikan tidak ada karakter PIN asli yang terlihat.

---

### APP-04: Tidak Ada Antrean Lokasi Offline & Ketiadaan Alur Hapus Akun
* **Lokasi Kode:**
  - `lib/services/location_service.dart` baris 187–220
  - `lib/services/supabase_service.dart`
* **Bukti Teknis:**
  Blok `_syncLocation()` membungkus pemanggilan jaringan dengan `catch (_) {}` kosong tanpa mekanisme *local caching/retry queue*.
  Selain itu, tidak ditemukan fungsi `deleteAccount()` maupun `leaveCircle()` pada `supabase_service.dart`.
* **Dampak:**
  1. Titik koordinat yang dilewati saat sinyal hilang/terputus hilang permanen dari riwayat linimasa perjalanan.
  2. Pengguna tidak memiliki opsi untuk keluar dari lingkaran keluarga atau menghapus akun beserta data pribadinya secara mandiri dari aplikasi (pelanggaran UU PDP dan pedoman Google Play Store).
* **Tingkat Risiko:** 🟢 **RENDAH**
* **Rekomendasi Perbaikan:**
  Sediakan antrean lokal sementara (misal 50 titik terakhir) saat koneksi terputus, serta implementasikan fungsi RPC `delete_my_account()` dan `leave_circle()`.
* **Tes Verifikasi:**
  Aktifkan Airplane Mode, tunggu 1 menit, matikan Airplane Mode. Titik riwayat harus tersinkronisasi kembali ke `location_history`.

---

## 4. RENCANA PERBAIKAN BERTAHAP (TAHAP 2 ROADMAP)

Sesuai aturan utama, perbaikan akan dilakukan secara bertahap tanpa merusak fungsionalitas yang ada:

### Tahap 2A: Pembuatan File Migrasi SQL Aman (`migration_security_fixes.sql`)
1. Kunci kueri SELECT `public.circles` agar hanya bisa diakses oleh creator atau member.
2. Perketat policy UPDATE pada `circle_members` untuk mencegah *self-promotion* role admin.
3. Perbaiki fungsi `can_view_location_of()` untuk menghormati sakelar `is_sharing_location`.
4. Hapus klausa `circle_id IS NULL` pada `loud_signals` dan `audio_requests`.
5. Ubah bucket `ambient_audio` menjadi privat dan terapkan signed URL.
6. Tambahkan fungsi RPC `leave_circle()` dan `delete_my_account()`.

### Tahap 2B: Penyesuaian Kode Sumber Flutter
1. Update `IntruderCameraService` dan `AudioService` untuk menggunakan signed URL atau upload ke folder terisolasi per-user.
2. Tambahkan penanganan null-safety pada deserializer model `models.dart`.
3. Ganti penyimpanan PIN di `phone_protection_service.dart` menggunakan salted hash.
4. Implementasikan metode `leaveCircle()` dan `deleteAccount()` di `supabase_service.dart`.

### Tahap 2C: Verifikasi & Pengujian Komprehensif
1. Uji otorisasi menggunakan 3 skenario:
   - Akun A dan Akun B dalam satu lingkaran.
   - Akun C di lingkaran berbeda.
   - Akun D tanpa lingkaran.
2. Uji ketahanan latar belakang (*background persistence*) pada Android 14.
3. Jalankan automated test suite `flutter test`.
