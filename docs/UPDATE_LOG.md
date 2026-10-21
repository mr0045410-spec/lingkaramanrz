# Log Pembaruan & Riwayat Perubahan (Changelog & Rollback Guide)
**Aplikasi**: LingkarAman (Circle Family Safety & Anti-Theft)

Dokumen ini mencatat setiap pembaruan arsitektural dan fitur, alasan teknis, file yang dimodifikasi, serta panduan rollback langkah demi langkah jika terjadi kendala atau regresi.

---

## [v0.7.5] - 2026-10-19: Riwayat Perjalanan Linimasa, Pemisahan Role Admin Utama vs Anggota, Notifikasi & Ringtone Chat/SOS, dan Saklar Fitur Keamanan

### 1. Riwayat Perjalanan Linimasa (Travel History & Timeline Log)
- **Masalah**: Riwayat perjalanan tidak berfungsi, kartu riwayat di Pusat Fitur tidak responsif, dan log riwayat anggota lain tidak tersedia di detail anggota.
- **Penyebab**: Koordinat GPS sebelumnya hanya menimpa tabel `user_locations` (PK: `user_id`) tanpa menyimpan log historis berurutan.
- **Solusi Arsitektural**:
  - Dibuat model data `TripPoint` di `lib/models/models.dart`.
  - Di `SupabaseService.updateMyLocation`: Setiap pembaruan lokasi kini otomatis mencatat log ke tabel `location_history` (dengan fallback penyimpanan linimasa lokal offline `loc_history_$userId`).
  - Dibuat komponen `TripHistorySheet` (`lib/widgets/trip_history_sheet.dart`): Menampilkan linimasa visual jam-demi-jam, status berhenti/bergerak, kecepatan (km/jam), sisa baterai, dan koordinat.
  - Di `MemberDetailSheet` (`lib/widgets/member_detail_sheet.dart`): Ditambahkan kartu & tombol "Riwayat Perjalanan (Linimasa)" untuk mengecek riwayat perjalanan anggota lain di lingkaran secara transparan.
  - Di `FeaturesScreen`: Kartu "Riwayat Perjalanan" kini aktif dan dapat langsung dibuka untuk melihat riwayat perjalanan pengguna sendiri.

### 2. Hierarki Peran Lingkaran: Admin Utama (Pemilik) vs Anggota
- **Masalah**: Setiap kali pengguna memasukkan kode undangan, perannya otomatis menjadi admin, sehingga seluruh anggota lingkaran menjadi admin.
- **Solusi Arsitektural**:
  - Di `joinCircleByCode` (`lib/services/supabase_service.dart`): Ditegakkan aturan mutlak bahwa siapa pun yang bergabung melalui kode undangan otomatis disetel ke `role = 'member'`. Hanya pembuat lingkaran (`created_by`) yang berhak memegang peran `admin`.
  - Di `getCircleMembers`: Dilakukan verifikasi silang dengan kolom `circles.created_by`. Pembuat lingkaran selalu dipertahankan sebagai `admin`, sedangkan pengguna lain dinormalisasi menjadi `member`.
  - Di antarmuka UI (`CircleScreen` dan `MemberDetailSheet`): Diberikan lencana badge visual yang jelas:
    - `👑 Admin Utama (Pemilik Lingkaran)`
    - `👤 Anggota Lingkaran`

### 3. Notifikasi Pesan Chat Lingkaran (Suara, Getar, dan Status Bar)
- **Masalah**: Pesan chat yang dikirim anggota lain tidak memicu notifikasi ketika aplikasi sedang berada di tab lain atau di latar belakang.
- **Solusi Arsitektural**:
  - Di `MainActivity.kt`: Ditambahkan notification channel Android dengan prioritas tinggi (`lingkaraman_chat_alert`) yang mendukung getaran dan audio notifikasi.
  - Di `HomeScreen`: Ditambahkan pendengar pesan chat realtime global (`_startGlobalChatListeners()`). Begitu ada pesan masuk dari anggota lain, sistem secara instan menampilkan notifikasi di status bar Android dan snackbar interaktif di dalam aplikasi.

### 4. Pengaturan & Pratinjau Nada Dering (Ringtone Selector)
- **Kebutuhan**: Fitur untuk memilih ringtone untuk Sinyal Keras, Alarm SOS, dan Chat.
- **Solusi Arsitektural**:
  - Dibuat layanan `SoundSettingsService` (`lib/services/sound_settings_service.dart`) dan dialog pengaturan interaktif `SoundSettingsDialog` (`lib/widgets/sound_settings_dialog.dart`).
  - Disediakan channel native Android `com.lingkaraman.lingkar_aman/sound_settings` di `MainActivity.kt` menggunakan `ToneGenerator` & `RingtoneManager` untuk memutar pratinjau suara secara langsung (Play/Stop).
  - Pilihan nada untuk:
    - **Alarm SOS**: Sirine Polisi Keras, Alarm Melodi Darurat, Sirine Klakson Cepat, Beep Alarm Cepat.
    - **Sinyal Keras**: Melodi Derit Keras, Dering Panggilan Cepat, Notifikasi Keras.
    - **Chat Lingkaran**: Ting Halus, Bell Pop Singkat, Dring Pendek, Chime Ding.
  - Pengaturan dapat diakses langsung dari menu Profil Pengguna ("Pengaturan Nada & Ringtone").

