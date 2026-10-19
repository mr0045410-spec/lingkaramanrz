# LingkarAman (Family Safety & Anti-Theft)

Aplikasi perlindungan keluarga dan anti-maling realtime berbasis Flutter & Supabase.

## Fitur Utama

- **Peta Realtime & Pelacakan GPS**: Memantau posisi anggota keluarga secara live di OpenStreetMap beserta status baterai dan charging.
- **Hierarki Lingkaran & Kode Undangan**: Manajemen lingkaran dengan peran tegas antara Admin Utama (pemilik lingkaran) dan Anggota biasa.
- **Obrolan Lingkaran & Notifikasi**: Obrolan grup realtime dengan notifikasi status bar, suara, dan getaran.
- **Pusat Fitur Anti-Theft**:
  - **Mode HP Hilang (Lost Mode)**: Kunci layar penuh anti-bypass, sirine darurat, tombol kontak darurat, dilindungi PIN.
  - **Kamuflase Pura-pura Mati (Fake Shutdown)**: Layar hitam pekat stealth OLED, GPS tetap aktif mengirim lokasi, buka kunci dengan 3x ketuk layar + PIN.
  - **Jebakan Penyusup (Intruder Trap)**: Salah PIN 3x memicu jepretan diam-diam kamera depan dan menyiarkan foto serta titik koordinat GPS ke keluarga.
  - **Last Breath Beacon**: Otomatis menyiarkan koordinat GPS darurat terakhir saat baterai ≤ 5% sebelum ponsel mati total.
  - **Kunci Brankas Darurat (Remote Wipe)**: Menghapus token sesi, cache lokasi, dan data lokal privat jika HP hilang.
- **Respon Cepat & Keselamatan**:
  - **Tombol Darurat SOS**: Tekan & tahan 3 detik untuk menyiarkan peringatan darurat ke seluruh keluarga.
  - **Sinyal Keras Darurat**: Membunyikan ponsel target dengan volume maksimal bahkan saat mode hening atau Jangan Ganggu (DND).
  - **Sadap Suara Lingkungan (Ambient Audio)**: Merekam suara sekitar 15 detik dari jarak jauh secara diam-diam dan mengunggah ke cloud storage.
  - **Tombol Power SOS**: Deteksi tekan cepat tombol power fisik 3x/4x/5x.
  - **Quick Settings Tile SOS**: Tombol pintas darurat langsung dari panel notifikasi atas Android.
- **Pantauan Keluarga & Anak**:
  - **Geofencing Otomatis**: Radius zona aman (Rumah, Sekolah) dengan log notifikasi masuk/keluar zona.
  - **Waktu Layar (Screen Time)**: Statistik penggunaan aplikasi dan durasi aktif ponsel anak.
  - **Riwayat Perjalanan Linimasa**: Linimasa pergerakan kronologis, kecepatan km/jam, dan titik berhenti.

## Arsitektur & Teknologi

- **Framework**: Flutter 3 (Dart)
- **Backend**: Supabase (PostgreSQL, Realtime WebSockets, Storage, Row Level Security)
- **Native Android**: Kotlin (Foreground Services, BootReceiver, Audio/Tone Generator, Camera Controller, UsageStatsManager)
- **Map Engine**: `flutter_map` dengan OpenStreetMap Tiles

## Konfigurasi & Persiapan

1. **Jalankan Database**:
   Eksekusi script SQL pada file `migration_full.sql` di Supabase SQL Editor.
2. **Setup Dependency**:
   ```bash
   flutter pub get
   ```
3. **Menjalankan Pengujian**:
   ```bash
   flutter test
   ```
4. **Build APK Debug**:
   ```bash
   flutter build apk --debug
   ```

## Dokumentasi Tambahan

- [DATABASE_LIBRARY.md](DATABASE_LIBRARY.md): Dokumentasi skema lengkap, ERD, dan kamus data Supabase.
- [UPDATE_LOG.md](UPDATE_LOG.md): Riwayat changelog versi, detail teknis, dan perbaikan bug.
