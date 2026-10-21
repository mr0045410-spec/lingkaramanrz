# RENCANA PERBAIKAN TEKNIS & KEAMANAN LINGKARAMAN (REVISI TAHAP 2)
**Dokumen Perencanaan Lengkap, Analisis Risiko Regresi, dan Matriks Pengujian**  
*Mencakup Perbaikan Review SQL (A1–A3) dan Temuan Tambahan (B1–B4)*

---

## 1. PENGELOMPOKAN MASALAH SESUAI TINGKAT RISIKO

### 🔴 Risiko Kritis (Immediate Priority)
1. **SEC-01:** Kebocoran seluruh kode undangan (*invite code*) keluarga melalui policy `circles` SELECT `USING (true)`.
2. **SEC-02:** Bucket storage `ambient_audio` terbuka publik dan policy terbuka mengizinkan pengunduhan rekaman suara & foto penyusup lintas pengguna.
3. **SEC-03:** Celah eskalasi peran (*privilege escalation*) di mana anggota biasa dapat mengangkat diri menjadi admin via PostgREST UPDATE pada `circle_members`.

### 🟠 Risiko Tinggi (High Priority)
4. **SEC-04:** Pelanggaran privasi di mana koordinat realtime & linimasa riwayat tetap terbaca meski `is_sharing_location = false`.
5. **SEC-05:** Injeksi perintah `remote_commands` (*remote_wipe*, *lost_mode_on*) yang dapat dikirim sembarangan oleh anggota biasa.
6. **SEC-06:** Injeksi sinyal sirene keras (`loud_signals`) dan permintaan sadap mikrofon (`audio_requests`) ke pengguna di luar lingkaran akibat `circle_id IS NULL`.
7. **APP-01:** Kegagalan penerimaan push notifikasi & perintah jarak jauh saat aplikasi ditutup (ketiadaan integrasi Firebase Cloud Messaging).
8. **APP-02:** Pelacakan lokasi latar belakang rentan dibekukan oleh Android 14+ karena ketiadaan deklarasi Foreground Service bertipe `location`.
9. **SEC-09 (B1):** Eksploitasi `MainActivity` berstatus `exported="true"` tanpa validasi pengirim, memungkinkan aplikasi jahat di perangkat memicu sinyal SOS palsu atau penguncian palsu via explicit intent.
10. **SEC-10 (B2):** Konfigurasi rilis APK ditandatangani menggunakan kunci debug (`signingConfigs.debug`), merusak integritas rantai pembaruan aplikasi dan membuka celah pemalsuan APK.
11. **SEC-11 (B3):** Kredensial sensitif `access_token` sesi Supabase tersimpan dalam bentuk teks polos (*plaintext*) di `SharedPreferences` standar.
12. **SEC-12 (B4):** Parameter `android:allowBackup` tidak didefinisikan pada `AndroidManifest.xml` (default `true`), memungkinkan ekstraksi data preferensi sensitif (token sesi + PIN) melalui ADB backup atau pencadangan cloud.

### 🟡 Risiko Sedang (Medium Priority)
13. **SEC-07:** Anggota biasa dapat menghapus (*DELETE*) zona aman (*geofences*) keluarga.
14. **SEC-08:** Inkonsistensi Project ID Supabase pada dokumen migrasi (`xtgumpluxciqesahpxuk`) dan runtime aplikasi (`uwxecnbeqeysnlzwdcha`).
15. **APP-03:** PIN pembuka Mode HP Hilang tersimpan teks polos (*plaintext*) dengan default `'1234'` di `SharedPreferences`.

### 🟢 Risiko Rendah (Low Priority)
16. **APP-04:** Tidak adanya antrean lokal (*offline retry queue*) saat koneksi terputus dan ketiadaan menu keluar lingkaran / hapus akun mandiri.

---

## 2. DETAIL PERBAIKAN NASKAH SQL (POIN A1, A2, DAN A3)