### 5. Pusat Fitur: Saklar Nyalakan / Matikan Fitur Langsung
- **Masalah**: Tombol pada Pusat Fitur sebelumnya bertuliskan "Uji Coba Kunci" alih-alih saklar operasional untuk menyalakan/mematikan fitur.
- **Solusi Arsitektural**:
  - Di `FeaturesScreen` (`lib/screens/features_screen.dart`):
    - Mode HP Hilang: Tombol dinamis "Nyalakan Fitur" / "Matikan Fitur" yang dilindungi verifikasi PIN.
    - Kamuflase Layar (Fake Shutdown): Tombol aksi langsung "Aktifkan Kamuflase Layar".
    - Jebakan Penyusup (Intruder Trap): Tombol "Nyalakan Jebakan" / "Matikan Jebakan" serta tombol sekunder "Ganti PIN".
    - Kartu fitur kini mendukung tombol aksi ganda (*primary* dan *secondary button*) secara elegan.

### 6. File yang Dimodifikasi & Ditambahkan
- **Ditambahkan**:
  - `lib/services/sound_settings_service.dart`
  - `lib/widgets/sound_settings_dialog.dart`
  - `lib/widgets/trip_history_sheet.dart`
- **Dimodifikasi**:
  - `android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/MainActivity.kt`
  - `lib/models/models.dart`
  - `lib/services/supabase_service.dart`
  - `lib/screens/circle_screen.dart`
  - `lib/screens/features_screen.dart`
  - `lib/screens/home_screen.dart`
  - `lib/screens/profile_screen.dart`
  - `lib/widgets/member_detail_sheet.dart`

---

## [v0.6.1] - 2026-10-18: Overhaul Tata Letak Responsif Bebas Overflow (Universal Phone Fit)

### 1. Masalah Teknis (Root Cause: Right Overflowed by XX Pixels)
- Di Flutter, widget `Row` secara default memberikan batasan lebar tak terhingga (*unbounded horizontal constraints*).
- Ketika judul, badge status (seperti `'PIN: 1234 | Silent Selfie Aktif'`), atau teks keterangan yang panjang diletakkan berdampingan di dalam `Row` tanpa `Expanded` atau `Wrap`, teks tidak dapat melipat ke bawah secara otomatis.
- Pada ponsel berlayar ramping (lebar 320dp - 360dp) atau saat pengguna menaikkan skala huruf sistem Android (*Display Zoom / Accessibility Large Font*), elemen horizontal menabrak batas layar kanan dan memicu garis kuning-hitam `Right overflowed by xx pixels`.

### 2. Standar Arsitektur Responsif Permanen
1. **Adopsi `Wrap` untuk Judul + Badge/Status**:
   - Komponen judul dan badge di kartu fitur diubah menjadi `Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 4)`.
   - Pada layar lebar, badge tetap sejajar dengan judul. Pada layar sempit atau font besar, badge otomatis turun ke baris berikutnya (*flow layout*) tanpa pernah overflow.
2. **Mandatory `Expanded` / `Flexible` pada Teks di Dalam `Row`**:
   - Seluruh baris judul dan status di dialog maupun kartu dibungkus dengan `Expanded` sehingga teks secara otomatis melipat baris (*word wrap*) mengikuti sisa lebar layar yang ada.
3. **Audit Menyeluruh Antar-Tab**:
   - **`features_screen.dart`**: Judul seksi dan kartu fitur adaptif dengan `Wrap` + `Expanded`.
   - **`circle_screen.dart`**: Banner kode invite diubah menggunakan `Expanded(child: Wrap(...))` sehingga kode dan tombol salin tidak pernah bertabrakan di layar sempit. Judul geofencing dibungkus `Expanded`.
   - **`member_detail_sheet.dart`**: Seluruh baris judul (Sinyal Keras, Mode HP Hilang, Kunci Brankas Data, Izin Penggunaan) dibungkus `Expanded`.
   - **`sos_screen.dart`**: Banner status SOS diubah menjadi `Flexible`, baris tombol power fisik dibungkus `Expanded`, dialog Quick Settings Tile dibungkus `Expanded`.
   - **`lost_mode_screen.dart`**: Judul dialog pembuka PIN dan pesan dari pemilik dibungkus `Expanded`.

### 3. File yang Dimodifikasi
- `lib/screens/features_screen.dart`
- `lib/screens/circle_screen.dart`
- `lib/widgets/member_detail_sheet.dart`
- `lib/screens/sos_screen.dart`
- `lib/screens/lost_mode_screen.dart`

---

## [v0.6.0] - 2026-10-18: Jebakan Penyusup dengan Jepret Kamera Depan Otomatis (Silent Intruder Selfie)

