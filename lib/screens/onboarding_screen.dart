import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  bool _locAlwaysGranted = false;
  bool _notifGranted = false;
  bool _cameraGranted = false;
  bool _micGranted = false;
  bool _batteryExemptGranted = false;
  bool _overlayGranted = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final locWhenInUse = await Permission.locationWhenInUse.isGranted;
    final locAlways = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final cam = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlay = await Permission.systemAlertWindow.isGranted;

    if (mounted) {
      setState(() {
        _locAlwaysGranted = locAlways || locWhenInUse;
        _notifGranted = notif;
        _cameraGranted = cam;
        _micGranted = mic;
        _batteryExemptGranted = battery;
        _overlayGranted = overlay;
        _isChecking = false;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      status = await Permission.locationAlways.request();
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestBatteryPermission() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestOverlayPermission() async {
    final status = await Permission.systemAlertWindow.request();
    if (!status.isGranted) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestAllPermissions() async {
    await _requestLocationPermission();
    await _requestNotificationPermission();
    await _requestCameraPermission();
    await _requestMicPermission();
    await _requestBatteryPermission();
    await _requestOverlayPermission();
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _locAlwaysGranted &&
        _notifGranted &&
        _cameraGranted &&
        _micGranted &&
        _batteryExemptGranted &&
        _overlayGranted;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Izin Perlindungan LingkarAman', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Illustration Banner
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.shield_outlined, size: 48, color: Colors.white),
                          const SizedBox(height: 10),
                          const Text(
                            'Persetujuan Keselamatan',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Agar keluarga dapat terlindungi dan dipantau saat darurat bahkan saat HP terkunci atau layar mati, izinkan hak akses di bawah ini.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Permission Card 1: Location Always
                    _buildPermissionCard(
                      icon: Icons.location_on,
                      iconColor: Colors.blue.shade700,
                      title: 'Lokasi Sepanjang Waktu',
                      subtitle:
                          'Wajib "Izinkan Sepanjang Waktu" agar keluarga dapat memantau posisi live dan zona aman (geofence).',
                      isGranted: _locAlwaysGranted,
                      onTap: _requestLocationPermission,
                    ),

                    const SizedBox(height: 12),

                    // Permission Card 2: Notifications
                    _buildPermissionCard(
                      icon: Icons.notifications_active,
                      iconColor: Colors.red.shade700,
                      title: 'Notifikasi Darurat & Sinyal Keras',
                      subtitle:
                          'Menerima alarm bahaya seketika, notifikasi SOS anggota keluarga, dan peringatan HP hilang.',
                      isGranted: _notifGranted,
                      onTap: _requestNotificationPermission,
                    ),

                    const SizedBox(height: 12),

                    // Permission Card 3: Camera
                    _buildPermissionCard(
                      icon: Icons.camera_front,
                      iconColor: Colors.deepOrange,
                      title: 'Kamera Depan (Jebakan Penyusup)',
                      subtitle:
                          'Mengambil foto selfie penyusup secara diam-diam jika ada 3x percobaan salah PIN pada HP yang hilang.',
                      isGranted: _cameraGranted,
                      onTap: _requestCameraPermission,
                    ),

                    const SizedBox(height: 12),

                    // Permission Card 4: Microphone
                    _buildPermissionCard(
                      icon: Icons.mic_none,
                      iconColor: Colors.purple.shade700,
                      title: 'Mikrofon & Audio Sekitar',
                      subtitle:
                          'Merekam audio 15 detik secara aman saat ada permintaan darurat dari anggota lingkaran.',
                      isGranted: _micGranted,
                      onTap: _requestMicPermission,
                    ),

                    const SizedBox(height: 12),

                    // Permission Card 5: Battery Optimization Exemption
                    _buildPermissionCard(
                      icon: Icons.battery_saver,
                      iconColor: Colors.green.shade700,
                      title: 'Aplikasi Berjalan di Latar Belakang',
                      subtitle:
                          'Mencegah sistem Android mematikan pelacakan GPS dan perlindungan anti-maling saat layar padam.',
                      isGranted: _batteryExemptGranted,
                      onTap: _requestBatteryPermission,
                    ),

                    const SizedBox(height: 12),

                    // Permission Card 6: Overlay on Lock Screen & Apps
                    _buildPermissionCard(
                      icon: Icons.layers_outlined,
                      iconColor: Colors.indigo.shade700,
                      title: 'Tampil di Atas Layar Kunci & Aplikasi',
                      subtitle:
                          'Wajib agar layar kunci darurat & perlindungan anti-maling langsung tampil di atas layar saat HP hilang atau dicuri.',
                      isGranted: _overlayGranted,
                      onTap: _requestOverlayPermission,
                    ),

                    const SizedBox(height: 24),

                    // Request All Button
                    if (!allGranted)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Izinkan Semua Sekaligus',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _requestAllPermissions,
                      ),

                    const SizedBox(height: 12),

                    // Continue / Finish Button
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: allGranted ? const Color(0xFF1E3A8A) : Colors.grey.shade400,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _finishOnboarding,
                      child: Text(
                        allGranted ? 'Lanjutkan ke Aplikasi' : 'Lewati & Masuk Aplikasi',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: allGranted ? const Color(0xFF1E3A8A) : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted ? Colors.green.shade300 : Colors.grey.shade200,
          width: isGranted ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (isGranted)
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: isGranted
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check, color: Colors.green, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Izin Sudah Aktif',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: onTap,
                          child: const Text('Beri Izin', style: TextStyle(fontSize: 12)),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