### A1. Guard Regex UUID pada Policy SELECT `storage.objects`
* **Masalah:** File legacy hasil jepretan kamera penyusup disimpan dengan format `intruder_photos/intruder_<timestamp>.jpg`. Path folder pertamanya adalah string `intruder_photos`. Jika langsung di-cast dengan `((storage.foldername(name))[1])::uuid`, PostgreSQL akan melempar *syntax error invalid input syntax for type uuid*. Di PostgreSQL, error di dalam policy RLS menyebabkan **seluruh kueri SELECT gagal**, bukan sekadar baris tersebut ditolak.
* **Perbaikan yang Diterapkan di `migration_security_fixes.sql`:**
  ```sql
  DROP POLICY IF EXISTS "Authorized users can read storage objects" ON storage.objects;

  CREATE POLICY "Authorized users can read storage objects" ON storage.objects
      FOR SELECT TO authenticated
      USING (
          bucket_id = 'ambient_audio'
          AND (
              (storage.foldername(name))[1] = auth.uid()::text
              OR (
                  (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  AND public.is_co_member_with(((storage.foldername(name))[1])::uuid)
              )
          )
      );
  ```

### A2. Klausa `WITH CHECK` Eksplisit pada Policy UPDATE `circle_members` (2b)
* **Masalah:** Policy pembaruan oleh admin sebelumnya hanya mendefinisikan `USING` tanpa `WITH CHECK`. Perilaku default PostgreSQL untuk UPDATE tanpa `WITH CHECK` dapat menjadi ambigu dan membahayakan barikade pertahanan anti-eskalasi peran.
* **Perbaikan yang Diterapkan di `migration_security_fixes.sql`:**
  Menambahkan klausa `WITH CHECK` eksplisit yang mencerminkan klausa `USING`:
  ```sql
  CREATE POLICY "Admins or creators can update circle members" ON public.circle_members
      FOR UPDATE TO authenticated
      USING (
          EXISTS (
              SELECT 1 FROM public.circles c
              WHERE c.id = circle_members.circle_id
                AND (
                    c.created_by = auth.uid()
                    OR EXISTS (
                        SELECT 1 FROM public.circle_members cm
                        WHERE cm.circle_id = circle_members.circle_id
                          AND cm.user_id = auth.uid()
                          AND cm.role = 'admin'
                    )
                )
          )
      )
      WITH CHECK (
          EXISTS (
              SELECT 1 FROM public.circles c
              WHERE c.id = circle_members.circle_id
                AND (
                    c.created_by = auth.uid()
                    OR EXISTS (
                        SELECT 1 FROM public.circle_members cm
                        WHERE cm.circle_id = circle_members.circle_id
                          AND cm.user_id = auth.uid()
                          AND cm.role = 'admin'
                    )
                )
          )
      );
  ```

### A3. Keterbatasan Diketahui pada `delete_my_account()` & Usulan Tindak Lanjut
* **Keterbatasan 1 (Autentikasi):** Fungsi SQL `delete_my_account()` hanya dapat beroperasi pada skema `public`. Baris di `auth.users` **TIDAK** ikut terhapus karena akun auth dikelola secara eksklusif oleh service GoTrue. Jika pengguna melakukan registrasi/login ulang dengan email yang sama, trigger `on_auth_user_created` akan secara otomatis membangkitkan baris profil baru.
* **Keterbatasan 2 (Berkas Storage):** Berkas rekaman suara dan foto yang tersimpan pada bucket `ambient_audio` tidak terhapus otomatis melalui fungsi SQL ini karena keterbatasan fungsi internal storage.
* **Tindak Lanjut Wajib:**
  1. Membangun **Supabase Edge Function** (`delete-user-account`) yang diamankan dengan `service_role` key.
  2. Edge function memanggil API administratif `supabase.auth.admin.deleteUser(uid)`.
  3. Edge function mengeksekusi penghapusan seluruh objek storage di bawah prefix folder `<uid>/`.
  4. *Catatan Status:* Fungsi SQL `delete_my_account()` saat ini bertindak sebagai **pembersihan data relasional (soft-wipe)**, dan tidak diklaim sebagai pemenuhan 100% hak hapus data (Right to Erasure / UU PDP) hingga Edge Function tersebut diterapkan.