### 1. Masalah & Kebutuhan Pengguna
- Pada versi sebelumnya, fitur "Jebakan Penyusup" hanya menghitung kesalahan PIN di layar Mode HP Hilang dan mengirimkan koordinat GPS serta notifikasi ke keluarga jika salah 3x.
- Pengguna membutuhkan bukti visual konkret berupa foto wajah pelaku pencurian yang tertangkap basah sedang mencoba menebak PIN pada layar kunci.

### 2. Solusi Teknis & Arsitektur
1. **Layanan Kamera Diam-diam (`IntruderCameraService`)**:
   - Mendeteksi ketersediaan sensor kamera depan (`CameraLensDirection.front`).
   - Menginisialisasi `CameraController` tanpa shutter suara (`enableAudio: false`).
   - Mengambil foto secara instan dalam resolusi medium (`ResolutionPreset.medium`).
   - Menyimpan salinan permanen lokal di direktori dokumen aplikasi (`getApplicationDocumentsDirectory`).
   - Mengunggah foto secara otomatis ke Supabase Storage (bucket `intruder_photos` dengan fallback ke `ambient_audio`).
   - Menghasilkan URL publik foto penyusup untuk disematkan pada peringatan darurat.
2. **Pemicu Otomatis pada Kesalahan PIN ke-3 (`PhoneProtectionService`)**:
   - Di `verifyUnlockPin()`: Saat `_failedPinAttempts >= 3`, memanggil `IntruderCameraService().captureIntruderSelfie()` secara asinkron.
   - Mengirimkan `photoUrl` beserta koordinat GPS live dan event `intruder_alert` ke Supabase Realtime broadcast dan tabel `sos_alerts`.
3. **Penyajian Darurat Real-time di Dashboard Keluarga (`HomeScreen`)**:
   - Menangkap stream `onIntruderAlert`.
   - Menampilkan popup dialog darurat `_showIntruderAlertDialog` lengkap dengan tampilan foto wajah pelaku, waktu kejadian, titik koordinat GPS, dan tombol navigasi langsung ke peta lokasi.
4. **Izin Android & Hardware Manifest (`AndroidManifest.xml`)**:
   - Menambahkan izin `android.permission.CAMERA`.
   - Menambahkan deklarasi hardware opsional `android.hardware.camera`, `android.hardware.camera.front`, dan `android.hardware.camera.autofocus`.

### 3. Daftar File yang Dimodifikasi / Dibuat
1. **`lib/services/intruder_camera_service.dart`** *(BARU)*
   - Service singleton pengambil foto kamera depan tanpa suara dan pengunggah ke cloud storage.
2. **`pubspec.yaml`**
   - Menambahkan dependensi resmi `camera: ^0.12.1`.
3. **`android/app/src/main/AndroidManifest.xml`**
   - Menambahkan permission `CAMERA` dan uses-feature camera front.
4. **`lib/services/phone_protection_service.dart`**
   - Menghubungkan trigger salah PIN 3x ke `captureIntruderSelfie` dan meneruskan `photoUrl` ke `reportIntruderAttempt`.
5. **`lib/screens/lost_mode_screen.dart`**
   - Memperbarui pesan error indikator pengambilan foto wajah saat jebakan aktif.
6. **`lib/screens/home_screen.dart`**
   - Menambahkan modal dialog darurat `_showIntruderAlertDialog` untuk menampilkan foto wajah pelaku & koordinat GPS.
7. **`lib/screens/features_screen.dart`**
   - Memperbarui deskripsi kartu fitur "Jebakan Penyusup" dengan status *Silent Selfie Aktif*.

### 4. Prosedur Rollback
Jika terjadi kendala pada integrasi kamera:
1. Hapus file `lib/services/intruder_camera_service.dart`.
2. Kembalikan `lib/services/phone_protection_service.dart` ke pemanggilan `reportIntruderAttempt` tanpa `photoUrl`.
3. Di `pubspec.yaml`, hapus dependensi `camera`.
4. Di `AndroidManifest.xml`, hapus `android.permission.CAMERA`.

---

## [v0.5.0] - 2026-10-18: Anti-Bypass Perlindungan HP Hilang (Lost Mode Persistence & Reboot Survival)

### 1. Masalah & Vektor Serangan (Threat Model)
- **Vektor 1 (Minimize / Clear Memory / Swipe Recent Apps)**:
  Saat Mode HP Hilang aktif, pelaku pencurian sebelumnya masih bisa menekan tombol Home/Recents atau menutup aplikasi dari Recent Apps (*Clear Memory*) sehingga layar kunci hilang dan pelaku bisa mengakses sistem HP.
- **Vektor 2 (Cabut Baterai / Paksa Restart Ponsel)**:
  Jika pelaku mematikan daya, mencabut baterai, atau me-restart HP, aplikasi sebelumnya tidak otomatis mengunci layar di detik pertama sistem boot selesai, dan notifikasi darurat hilang.

### 2. Solusi Arsitektur Multi-Layer (Pertahanan Berlapis)

