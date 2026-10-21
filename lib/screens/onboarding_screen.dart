import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingkar_aman/services/oem_security_service.dart';
import '../theme/app_theme.dart';

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
  bool _overlayGranted = false;
  bool _batteryExemptGranted = false;
  bool _accessibilityGranted = false;
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
    final overlay = await Permission.systemAlertWindow.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final access = await OemSecurityService.instance.isAccessibilityServiceEnabled();

    if (mounted) {
      setState(() {
        _locAlwaysGranted = locAlways || locWhenInUse;
        _notifGranted = notif;
        _cameraGranted = cam;
        _micGranted = mic;
        _overlayGranted = overlay;
        _batteryExemptGranted = battery;
        _accessibilityGranted = access;
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

  Future<void> _requestOverlayPermission() async {
    final status = await Permission.systemAlertWindow.request();
    if (!status.isGranted) {
      await openAppSettings();
    }
    await _checkPermissions();
  }

  Future<void> _requestAllPermissions() async {
    if (!_locAlwaysGranted) await _requestLocationPermission();
    if (!_notifGranted) await _requestNotificationPermission();
    if (!_cameraGranted) await _requestCameraPermission();
    if (!_micGranted) await _requestMicPermission();
    if (!_overlayGranted) await _requestOverlayPermission();
    await _checkPermissions();
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    // Izin utama yang direkomendasikan
    final canProceed = _locAlwaysGranted || _notifGranted;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: _isChecking
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          // Ilustrasi Perisai Biru dengan Siluet Keluarga (Layar 6 Referensi)
                          _buildShieldIllustration(),
                          const SizedBox(height: 20),

                          const Text(
                            'Persetujuan Keselamatan',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Agar keluarga Anda terlindungi,\nizinkan akses berikut',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 1. Lokasi Sepanjang Waktu
                          _buildPermissionCard(
                            icon: Icons.location_on_rounded,
                            title: 'Lokasi Sepanjang Waktu',
                            subtitle: 'Agar lokasi selalu terpantau',
                            isGranted: _locAlwaysGranted,
                            onTap: _requestLocationPermission,
                          ),
                          const SizedBox(height: 12),

                          // 2. Notifikasi
                          _buildPermissionCard(
                            icon: Icons.notifications_rounded,
                            title: 'Notifikasi',
                            subtitle: 'Dapatkan peringatan penting',
                            isGranted: _notifGranted,
                            onTap: _requestNotificationPermission,
                          ),
                          const SizedBox(height: 12),

                          // 3. Kamera Depan
                          _buildPermissionCard(
                            icon: Icons.camera_alt_rounded,
                            title: 'Kamera Depan',
                            subtitle: 'Untuk verifikasi keamanan',
                            isGranted: _cameraGranted,
                            onTap: _requestCameraPermission,
                          ),
                          const SizedBox(height: 12),

                          // 4. Mikrofon
                          _buildPermissionCard(
                            icon: Icons.mic_rounded,
                            title: 'Mikrofon',
                            subtitle: 'Untuk keadaan darurat',
                            isGranted: _micGranted,
                            onTap: _requestMicPermission,
                          ),
                          const SizedBox(height: 12),

                          // 5. Tampil di Atas Layar Kunci
                          _buildPermissionCard(
                            icon: Icons.phonelink_lock_rounded,
                            title: 'Tampil di Atas Layar Kunci',
                            subtitle: 'Akses saat layar terkunci',
                            isGranted: _overlayGranted,
                            onTap: _requestOverlayPermission,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Fixed Bottom Button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final allGranted = _locAlwaysGranted &&
                                  _notifGranted &&
                                  _cameraGranted &&
                                  _micGranted &&
                                  _overlayGranted;
                              if (!allGranted) {
                                await _requestAllPermissions();
                              } else {
                                await _finishOnboarding();
                              }
                            },
                            child: Text(
                              (_locAlwaysGranted && _notifGranted && _cameraGranted && _micGranted && _overlayGranted)
                                  ? 'Lanjutkan ke Aplikasi'
                                  : 'Izinkan Semua Sekaligus',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (canProceed && !(_locAlwaysGranted && _notifGranted && _cameraGranted && _micGranted && _overlayGranted)) ...[
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _finishOnboarding,
                            child: const Text(
                              'Lewati & Lanjutkan',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildShieldIllustration() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primaryNavy,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(36),
              bottomRight: Radius.circular(36),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryNavy.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.family_restroom_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted ? AppColors.statusSuccess.withOpacity(0.3) : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isGranted ? const Color(0xFFDCFCE7) : AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isGranted ? AppColors.statusSuccess : AppColors.primaryNavy,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGranted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check, size: 14, color: AppColors.statusSuccess),
                  SizedBox(width: 4),
                  Text(
                    'Aktif',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.statusSuccess,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 36,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: onTap,
                child: const Text(
                  'Izinkan',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