---

## 3. ANALISIS & RENCANA PERBAIKAN TEMUAN TAMBAHAN (B1–B4)

---

### B1. SEC-09 — Eksploitasi `MainActivity` Exported Memicu SOS Palsu
* **File & Lokasi:** 
  - [`android/app/src/main/AndroidManifest.xml`](file:///g:/AI%20APP/aplikasi%20circle/lingkar_aman/android/app/src/main/AndroidManifest.xml#L35-L58)
  - [`android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/MainActivity.kt`](file:///g:/AI%20APP/aplikasi%20circle/lingkar_aman/android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/MainActivity.kt#L164-L230)
* **Bukti Teknis:**
  `MainActivity` memiliki atribut `android:exported="true"` (wajib karena merupakan activity launcher utama). Namun, pada `onCreate` dan `onNewIntent`, activity langsung membaca:
  ```kotlin
  if (intent.getBooleanExtra("trigger_sos_immediately", false)) { ... }
  if (intent.getBooleanExtra("lost_mode_locked", false)) { ... }
  ```
  tanpa memverifikasi asal pengirim Intent.
* **Dampak:** 
  Aplikasi jahat lain (malware / adware) yang terpasang pada perangkat yang sama dapat mengirimkan Intent eksplisit:
  ```bash
  am start -n com.lingkaraman.lingkar_aman/.MainActivity --ez trigger_sos_immediately true
  ```
  yang akan memicu pancaran sinyal darurat SOS palsu ke keluarga atau mengunci layar tanpa otorisasi!
* **Analisis Risiko Regresi:**
  - Jika `android:exported="false"`, aplikasi tidak akan bisa dibuka dari launcher Android (aplikasi tidak bisa di-launch!).
  - Jika Intent dari internal (seperti `BootReceiver`, `SosTileService`, dan notification pending intent) diblokir, fitur Quick Settings Tile dan Auto-lock setelah reboot akan rusak.
* **Rencana Perbaikan:**
  1. Tetap pertahankan `android:exported="true"` pada `MainActivity`.
  2. Buat mekanisme validasi pengirim intent internal:
     - Gunakan `PendingIntent` dengan flag `FLAG_IMMUTABLE` yang ditandatangani oleh package internal.
     - Tambahkan verifikasi token rahasia internal pada ekstra Intent (One-Time Token internal yang di-generate oleh memory aplikasi) ATAU validasi `callingPackage == packageName`.
     - Pindahkan pemicu background langsung ke `BroadcastReceiver` internal yang disetel `android:exported="false"`.
* **Rencana Pengujian:**
  Jalankan perintah ADB dari luar package untuk mengirim extra `trigger_sos_immediately true`. `MainActivity` harus menolak memproses extra tersebut dan mencatat log warning keamanan.

---

### B2. SEC-10 — Build Release Ditandatangani Menggunakan Kunci Debug
* **File & Lokasi:** 
  - [`android/app/build.gradle.kts`](file:///g:/AI%20APP/aplikasi%20circle/lingkar_aman/android/app/build.gradle.kts)
* **Bukti Teknis:**
  ```kotlin
  buildTypes {
      release {
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
* **Dampak:** 
  Sertifikat debug Android (`debug.keystore`) memiliki kunci privat publik yang seragam di seluruh dunia (password: `android`). APK rilis yang ditandatangani dengan kunci debug rentan terhadap *tampering*, *repackaging*, dan kehilangan integritas pembaruan di Google Play Store atau distribusi langsung.
* **Analisis Risiko Regresi:**
  - Mengubah keystore release secara sembarangan pada aplikasi yang sudah terinstal di perangkat pengguna akan menyebabkan error `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (aplikasi lama harus di-uninstall terlebih dahulu sebelum memasang build baru).
* **Rencana Perbaikan:**
  1. Buat keystore produksi tersendiri: `lingkaraman-release.jks`.
  2. Buat konfigurasi aman `android/key.properties` yang membaca path keystore, password, dan alias kunci.
  3. Masukkan `android/key.properties` dan `*.jks` ke dalam `.gitignore` agar kredensial tidak pernah bocor ke repository Git.
  4. Perbarui `build.gradle.kts` agar membaca `key.properties` jika tersedia, dan hanya fallback ke debug jika dalam mode development lokal.
* **Rencana Pengujian:**
  Jalankan `flutter build apk --release`. Verifikasi tanda tangan APK menggunakan `apksigner verify --verbose` untuk memastikan sertifikat bukan dari Android Debug CN.

---

### B3. SEC-11 — Access Token Sesi Tersimpan Teks Polos (*Plaintext*) di SharedPreferences
* **File & Lokasi:** 
  - [`lib/services/location_service.dart`](file:///g:/AI%20APP/aplikasi%20circle/lingkar_aman/lib/services/location_service.dart#L232-L236)
  - [`android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/SosDirectSender.kt`](file:///g:/AI%20APP/aplikasi%20circle/lingkar_aman/android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/SosDirectSender.kt#L39)
* **Bukti Teknis:**
  ```dart
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token != null && token.isNotEmpty) {
    await prefs.setString('access_token', token);
  }
  ```
  Di sisi Kotlin:
  ```kotlin
  val accessToken = getPrefString(prefs, "access_token")
  ```
* **Dampak:** 
  `access_token` JWT memberikan hak akses penuh atas nama pengguna ke REST API Supabase. Menyimpannya di `SharedPreferences` biasa (file XML polos di `/data/data/...`) membuat token rentan dicuri melalui ADB backup, aplikasi inspeksi file root, atau eksploitasi lokal lainnya.
* **Analisis Risiko Regresi:**
  - `SosDirectSender.kt` (native service darurat saat Flutter mati) memerlukan token ini untuk memancarkan sinyal darurat langsung via HTTP POST. Jika token dienkripsi tanpa sinkronisasi kunci ke native Kotlin, pengiriman SOS native offline bisa gagal otentikasi.
* **Rencana Perbaikan:**
  1. Gunakan `flutter_secure_storage` atau Android `EncryptedSharedPreferences` (MasterKey Keystore).
  2. Di sisi Android native, gunakan pustaka AndroidX Security `EncryptedSharedPreferences` untuk membaca token dari shared preferences yang terenkripsi secara seragam antara Flutter dan Kotlin.
* **Rencana Pengujian:**
  Inspeksi berkas `FlutterSharedPreferences.xml`. Pastikan string `access_token` tidak lagi muncul dalam format JWT plaintext (`eyJhbGciOi...`).

---

### B4. SEC-12 — Ketiadaan Konfigurasi `android:allowBackup` pada Manifest
* **File & Lokasi:** 
  - [`android/app/src/main/AndroidManifest.xml`](file:///g:/AI%20APP/aplikasi%20circle/lingkar_aman/android/app/src/main/AndroidManifest.xml#L31-L34)
* **Bukti Teknis:**
  Tag `<application>` didefinisikan tanpa atribut `android:allowBackup`:
  ```xml
  <application
      android:label="LingkarAman"
      android:name="${applicationName}"
      android:icon="@mipmap/ic_launcher">
  ```
  Secara default pada Android, jika tidak dispesifikasikan, nilai `allowBackup` adalah `true`.
* **Dampak:** 
  Penyerang dengan akses fisik sementara (atau kabel USB via ADB) dapat menjalankan perintah:
  ```bash
  adb backup -f backup.ab com.lingkaraman.lingkar_aman
  ```
  dan mengekstrak seluruh basis data lokal, preferensi, PIN teks polos, serta token sesi ke komputer penyerang.
* **Analisis Risiko Regresi:**
  - Menonaktifkan backup (`android:allowBackup="false"`) berarti data lokal tidak akan dicadangkan saat pengguna berganti perangkat via Google Cloud Backup. Untuk aplikasi pelacak keselamatan realtime berbasis cloud (di mana seluruh data utama berada di Supabase), ini **tidak menimbulkan dampak fungsional** karena data langsung tersinkronisasi saat login kembali.
* **Rencana Perbaikan:**
  Tambahkan atribut eksplisit pada `<application>` di `AndroidManifest.xml`:
  ```xml
  <application
      android:label="LingkarAman"
      android:name="${applicationName}"
      android:icon="@mipmap/ic_launcher"
      android:allowBackup="false">
  ```
* **Rencana Pengujian:**
  Jalankan `adb backup -f test.ab com.lingkaraman.lingkar_aman`. Sistem Android harus menolak pencadangan dengan pesan bahwa aplikasi tidak mengizinkan backup.

---

## 4. MATRIKS ANALISIS DEPENDENSI & RISIKO REGRESI KESELURUHAN

| Komponen | Dependensi | Risiko Regresi Potensial | Tindakan Pencegahan |
| :--- | :--- | :--- | :--- |
| **SELECT `circles`** | Alur bergabung (`joinCircleByCode`) | Calon anggota tidak bisa bergabung ke lingkaran. | Fungsi `join_circle_by_code` berstatus `SECURITY DEFINER`, sehingga validasi kode invite tidak terpengaruh oleh RLS SELECT. |
| **UPDATE `circle_members`** | Halaman Pengaturan / Profil | Gagal mengubah sakelar "Bagi Lokasi". | Policy `WITH CHECK` mengizinkan update mandiri untuk `is_sharing_location` selama `role = 'member'`. |
| **Storage `ambient_audio`** | `IntruderCameraService` & `AudioService` | Audio atau foto gagal diunggah/diputar. | Gunakan regex guard pada SQL untuk melindungi file legacy, lalu perbarui client agar mengunggah ke `<uid>/...` dan meminta *Signed URL*. |
| **Lokasi (`can_view_location_of`)** | Tab Peta & Notifikasi SOS | Lokasi tidak terlihat saat darurat. | Ditambahkan bypass otomatis: jika ada SOS aktif, lokasi target selalu terbuka bagi keluarga. |
| **Intent `MainActivity`** | BootReceiver & QS Tile | SOS dari tombol power / Quick Tile gagal terbuka. | Validasi calling package internal atau gunakan PendingIntent internal bertanda tangan immutable. |
| **Signing Release** | Pipeline Build APK | Gagal build jika `key.properties` tidak ada. | Fallback otomatis ke konfigurasi debug pada lingkungan pengujian lokal non-CI/CD. |

---

## 5. RENCANA PENGUJIAN OTORISASI (TAHAP 4 ROADMAP)

Pengujian akan dijalankan secara otomatis melalui automated integration test suite (`test/security_authorization_matrix_test.dart`) menggunakan 4 profil akun:
- **Akun A (Admin/Creator Lingkaran 1)**.
- **Akun B (Anggota Biasa Lingkaran 1)**.
- **Akun C (Anggota Lingkaran 2 / Pihak Asing)**.
- **Akun D (Pengguna Baru Tanpa Lingkaran)**.

### Skenario Uji Wajib:
1. **Tes Kebocoran Lingkaran:** Akun C & D mencoba membaca baris `circles` milik Lingkaran 1 -> **Wajib 0 baris**.
2. **Tes Anti-Eskalasi Peran:** Akun B mencoba mengupdate `role = 'admin'` untuk dirinya sendiri -> **Wajib ditolak RLS (403)**.
3. **Tes Privasi Lokasi:** Akun B menyetel `is_sharing_location = false` -> Akun A kueri `user_locations` Akun B -> **Wajib 0 baris**.
4. **Tes Pengecualian SOS:** Akun B (lokasi nonaktif) memicu SOS -> Akun A kueri lokasi Akun B -> **Wajib berhasil terbaca**.
5. **Tes Injeksi Perintah:** Akun C mencoba mengirim `remote_commands` ke Akun B -> **Wajib ditolak RLS**.
6. **Tes Storage Privat:** Akun C mencoba mengambil foto/audio Akun B -> **Wajib ditolak (403)**.
7. **Tes Intent Injection:** Kirim Intent `trigger_sos_immediately` via ADB dari package asing -> **Wajib diabaikan**.
8. **Tes ADB Backup:** Jalankan `adb backup` -> **Wajib ditolak oleh sistem**.