#### Layer 1: Native Android Foreground Service (`LostModeProtectionService.kt`)
- Menjalankan Foreground Service berkelanjutan dengan `START_STICKY`.
- Menampilkan notifikasi persisten bertingkat darurat:
  - `setOngoing(true)` & `setAutoCancel(false)` (tidak bisa di-swipe atau dihapus oleh pencuri).
  - Prioritas `PRIORITY_MAX` dan kategori `CATEGORY_ALARM`.
  - `setFullScreenIntent()`: Membuka paksa `MainActivity` ke permukaan layar bahkan di atas lockscreen sistem (`VISIBILITY_PUBLIC`).
- **Penanganan `onTaskRemoved`**: Ketika pencuri mencoba "Clear Memory" / menggeser LingkarAman dari Recent Apps, Android secara otomatis memanggil `onTaskRemoved()`. Service mendeteksi jika `flutter.lost_mode_active == true`, lalu menjadwalkan `AlarmManager` (RTC_WAKEUP 300ms) untuk seketika membangkitkan kembali `MainActivity` dan Service.

#### Layer 2: Boot & Hardware Restart Receiver (`BootReceiver.kt`)
- Mendengarkan intent broadcast sistem Android:
  - `android.intent.action.BOOT_COMPLETED`
  - `android.intent.action.LOCKED_BOOT_COMPLETED`
  - `android.intent.action.QUICKBOOT_POWERON`
  - `com.htc.intent.action.QUICKBOOT_POWERON`
  - `android.intent.action.MY_PACKAGE_REPLACED`
- Membaca status persistensi dari `FlutterSharedPreferences`:
  - Jika `flutter.lost_mode_active == true`, seketika mengaktifkan `LostModeProtectionService` dan meluncurkan layar kunci Mode HP Hilang via `AlarmManager` dan `Intent.FLAG_ACTIVITY_NEW_TASK`.
  - Memulihkan juga background monitor tombol power darurat (`SosPowerService`).

#### Layer 3: Anti-Minimize Window Guard (`MainActivity.kt`)
- Mengaktifkan window flag:
  - `setShowWhenLocked(true)` & `setTurnScreenOn(true)` (Android 8.0+ O_MR1).
  - `FLAG_DISMISS_KEYGUARD`, `FLAG_KEEP_SCREEN_ON`.
  - Mengaktifkan `startLockTask()` (Screen Pinning / Kiosk lock) jika didukung perangkat.
- **Recent Apps Exclusion (`setExcludeFromRecents(true)`)**:
  - Saat Mode HP Hilang aktif, aplikasi otomatis disembunyikan dari daftar Recent Apps Android (`ActivityManager.AppTask.setExcludeFromRecents(true)`). Pencuri tidak akan menemukan aplikasi di menu recent apps sehingga tidak bisa di-swipe atau di-kill dari sana.
- Meng-override `onUserLeaveHint()`, `onPause()`, dan `onWindowFocusChanged()`:
  - Jika `isLostModeActive() == true`, setiap upaya beralih jendela/home/recents langsung diintersep dan ditarik kembali seketika (`bringLockToFront()`).

#### Layer 4: Flutter Root Level Enforcement (`main.dart` & `phone_protection_service.dart`)
- `PhoneProtectionService().initialize()` dijalankan sebelum `runApp()`.
- Di `LingkarAmanApp`: Jika `isLostModeActive == true`, aplikasi langsung me-render `LostModeScreen` sebagai `homeWidget` utama (bahkan sebelum login/onboarding selesai dicek).
- Di `LostModeScreen`: Tombol kembali Android dicegah dengan `PopScope(canPop: false)`. Saat PIN pemilik diverifikasi benar, service otomatis menonaktifkan native anti-bypass, mematikan alarm sirine, dan memulihkan navigasi aplikasi ke kondisi normal.

---

### 3. Daftar File yang Dimodifikasi / Dibuat

1. **`android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/LostModeProtectionService.kt`** *(BARU)*
   - Sticky foreground service, unkillable notification, deteksi `onTaskRemoved` + AlarmManager resurrect.
2. **`android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/BootReceiver.kt`** *(BARU)*
   - BroadcastReceiver pemulihan otomatis saat booting/restart/cabut baterai.
3. **`android/app/src/main/AndroidManifest.xml`**
   - Menambahkan permission `RECEIVE_BOOT_COMPLETED`, `USE_FULL_SCREEN_INTENT`, `REORDER_TASKS`, `SYSTEM_ALERT_WINDOW`.
   - Menambahkan atribut `showWhenLocked="true"` dan `turnScreenOn="true"` pada `MainActivity`.
   - Mendaftarkan `LostModeProtectionService` dan `BootReceiver`.
4. **`android/app/src/main/kotlin/com/lingkaraman/lingkar_aman/MainActivity.kt`**
   - Menambahkan MethodChannel `com.lingkaraman.lingkar_aman/lost_mode_protection`.
   - Handler `enableAntiBypass`, `disableAntiBypass`, `isAntiBypassActive`.
   - Override `onUserLeaveHint()` dan `onPause()` untuk mencegah minimize.
