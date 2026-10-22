# PROJECT_CONTEXT: Lingkar Aman (Aplikasi Keselamatan & Pelacak Keluarga)

Dokumen ini adalah referensi persisten untuk pengembang dan agen AI guna melanjutkan pengembangan tanpa kehilangan konteks.

---

## 1. Ikhtisar Proyek & Arsitektur

**Lingkar Aman** adalah aplikasi perlindungan keluarga mandiri dan pelacakan lokasi realtime (alternatif Life360 berprivasi tinggi) yang dilengkapi proteksi fisik anti-maling, pencegahan mematikan daya paksa, serta pemantauan sensor darurat.

### Tech Stack
* **Frontend:** Flutter 3.x (Dart 3.x)
* **Peta & Geospasial:** `flutter_map` (OpenStreetMap / CartoDB Voyager tiles), `latlong2`, `geolocator`
* **Backend & Realtime:** Supabase (PostgreSQL, Realtime Subscriptions, Row Level Security / RLS, Supabase Storage)
* **Android Native Layer (Kotlin):**
  * `AntiShutdownAccessibilityService.kt`: Menjaga aksesibilitas & mencegah penarikan status bar / power menu saat layar terkunci.
  * `LostModeProtectionService.kt`: Layar penutup penuh anti-bypass saat mode hilang aktif.
  * `SosPowerService.kt` & `BootReceiver.kt`: Deteksi tombol power 3x dan autostart setelah reboot.
  * `SosTileService.kt`: Tombol cepat Quick Settings Android.
  * `InternalIntentGuard.kt`: Validasi keamanan intent antar-komponen internal.
* **Autentikasi:** Supabase Auth (Email OTP + Google Sign-In via native OAuth credential).

---

## 2. Status Fitur Terkini (Per Oktober 2026)

### A. Fitur Inti Aplikasi
- [x] **Peta Realtime & Anggota:** Pelacakan pin lokasi anggota, tingkat baterai, status pengisian daya, dan status pergerakan.
- [x] **Manajemen Lingkaran:** Buat lingkaran keluarga, gabung kode unik (6 karakter), peran Admin Utama vs Anggota.
- [x] **Obrolan Realtime Lingkaran:** Chat broadcast ke semua anggota keluarga, badge angka unread di tab bar bawah, notifikasi in-app.
- [x] **Geofencing Dasar & Riwayat:** Pembuatan radius zona aman (Rumah, Kantor, Sekolah) dan logging riwayat masuk/keluar.
- [x] **Anti-Maling & Anti-Pencopotan:** Jebakan PIN salah 4x otomatis memotret wajah penyusup, merekam suara sekitar (ambient audio) 30 detik, dan mengunggah ke Supabase Storage.
- [x] **Mode Hilang:** Kunci jarak jauh dengan sirene keras dan pesan kontak pemulihan.

### B. Fitur Tambahan (S1 s/d S6) — Lulus Uji 100%
- [x] **S1 (Low-Battery Alerting):** Peringatan otomatis saat baterai anggota < 15%, notifikasi broadcast instan ke obrolan/banner keluarga.
- [x] **S2 (Driving / Motion Detection):** Deteksi kecepatan berkendara (> 25 km/jam) dan peringatan kecepatan tinggi (> 80 km/jam).
- [x] **S3 (Anti-False SOS Countdown):** Countdown 5 detik untuk membatalkan pemicu SOS yang tidak disengaja. Dibuat **opsional** dengan sakelar OFF secara default di menu Profil.
- [x] **S4 (Smart Scheduled Geofencing):** Penjadwalan zona aman berbasis jam & hari (misal jam kantor 07:00 - 15:00, Sen-Jum). Menampilkan badge otomatis `• Di Luar Jam` dan mengabaikan transisi di luar jam operasional.
- [x] **S5 (Fake Emergency Call):** Panggilan darurat palsu realistis (Incoming Call Screen native gelap, avatar berdenyut, ringtone telepon bawaan, timer panggilan, naskah audio-visual penyelamat diri, kontrol Mute/Keypad/Speaker/End Call).
- [x] **S6 (Safety Timer / Check-in Perjalanan):** Timer hitung mundur perjalanan di floating banner atas peta.
  - *Skenario Timeout:* Otomatis memicu status SOS Darurat, menyalakan sirene, dan menyiarkan peringatan darurat ke Supabase.
  - *Skenario Check-in Sukses:* Tombol `CHECK-IN` menghentikan timer dan mengirim pesan konfirmasi selamat ke chat keluarga.

---

## 3. Konfigurasi Rilis & Repositori

* **Repositori GitHub:** `https://github.com/mr0045410-spec/lingkaramanrz.git` (Branch: `main`)
* **Versi Aplikasi:** `v0.9.5+11`
* **Keystore Produksi:**
  - File: `lingkar_aman/android/app/lingkaraman_release.jks` (Tersimpan lokal, di-gitignore)
  - Konfigurasi: `lingkar_aman/android/key.properties`
* **Artefak Build Tersedia di Root:**
  - `lingkar_aman_release.aab` (58.3 MB) — Format resmi untuk Google Play Console.
  - `lingkar_aman_release.apk` (59.4 MB) — APK Universal Release (ARM64, ARMv7, x86_64) untuk tes di HP fisik nyata.

---

## 4. Catatan Teknis & Lingkungan Penting

1. **Crash Emulator Google Sign-In (AMD Radeon):**
   - *Gejala:* Emulator Pixel 8 tertutup tiba-tiba saat verifikasi 2FA Google.
   - *Penyebab Forensik:* Driver GPU PC `atio6axx.dll` mengalami *stack buffer overrun* saat merender WebView hardware.
   - *Solusi:* Di Android Studio Virtual Device Manager > Edit AVD > *Emulated Performance* > Ubah **Graphics** ke **`Software - GLES 2.0`** atau **`ANGLE`**.
2. **Navigasi TabBar `CircleScreen` (Index 1):**
   - TabBar memiliki 2 tab: `Anggota` (kiri) dan `Zona Aman` (kanan).
   - Posisi vertikal TabBar di layar 1080x2400 berada di kisaran `Y ≈ 680 - 740` (di bawah banner proteksi dan AppBar).
3. **Penyimpanan Jadwal S4:**
   - Menggunakan SharedPreferences lokal via `GeofenceScheduleService` tanpa merusak skema tabel geofences Supabase yang sudah ada.

---

## 5. Roadmap Tugas / Next Steps

1. **Pengujian HP Fisik Nyata (Real Device Testing):**
   - Sideload `lingkar_aman_release.apk` ke minimal 2 HP fisik (misal Xiaomi/Samsung).
   - Uji background location tracking saat layar mati selama 30+ menit.
2. **Persiapan Rilis Google Play Console:**
   - Pembuatan Privacy Policy URL (wajib untuk izin lokasi latar belakang & audio).
   - Perekaman video demo 30 detik *prominent disclosure* izin `ACCESS_BACKGROUND_LOCATION`.
   - Pembuatan aset visual Play Store: Icon 512x512, Feature Graphic 1024x500, dan screenshot ponsel.
3. **Penyempurnaan Tambahan (Optional):**
   - Fitur crash / fall detection sensor kalibrasi lebih lanjut untuk berbagai jenis giroskop HP murah.
   - Integrasi Firebase Cloud Messaging (FCM) untuk push notification instan saat aplikasi ditutup total oleh OS.
