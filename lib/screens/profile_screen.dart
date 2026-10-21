import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/battery_optimization_service.dart';
import '../services/oem_security_service.dart';
import '../services/location_service.dart';
import '../services/phone_protection_service.dart';
import '../services/sos_trigger_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sound_settings_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onSignedOut;
  const ProfileScreen({super.key, required this.onSignedOut});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  final SupabaseService _supa = SupabaseService();
  final LocationService _locService = LocationService();
  final PhoneProtectionService _phoneProtectionService = PhoneProtectionService();
  final SosTriggerService _sosTriggerService = SosTriggerService();
  final BatteryOptimizationService _batteryService = BatteryOptimizationService();
  final OemSecurityService _oemSecurityService = OemSecurityService();

  OemDeviceInfo _deviceInfo = const OemDeviceInfo(
    manufacturer: 'android',
    brandDisplayName: 'Android Device',
    isKnownVendor: false,
  );
  bool _isAccessibilityEnabled = false;

  UserProfile? _profile;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isUploadingAvatar = false;
  bool _isLocationSharing = true;
  bool _isBatteryOptimizedIgnored = false;

  // Keamanan & Anti-Maling state
  String _currentPin = '1234';
  bool _isPowerButtonEnabled = true;
  int _powerButtonCount = 3;
  bool _isIntruderTrapEnabled = true;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    _loadSecuritySettings();
    _checkBatteryOptimization();
    _loadOemSecurityStatus();
    _isLocationSharing = _locService.isTracking;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimization();
      _loadOemSecurityStatus();
    }
  }


  Future<void> _loadOemSecurityStatus() async {
    try {
      final info = await _oemSecurityService.getDeviceInfo();
      final accessEnabled = await _oemSecurityService.isAccessibilityServiceEnabled();
      if (mounted) {
        setState(() {
          _deviceInfo = info;
          _isAccessibilityEnabled = accessEnabled;
        });
      }
    } catch (_) {}
  }

  void _showOemAutostartDialog() {
    final brand = _deviceInfo.brandDisplayName;
    final m = _deviceInfo.manufacturer.toLowerCase();

    List<String> tips = [];
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      tips = [
        'Aktifkan opsi "Mulai Otomatis" (Autostart) untuk LingkarAman.',
        'Di Penghemat Baterai, pilih "Tidak Ada Pembatasan" (No Restrictions).',
        'Buka Recent Apps, tahan kartu aplikasi LingkarAman, lalu ketuk ikon gembok agar tidak terhapus saat bersihkan RAM.',
      ];
    } else if (m.contains('samsung')) {
      tips = [
        'Buka Pengaturan > Perawatan Perangkat > Baterai.',
        'Pilih "Batas Penggunaan Latar Belakang" > "Aplikasi yang tidak pernah tidur".',
        'Tambahkan LingkarAman ke dalam daftar.',
      ];
    } else if (m.contains('oppo') || m.contains('realme')) {
      tips = [
        'Buka Info Aplikasi LingkarAman > Penggunaan Baterai.',
        'Aktifkan "Izinkan Aktivitas Latar Belakang" dan "Izinkan Mulai Otomatis".',
        'Kunci aplikasi di menu Recent Apps.',
      ];
    } else if (m.contains('vivo') || m.contains('iqoo')) {
      tips = [
        'Buka iManager > Manajemen Izin > Kelola Mulai Otomatis.',
        'Aktifkan LingkarAman.',
        'Buka Konsumsi Daya Latar Belakang dan izinkan LingkarAman berjalan bebas.',
      ];
    } else if (m.contains('transsion') || m.contains('infinix') || m.contains('tecno')) {
      tips = [
        'Buka Phone Master > Manajemen Auto-Start.',
        'Izinkan LingkarAman berjalan otomatis saat booting.',
      ];
    } else {
      tips = [
        'Pastikan pengoptimalan baterai dimatikan untuk LingkarAman.',
        'Izinkan aplikasi berjalan di latar belakang tanpa batas.',
        'Kunci aplikasi di layar Recent Apps jika ponsel memiliki fitur pembersih RAM agresif.',
      ];
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings_suggest, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Panduan Autostart $brand',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agar pelacakan anti-maling dan sinyal darurat tetap aktif 24/7 di sistem $brand, lakukan langkah berikut:',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            ...tips.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2, right: 8),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.indigo,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(entry.value, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Buka Pengaturan HP'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _oemSecurityService.openAutostartSettings();
            },
          ),
        ],
      ),
    );
  }

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.phonelink_lock, color: Colors.deepOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Proteksi Matikan Daya',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fitur ini mencegah pencuri mematikan HP dengan menahan tombol power saat ponsel dalam status Mode Hilang atau Fake Shutdown.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            SizedBox(height: 12),
            Text(
              'Langkah aktivasi:\n1. Ketuk "Buka Aksesibilitas" di bawah.\n2. Cari dan pilih layanan "Proteksi Anti-Matikan Daya (LingkarAman)".\n3. Aktifkan sakelar izin tersebut.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.accessibility_new, size: 18),
            label: const Text('Buka Aksesibilitas'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _oemSecurityService.openAccessibilitySettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _checkBatteryOptimization() async {
    final isIgnored = await _batteryService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() => _isBatteryOptimizedIgnored = isIgnored);
    }
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final pin = await _phoneProtectionService.getOwnerPin();
      final pwrEnabled = await _sosTriggerService.isPowerButtonEnabled();
      final pwrCount = await _sosTriggerService.getPowerButtonCount();
      final prefs = await SharedPreferences.getInstance();
      final trap = prefs.getBool('intruder_trap_enabled') ?? true;
      if (mounted) {
        setState(() {
          _currentPin = pin;
          _isPowerButtonEnabled = pwrEnabled;
          _powerButtonCount = pwrCount;
          _isIntruderTrapEnabled = trap;
        });
      }
    } catch (_) {}
  }

  Future<void> _changeOwnerPinDialog() async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah PIN Keamanan Pemilik'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PIN ini digunakan untuk membuka layar ponsel saat Mode HP Hilang aktif.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'PIN Baru (4-6 Angka)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin),
                ),
                validator: (val) {
                  if (val == null || val.length < 4) {
                    return 'Minimal 4 angka';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(ctrl.text.trim());
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newPin != null && newPin.isNotEmpty) {
      await _phoneProtectionService.setOwnerPin(newPin);
      if (mounted) {
        setState(() => _currentPin = newPin);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ PIN Pemilik berhasil diperbarui!')),
        );
      }
    }
  }

  void _showPowerButtonSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.power_settings_new, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Pemicu Darurat Tombol Power', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tekan tombol daya (Power) secara cepat beberapa kali untuk memicu Alarm SOS otomatis meskipun ponsel di dalam saku.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Aktifkan Pemicu Tombol Daya', style: TextStyle(fontWeight: FontWeight.bold)),
                value: _isPowerButtonEnabled,
                onChanged: (val) async {
                  setModalState(() => _isPowerButtonEnabled = val);
                  setState(() => _isPowerButtonEnabled = val);
                  await _sosTriggerService.setPowerButtonSettings(
                    enabled: val,
                    count: _powerButtonCount,
                  );
                },
              ),
              const Divider(),
              const Text('Jumlah Tekanan Cepat:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [3, 4, 5].map((cnt) {
                  final isSelected = _powerButtonCount == cnt;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isSelected ? Colors.red.shade50 : null,
                          side: BorderSide(color: isSelected ? Colors.red : Colors.grey.shade300, width: isSelected ? 2 : 1),
                        ),
                        child: Text('$cnt Kali', style: TextStyle(color: isSelected ? Colors.red : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        onPressed: () async {
                          setModalState(() => _powerButtonCount = cnt);
                          setState(() => _powerButtonCount = cnt);
                          await _sosTriggerService.setPowerButtonSettings(
                            enabled: _isPowerButtonEnabled,
                            count: cnt,
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleIntruderTrap() async {
    final prefs = await SharedPreferences.getInstance();
    final newState = !_isIntruderTrapEnabled;
    await prefs.setBool('intruder_trap_enabled', newState);
    setState(() => _isIntruderTrapEnabled = newState);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newState ? 'Jebakan Penyusup (Silent Selfie) DINYALAKAN!' : 'Jebakan Penyusup DINONAKTIFKAN.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emergencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final prof = await _supa.getProfile();
    if (mounted) {
      setState(() {
        _profile = prof;
        _nameCtrl.text = prof?.fullName ?? '';
        _phoneCtrl.text = prof?.phoneNumber ?? '';
        _emergencyCtrl.text = prof?.emergencyContactPhone ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      await _supa.updateProfile(
        fullName: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        emergencyContactPhone: _emergencyCtrl.text.trim(),
      );
      await _loadProfile();
      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan profil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAvatarPickerSheet() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Foto Profil',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.camera_alt, color: Colors.blueAccent),
                ),
                title: const Text('Ambil Foto dari Kamera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF0FDF4),
                  child: Icon(Icons.photo_library, color: Colors.green),
                ),
                title: const Text('Pilih dari Galeri HP'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
              if (_profile?.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEF2F2),
                    child: Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  title: const Text('Hapus Foto Profil', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeAvatar();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingAvatar = true);

      final file = File(picked.path);
      await _supa.uploadAvatar(file);
      await _loadProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profil berhasil diperbarui!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui foto profil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    try {
      setState(() => _isUploadingAvatar = true);
      await _supa.updateProfile(clearAvatar: true);
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profil dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar Akun'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _locService.stopTracking();
      await _supa.signOut();
      widget.onSignedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supa.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
          : SingleChildScrollView(
              child: Column(
                children: [
                  // 1. HEADER NAVY MELENGKUNG (Sesuai Referensi Layar 4)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 48, bottom: 32, left: 24, right: 24),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryNavy,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Avatar Besar dengan Border Putih
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: _showAvatarPickerSheet,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 44,
                                  backgroundColor: const Color(0xFF2563EB),
                                  backgroundImage: (_profile?.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty)
                                      ? NetworkImage(_profile!.avatarUrl!)
                                      : null,
                                  child: _isUploadingAvatar
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : (_profile?.avatarUrl == null || _profile!.avatarUrl!.isEmpty)
                                          ? Text(
                                              (_profile?.fullName.isNotEmpty == true)
                                                  ? _profile!.fullName[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                fontSize: 34,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _showAvatarPickerSheet,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    size: 15,
                                    color: AppColors.primaryNavy,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _profile?.fullName ?? 'Budi Santoso',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? 'budi@email.com',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),

                        // 2. TOGGLE CARD: BERBAGI LOKASI REALTIME (Layar 4)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.location_on, color: AppColors.primaryNavy, size: 22),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Berbagi Lokasi Realtime',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _isLocationSharing,
                                activeColor: const Color(0xFF16A34A),
                                activeTrackColor: const Color(0xFFDCFCE7),
                                onChanged: (val) {
                                  setState(() => _isLocationSharing = val);
                                  if (val) {
                                    _locService.startTracking();
                                  } else {
                                    _locService.stopTracking();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 3. GRID MENU FITUR (2 KOLOM, KARTU PUTIH, IKON NAVY)
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.45,
                          children: [
                            // 1. Mode HP Hilang
                            _buildFeatureCard(
                              icon: Icons.phonelink_lock_rounded,
                              label: 'Mode HP Hilang',
                              onTap: _showLostModeFeatureDialog,
                            ),
                            // 2. Sinyal Keras
                            _buildFeatureCard(
                              icon: Icons.signal_cellular_alt_rounded,
                              label: 'Sinyal Keras',
                              onTap: _showLoudSignalFeatureDialog,
                            ),
                            // 3. Jebakan Penyusup
                            _buildFeatureCard(
                              icon: Icons.shield_outlined,
                              label: 'Jebakan Penyusup',
                              onTap: () => _toggleIntruderTrap(),
                            ),
                            // 4. Riwayat Perjalanan
                            _buildFeatureCard(
                              icon: Icons.speed_rounded,
                              label: 'Riwayat Perjalanan',
                              onTap: _showTripHistoryFeatureDialog,
                            ),
                            // 5. Zona Aman
                            _buildFeatureCard(
                              icon: Icons.home_rounded,
                              label: 'Zona Aman',
                              onTap: _showGeofenceFeatureDialog,
                            ),
                            // 6. Rekam Suara Darurat
                            _buildFeatureCard(
                              icon: Icons.mic_rounded,
                              label: 'Rekam Suara Darurat',
                              onTap: _showAudioRecordFeatureDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 4. CARD HORIZONTAL: PENGATURAN NADA & RINGTONE
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.music_note_rounded, color: AppColors.primaryNavy, size: 20),
                            ),
                            title: const Text(
                              'Pengaturan Nada & Ringtone',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                            onTap: () => SoundSettingsDialog.show(context),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 5. INFORMASI KONTAK & AKUN
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Informasi Kontak',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        if (_isEditing) {
                                          _saveProfile();
                                        } else {
                                          setState(() => _isEditing = true);
                                        }
                                      },
                                      child: Text(
                                        _isEditing ? 'Simpan' : 'Edit',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              if (_isEditing) ...[
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      TextField(
                                        controller: _nameCtrl,
                                        decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _phoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(labelText: 'Nomor WhatsApp / HP'),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _emergencyCtrl,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(
                                          labelText: 'Kontak Darurat',
                                          helperText: 'Nomor dipanggil saat tombol SOS ditekan',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                ListTile(
                                  leading: const Icon(Icons.phone_outlined, color: AppColors.textSecondary, size: 20),
                                  title: const Text('Nomor HP', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  subtitle: Text(_profile?.phoneNumber ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.contact_phone_outlined, color: AppColors.statusEmergency, size: 20),
                                  title: const Text('Kontak Darurat Prioritas', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  subtitle: Text(
                                    _profile?.emergencyContactPhone ?? 'Belum diatur',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.statusEmergency),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Tombol Keluar dari Akun
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.statusEmergency,
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              backgroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('Keluar dari Akun', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _signOut,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.primaryNavy, size: 28),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLostModeFeatureDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.phonelink_lock_rounded, color: AppColors.primaryNavy),
            SizedBox(width: 8),
            Text('Mode HP Hilang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mode HP Hilang mengunci layar ponsel jarak jauh dengan PIN keamanan dan menampilkan nomor kontak pemilik.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'PIN Keamanan Anda: ${_currentPin.replaceAll(RegExp(r'.'), '•')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _changeOwnerPinDialog();
            },
            child: const Text('Ubah PIN'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showLoudSignalFeatureDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.signal_cellular_alt_rounded, color: AppColors.primaryNavy),
            SizedBox(width: 8),
            Text('Sinyal Keras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Fitur Sinyal Keras membunyikan alarm volume maksimal di HP anggota keluarga meskipun sedang dalam mode diam/silent. Fitur ini dapat dipicu melalui Detail Anggota pada layar Peta.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  void _showTripHistoryFeatureDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.speed_rounded, color: AppColors.primaryNavy),
            SizedBox(width: 8),
            Text('Riwayat Perjalanan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Riwayat perjalanan merekam pergerakan rute harian secara otomatis dan dapat dilihat melalui profil anggota keluarga di Peta.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showGeofenceFeatureDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.home_rounded, color: AppColors.primaryNavy),
            SizedBox(width: 8),
            Text('Zona Aman (Geofence)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Zona Aman memberi peringatan otomatis saat anggota keluarga tiba atau keluar dari tempat seperti Rumah atau Sekolah. Anda dapat mengelolanya di tab Lingkaran.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showAudioRecordFeatureDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.mic_rounded, color: AppColors.primaryNavy),
            SizedBox(width: 8),
            Text('Rekam Suara Darurat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Fitur Rekam Suara Darurat memungkinkan Anda mendengarkan rekaman audio sekitar 15 detik dari perangkat anggota yang membutuhkan bantuan saat mode darurat.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }
}