5. **`lib/services/phone_protection_service.dart`**
   - Integrasi MethodChannel native untuk aktivasi/deaktivasi anti-bypass.
   - Sinkronisasi state lokal dan native saat inisialisasi & verifikasi PIN.
6. **`lib/main.dart`**
   - Inisialisasi service di `main()`.
   - Root routing dinamis: jika `isLostModeActive` langsung tampilkan `LostModeScreen`.
7. **`lib/screens/lost_mode_screen.dart`**
   - Proteksi navigasi pop aman (`if (nav.canPop()) nav.pop()`).

---

### 4. Prosedur Rollback (Cara Mengembalikan Kode jika Terjadi Masalah)

Jika ingin membatalkan (rollback) pembaruan ini ke versi v0.4:
1. **Hapus File Native Baru**:
   ```powershell
   Remove-Item "android\app\src\main\kotlin\com\lingkaraman\lingkar_aman\LostModeProtectionService.kt"
   Remove-Item "android\app\src\main\kotlin\com\lingkaraman\lingkar_aman\BootReceiver.kt"
   ```
2. **Revert `AndroidManifest.xml`**:
   - Hapus blok tag `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />` dkk.
   - Hapus blok `<service android:name=".LostModeProtectionService" ... />` dan `<receiver android:name=".BootReceiver" ... />`.
   - Hapus atribut `android:showWhenLocked="true"` dan `android:turnScreenOn="true"` dari `MainActivity`.
3. **Revert `MainActivity.kt`**:
   - Hapus channel `LOST_MODE_CHANNEL` dan override `onUserLeaveHint`, `onPause`, `applyLockWindowFlags`, `bringLockToFront`.
4. **Revert `lib/services/phone_protection_service.dart`**:
   - Hapus pemanggilan `enableNativeAntiBypass` dan `disableNativeAntiBypass`.
5. **Revert `lib/main.dart`**:
   - Kembalikan `home:` ke ternary auth tanpa pengecekan `_protectionService.isLostModeActive`.

---

### 5. Catatan Verifikasi Pengujian
- Static Analysis: `flutter analyze lib/` (0 error, 0 warning).
- Automated Unit & Widget Test: `flutter test` lolos 100%.
- Emulator Live Test:
  - Uji Mode HP Hilang aktif -> Minimize diintersep langsung kembali ke layar kunci.
  - Notifikasi darurat persisten tetap siaga di status bar.
  - Verifikasi input PIN membuka kunci dengan mulus.

---

## [v0.6.2] - 2026-10-18: Onboarding Permissions All-in-One & UI Clutter Cleanup

### 1. Masalah & Kebutuhan Pengguna
- **Izin Belum Lengkap di Awal**: Pada instalasi baru, aplikasi sebelumnya mengarahkan pengguna ke layar login terlebih dahulu sebelum meminta izin. Akibatnya, izin Android 13+ seperti `POST_NOTIFICATIONS` dan `CAMERA` (kamera depan untuk foto penyusup) belum aktif secara otomatis jika user belum menyelesaikan onboarding.
- **Tombol Redundan & Simulasi Dev**: Di beberapa tab (khususnya Pusat Fitur dan Lembar Anggota Keluarga), terdapat tombol simulasi pengujian internal ("Simulasi Beacon", "Uji Coba Layar Kunci", "Tes Kamuflase Mati", "Target belum online? Coba Uji Rekam di HP Ini") serta tombol navigasi yang menduplikasi bilah navigasi utama di bagian bawah layar.

### 2. Perubahan yang Diterapkan

#### A. Permintaan Semua Izin di Awal Instalasi (First-Install Onboarding)
- **File**: `lib/main.dart`
  - Memprioritaskan pengecekan `!_onboardingCompleted` sebelum `!_isAuthenticated`.
  - Ponsel yang baru menginstal aplikasi seketika disambut dengan layar izin lengkap sebelum masuk/mendaftar.
- **File**: `lib/screens/onboarding_screen.dart`
  - Menambahkan permintaan izin lengkap 5 pilar keselamatan:
    1. **Lokasi Presisi Latar Belakang** (`locationAlways`) - Melacak koordinat GPS secara akurat dan memicu pagar virtual (*geofence*).
    2. **Notifikasi Penuh** (`Permission.notification` - Android 13+) - Menerima alarm sirine darurat, sinyal SOS keluarga, dan notifikasi persisten Mode Hilang.
    3. **Kamera Depan** (`Permission.camera`) - Menjepret foto wajah penyusup secara diam-diam (*Silent Intruder Selfie*) jika salah memasukkan PIN 3 kali.
    4. **Mikrofon** (`Permission.microphone`) - Merekam suara sekitar saat darurat (*Ambient Audio*).
    5. **Abaikan Penghemat Baterai** (`ignoreBatteryOptimizations`) - Menjaga servis GPS dan koneksi Supabase tetap siaga saat HP terkunci/tidur.
  - Menambahkan tombol **"Izinkan Semua Sekaligus"** yang secara otomatis meminta kelima izin secara berurutan dalam sekali klik.

