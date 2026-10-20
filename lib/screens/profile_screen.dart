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
      appBar: AppBar(
        title: const Text('Profil & Pengaturan'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit Profil',
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProfile,
              tooltip: 'Simpan',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // User Avatar with Camera / Edit Badge
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _showAvatarPickerSheet,
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.indigo.shade100,
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
                                        style: TextStyle(fontSize: 38, color: Colors.indigo.shade900, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showAvatarPickerSheet,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade700,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile?.fullName ?? 'Pengguna',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Profile Form / Details
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Informasi Kontak',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 16),
                          if (_isEditing) ...[
                            TextField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nama Lengkap',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Nomor WhatsApp / HP',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _emergencyCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Nomor Kontak Darurat (Keluarga)',
                                prefixIcon: Icon(Icons.contact_phone_outlined),
                                helperText: 'Nomor yang dipanggil cepat saat tombol SOS ditekan',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ] else ...[
                            ListTile(
                              leading: const Icon(Icons.person_outline, color: Colors.indigo),
                              title: const Text('Nama Lengkap', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(_profile?.fullName ?? '-', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                            ListTile(
                              leading: const Icon(Icons.phone_outlined, color: Colors.indigo),
                              title: const Text('Nomor WhatsApp / HP', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(_profile?.phoneNumber ?? '-', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                            ListTile(
                              leading: const Icon(Icons.contact_phone_outlined, color: Colors.red),
                              title: const Text('Kontak Darurat Prioritas', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(
                                _profile?.emergencyContactPhone ?? 'Belum diatur',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location Tracking Toggle Card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: SwitchListTile(
                      secondary: const Icon(Icons.my_location, color: Colors.indigo),
                      title: const Text('Berbagi Lokasi Realtime', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Kirim koordinat GPS dan level baterai ke lingkaran'),
                      value: _isLocationSharing,
                      onChanged: (val) {
                        setState(() => _isLocationSharing = val);
                        if (val) {
                          _locService.startTracking();
                        } else {
                          _locService.stopTracking();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Proteksi Latar Belakang & Anti-Kill OS Card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Icon(
                              _isBatteryOptimizedIgnored ? Icons.battery_charging_full : Icons.battery_alert,
                              color: _isBatteryOptimizedIgnored ? Colors.teal : Colors.deepOrange,
                              size: 28,
                            ),
                            title: const Text('Proteksi Latar Belakang (Anti-Kill OS)', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              _isBatteryOptimizedIgnored
                                  ? 'Aplikasi diizinkan berjalan bebas di latar belakang saat HP di saku'
                                  : 'Ketuk untuk mengabaikan optimasi baterai agar pelacakan tidak dimatikan Android',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: _isBatteryOptimizedIgnored
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.shade300),
                                    ),
                                    child: const Text('Aktif', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.indigo,
                                      foregroundColor: Colors.white,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    onPressed: () async {
                                      await _batteryService.requestIgnoreBatteryOptimizations();
                                    },
                                    child: const Text('Izinkan'),
                                  ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: const Icon(Icons.settings_suggest, color: Colors.indigo, size: 28),
                            title: Text('Panduan Autostart (${_deviceInfo.brandDisplayName})', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              'Buka pengaturan agar pelacakan tidak dibunuh oleh sistem ${_deviceInfo.brandDisplayName}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                              onPressed: _showOemAutostartDialog,
                              child: const Text('Panduan'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Security & Anti-Theft Settings Card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              'Keamanan & Proteksi Anti-Maling',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.lock_outline, color: Colors.deepOrange),
                            title: const Text('PIN Keamanan Pemilik', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Digunakan untuk membuka kunci Mode HP Hilang (PIN: ${_currentPin.replaceAll(RegExp(r'.'), '•')})'),
                            trailing: TextButton(
                              onPressed: _changeOwnerPinDialog,
                              child: const Text('Ubah PIN', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.power_settings_new, color: Colors.red),
                            title: const Text('Pemicu Tombol Power SOS', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(_isPowerButtonEnabled
                                ? 'Aktif: Tekan tombol daya $_powerButtonCount x cepat'
                                : 'Nonaktif'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _showPowerButtonSettings,
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SwitchListTile(
                            secondary: const Icon(Icons.camera_front_outlined, color: Colors.amber),
                            title: const Text('Jebakan Penyusup (Silent Selfie)', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('Ambil foto kamera depan otomatis jika salah PIN 3x'),
                            value: _isIntruderTrapEnabled,
                            onChanged: (_) => _toggleIntruderTrap(),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: Icon(
                              Icons.phonelink_lock,
                              color: _isAccessibilityEnabled ? Colors.teal : Colors.deepOrange,
                            ),
                            title: const Text('Kunci Menu Power (Anti-Shutdown)', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              _isAccessibilityEnabled
                                  ? 'Aktif: Menu daya diblokir saat Mode HP Hilang aktif'
                                  : 'Nonaktif: Cegah maling mematikan HP via tombol daya',
                            ),
                            trailing: _isAccessibilityEnabled
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.shade300),
                                    ),
                                    child: const Text('Aktif', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepOrange,
                                      foregroundColor: Colors.white,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    onPressed: _showAccessibilityDialog,
                                    child: const Text('Aktifkan'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sound & Ringtone Settings Card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.music_note, color: Colors.indigo),
                      title: const Text('Pengaturan Nada & Ringtone', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Atur nada Alarm SOS, Sinyal Suara, dan Chat'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => SoundSettingsDialog.show(context),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Keluar dari Akun', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _signOut,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