#### B. Pembersihan Tombol Redundan & Dev Simulators (UI Streamlining)
- **Pusat Fitur (`lib/screens/features_screen.dart`)**:
  - Menghapus tombol navigasi duplikat ("Buka Tab SOS", "Buka Peta", "Buka Lingkaran", "Lihat di Lingkaran").
  - Menghapus tombol simulasi "Simulasi Beacon" pada kartu *Last Breath Beacon*. Kartu kini secara otomatis menampilkan status badge *"Aktif Otomatis ≤ 5%"*.
- **Lembar Anggota Keluarga (`lib/widgets/member_detail_sheet.dart`)**:
  - Saat membuka profil diri sendiri (`isMe == true`):
    - Bagian *Ambient Audio* disembunyikan (karena user tidak perlu memantau mikrofon HP-nya sendiri dari lembar anggota keluarga).
    - Tombol dev test ("Uji Coba Layar Kunci HP Hilang", "Tes Kamuflase Mati", "Ubah PIN Kunci") dihilangkan agar tidak membingungkan pengguna atau menyebabkan terkunci secara tidak sengaja.
    - Menampilkan kartu status keluarga: *"Perangkat Anda siaga dan terhubung. Jika ponsel ini hilang atau dirampas, anggota keluarga lain dalam lingkaran dapat mengunci atau melacaknya dari aplikasi mereka."*
  - Saat membuka profil anggota lain (`isMe == false`):
    - Menghapus tombol fallback dev ("Target belum online? Coba Uji Rekam di HP Ini").
    - Menjaga antarmuka tetap bersih dan intuitif hanya dengan tombol aksi jarak jauh sesungguhnya (*Minta Rekaman Lingkungan*, *Bunyikan Sinyal Keras*, *Aktifkan Mode HP Hilang*, *Kunci Brankas*).

#### C. Pengujian & Verifikasi
- Memperbarui widget test di `test/features_screen_test.dart` untuk menguji dialog interaktif "Ganti PIN".
- Seluruh 36 skenario automated test lulus 100% (`flutter test`).
- Analisis kode bersih tanpa warning di direktori `lib/` (`flutter analyze`).

---

## [v0.7.0] - 2026-10-19: Passwordless Email OTP Authentication & Disposable Temp-Mail Blocker

### 1. Masalah & Kebutuhan Pengguna
- **Risiko Password Konvensional**: Pengguna (terutama anak-anak atau lansia) sering lupa password, atau menggunakan password lemah yang mudah ditebak.
- **Penyalahgunaan Akun Palsu / Temp Mail**: Pendaftaran menggunakan email sekali pakai (*disposable email / temp mail*) membahayakan keamanan lingkaran keluarga dan membuang kuota pengiriman email Supabase.

### 2. Perubahan yang Diterapkan

#### A. Filter Anti-Temp Mail 3 Lapis (`lib/utils/disposable_email_checker.dart`)
- **Lapis 1 - Fast-Path Whitelist**: Memverifikasi secara instan (< 1 µs) domain email terpercaya (Gmail, Yahoo, Outlook, Hotmail, iCloud, Proton, Zoho, AOL, serta domain institusi Indonesia seperti `.ac.id`, `.go.id`, `.sch.id`).
- **Lapis 2 - Blacklist Komprehensif**: Memblokir lebih dari 200+ domain penyedia temp mail populer (`tempmail.com`, `10minutemail.com`, `guerrillamail.com`, `mailinator.com`, `yopmail.com`, `trashmail.com`, `throwawaymail.com`, `fakemailgenerator.com`, `getnada.com`, `maildrop.cc`, `sharklasers.com`, `burnermail.io`, dll).
- **Lapis 3 - Heuristic Pattern Matching**: Mendeteksi pola nama domain yang mencurigakan (mengandung kata kunci `tempmail`, `10minute`, `guerrilla`, `mailinator`, `trashmail`, `disposab`, `fakemail`, `burner`, `mohmal`, dll).
- **Validasi Klien Seketika**: Pemeriksaan dijalankan sebelum request dikirim ke server Supabase, menghemat kuota SMTP dan langsung memberikan feedback penolakan: *"Email sementara (temp mail) dilarang. Harap gunakan email asli seperti Gmail, Yahoo, atau Outlook."*

#### B. Layanan Supabase Email OTP (`lib/services/supabase_service.dart`)
- Menambahkan metode `sendEmailOtp(email, shouldCreateUser, fullName, phoneNumber)`: Mengirimkan 6 digit kode OTP ke inbox email pengguna via `supabase.auth.signInWithOtp()`. Menyimpan nama lengkap dan nomor telepon ke tabel `profiles` secara otomatis.
- Menambahkan metode `verifyEmailOtp(email, token)`: Memverifikasi kode 6 digit via `supabase.auth.verifyOTP(type: OtpType.email)` dan membuka sesi login terautentikasi.

#### C. Antarmuka 2-Tahap Modern (`lib/screens/auth_screen.dart`)
- **Tahap 1 (Kirim OTP)**:
  - Tab pilihan: **Masuk** vs **Daftar Baru**.
  - Form input: Nama Lengkap (untuk pendaftar baru), No. WhatsApp (opsional), dan Alamat Email Pribadi.
  - Tombol aksi: *"Kirim Kode OTP"* dengan icon dan loading indicator.
  - Alternatif: Tetap mempertahankan tombol *"Lanjutkan dengan Google"* sebagai opsi 1-klik cepat.
- **Tahap 2 (Verifikasi OTP)**:
  - Banner email terkirim yang jelas (`Kode 6 digit telah dikirim ke: budi@gmail.com`).
  - Input 6 digit angka dengan tampilan besar, terpusat, dan spasi lega (`letterSpacing: 14`).
  - **Auto-Submit**: Begitu digit ke-6 diketik, verifikasi langsung berjalan otomatis tanpa perlu menekan tombol lagi.
  - **Timer Hitung Mundur 60 Detik**: Mencegah spam kirim ulang, tombol *"Kirim Ulang Kode"* aktif setelah 60 detik.
  - Tombol *"Ganti Email"*: Memungkinkan pengguna kembali ke tahap 1 jika salah mengetik email tanpa perlu restart aplikasi.

#### D. Pengujian & Verifikasi
- Unit test anti-temp mail: `test/disposable_email_checker_test.dart` (3 skenario lolos 100%).
- Widget test alur OTP & blokir temp mail: `test/auth_screen_otp_test.dart` (lolos 100%).
- Full test suite: 40 skenario pengujian lulus (`flutter test`).
- Analisis kode bersih tanpa warning (`flutter analyze`).

---

## [0.7.2] - 2026-10-19
### Deteksi Notifikasi GPS, Indikator Pergerakan Real-time Peta, & Auto-Start Saat HP Dinyalakan Ulang

#### A. Deteksi & Notifikasi GPS Mati / Nonaktif
- **Pemantauan Real-time**: `LocationService` memantau aliran status GPS (`Geolocator.getServiceStatusStream()`).
- **In-App Warning Banner**:
  - Di layar Peta (`MapViewScreen`): Muncul banner peringatan merah elegan di bagian atas ketika GPS dinonaktifkan dengan tombol 1-klik *"Nyalakan"* yang langsung mengarahkan ke pengaturan GPS sistem.
  - Di layar Utama (`HomeScreen`): Menampilkan SnackBar mengambang dengan tombol aksi *"Nyalakan"* saat GPS mati.
- **Notifikasi Status Bar Sistem Android**: Menampilkan notifikasi persisten prioritas tinggi (`⚠️ Layanan Lokasi (GPS) Nonaktif`) yang otomatis hilang begitu pengguna mengaktifkan GPS kembali.

#### B. Indikator Status Pergerakan Real-time di Tab Peta
- **Top Header Status Badge**:
  - Ditampilkan tepat di bawah nama Lingkaran keluarga pada pil tengah atas.
  - Status **AKTIF**: Titik hijau bercahaya (`● REALTIME: AKTIF`).
  - Status **MATI**: Titik abu-abu (`○ REALTIME: MATI`).
- **Tombol Quick-Action Bar Dinamis**:
  - Pil navigasi pergerakan realtime di bagian bawah peta menampilkan label status visual yang jelas (`AKTIF` vs `MATI`).
  - Efek visual hidup dengan border hijau menyala dan latar belakang zamrud gelap saat aktif.
- **Sinkronisasi Pembaruan Posisi Nyata**:
  - Saat aktif: Memulai timer pembaruan posisi anggota setiap 5 detik secara hening (*silent background refresh*) tanpa membuat peta berkedip.
  - Saat mati: Menghentikan timer untuk menghemat pemakaian baterai dan kuota data.

#### C. Auto-Start Otomatis Saat Handphone Dinyalakan Ulang (Boot & Reboot)
- **Direct Boot Aware BroadcastReceiver**: `BootReceiver` diperbarui dengan `android:directBootAware="true"` dan mendukung `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED`, serta `USER_PRESENT`.
- **Eksekusi Multi-Jalur Auto-Start**:
  1. Peluncuran langsung `Intent.FLAG_ACTIVITY_NEW_TASK`.
  2. Penjadwalan `AlarmManager` untuk memprioritaskan aktivitas setelah proses boot selesai.
  3. Pemanggilan `setFullScreenIntent()` pada notifikasi prioritas tinggi sehingga aplikasi dapat langsung terbuka ke layar depan bahkan saat perangkat baru dibuka kuncinya.
- **Pembersihan Otomatis**: Notifikasi pelindung booting otomatis ditutup dan dibersihkan saat `MainActivity` aktif.

---

## [0.7.3] - 2026-10-19
### Kebijakan Retensi Audio Lokal 7 Hari & Pembersihan Mingguan Otomatis

#### A. Penyimpanan Audio Lokal Persisten (`lib/services/audio_service.dart`)
- **Penyimpanan Dokumen Aplikasi**: File rekaman tidak lagi disimpan di cache sementara yang rentan terhapus sistem OS, melainkan di direktori dokumen aplikasi yang aman:
  `app_flutter/ambient_recordings/ambient_<requestId>_<timestamp>.m4a`.
- **Tidak Dihapus Langsung**: File rekaman tetap disimpan di perangkat pengguna setelah proses upload ke Supabase Storage selesai.
- **Pembersihan Otomatis Mingguan (`cleanOldRecordings`)**:
  - File rekaman yang umurnya melebihi 7 hari (`maxAge > 7 days`) akan otomatis dibersihkan secara berkala.
  - Pembersihan otomatis dijalankan setiap kali aplikasi dimulai (`startListeningForRequests`), setelah rekaman baru selesai, serta pada saat pengujian mandiri (*self-test*).
- **Pengujian Unit Retensi**: Menambahkan pengujian `test/audio_service_retention_test.dart` yang memverifikasi bahwa file rekaman baru tetap dipertahankan dan hanya file yang berumur lebih dari 7 hari yang dihapus secara otomatis. Seluruh 41 pengujian sistem lolos 100%.

---

## [0.7.4] - 2026-10-19
### Perbaikan Remote Mode HP Hilang Antar-Anggota (Remote Lost Mode RLS & Multi-Device Sync)

#### A. Akar Masalah (Root Cause Analysis)
1. **Supabase RLS Violation (Error 42501)**:
   - Kebijakan RLS tabel `sos_alerts` diatur ketat: `WITH CHECK (user_id = auth.uid())`.
   - Sebelumnya, fungsi `sendLostModeCommand(targetUserId, ...)` mencoba melakukan `insert` dengan `'user_id': targetUserId` (ID anggota keluarga yang ingin dikunci).
   - Karena request dikirim oleh orang tua / pemilik akun yang berbeda (`auth.uid() != targetUserId`), PostgreSQL Supabase secara otomatis menolak (HTTP 403 Forbidden). Error ini tertelan blok `catch (e)`, sehingga peringatan darurat tidak pernah berhasil masuk ke database.
2. **Pengabaian Alert Masuk di Sisi Perangkat Target**:
   - Di `HomeScreen.dart` listener SOS stream sebelumnya sengaja mengabaikan event jika `alert.userId == _supa.currentUser?.id`. Namun karena format lama mengasumsikan `alert.userId == targetUserId`, perangkat target tidak pernah menangkap sinyal untuk meluncurkan `LostModeScreen`.
3. **Pengecekan Status UI Lembar Anggota (`MemberDetailSheet`)**:
   - Sebelumnya hanya memeriksa status lokal perangkat pemanggil (`_protectionService.isLostModeActive`), yang bernilai `false` di HP orang tua. Akibatnya status aktif tidak tersinkronisasi dan tombol batalkan/buka kunci tidak muncul.

#### B. Solusi & Perubahan Teknis
1. **Kepatuhan RLS & Enkapsulasi Target Command (`PhoneProtectionService`)**:
   - `sendLostModeCommand`: Menggunakan `auth.uid()` pemanggil sebagai `user_id` di `sos_alerts` (100% mematuhi aturan RLS Supabase tanpa melanggar kebijakan keamanan).
   - Data target disematkan ke dalam pesan berstruktur: `[MODE HP HILANG] Target: <targetUserId> | Kontak: <phone> | Sirine: <Aktif/Mati> | Pesan: <customMessage>`.
   - Fungsi parser `LostModeCommand.parseFromSosMessage()` mengekstrak parameter target, nomor darurat, status sirine, dan pesan khusus secara deterministik.
2. **Sinkronisasi Realtime & Respon Otomatis di HP Target (`HomeScreen`)**:
   - Listener `subscribeToSosAlerts()` di `HomeScreen` mendengarkan pesan `[MODE HP HILANG]`.
   - Jika `command.targetUserId == myUid`:
     - **Status 'active'**: Langsung mengaktifkan `applyRemoteLostMode(command)`, membunyikan sirine (jika dipilih), mengaktifkan native anti-bypass, dan membuka layar penuh `LostModeScreen`.
     - **Status 'resolved'**: Menonaktifkan Mode HP Hilang, mematikan sirine, melepas native anti-bypass, dan menutup `LostModeScreen`.
3. **Pemeriksaan Status Aktif Saat Booting / Startup (`checkAndApplyRemoteLostMode`)**:
   - Saat aplikasi di perangkat target dinyalakan atau restart setelah sempat offline, `HomeScreen._initialize()` langsung memeriksa ke Supabase apakah ada alert `[MODE HP HILANG]` aktif untuk `myUid`. Jika ada, ponsel seketika mengunci dirinya sendiri.
4. **Pembaruan Status UI Dinamis pada Lembar Anggota (`MemberDetailSheet`)**:
   - Memanggil `isLostModeActiveForUser(member.userId)` saat lembar dibuka.
   - Menampilkan status *"KUNCI AKTIF"* dan tombol *"Nonaktifkan Mode Hilang"* secara akurat di perangkat orang tua/anggota.



