import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/loud_signal_service.dart';
import '../services/phone_protection_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sos_trigger_service.dart';
import '../services/supabase_service.dart';
import '../widgets/geofence_map_picker.dart';
import '../widgets/sound_settings_dialog.dart';
import '../widgets/trip_history_sheet.dart';
import 'lost_mode_screen.dart';

class FeaturesScreen extends StatefulWidget {
  final List<CircleModel> circles;
  final CircleModel? selectedCircle;
  final Function(int tabIndex)? onNavigateToTab;
  final VoidCallback onRefresh;

  const FeaturesScreen({
    super.key,
    required this.circles,
    required this.selectedCircle,
    this.onNavigateToTab,
    required this.onRefresh,
  });

  @override
  State<FeaturesScreen> createState() => _FeaturesScreenState();
}

class _FeaturesScreenState extends State<FeaturesScreen> {
  final SupabaseService _supa = SupabaseService();
  final PhoneProtectionService _phoneProtectionService = PhoneProtectionService();
  final LoudSignalService _loudSignalService = LoudSignalService();
  final AudioService _audioService = AudioService();
  final SosTriggerService _sosTriggerService = SosTriggerService();

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // State caches
  bool _isLoudSignalTesting = false;
  bool _isAudioRecording = false;
  bool _isPowerButtonEnabled = true;
  int _powerButtonCount = 3;
  String _currentPin = '1234';
  bool _isLostModeActive = false;
  bool _isIntruderTrapEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final pin = await _phoneProtectionService.getOwnerPin();
    final pwrEnabled = await _sosTriggerService.isPowerButtonEnabled();
    final pwrCount = await _sosTriggerService.getPowerButtonCount();
    final prefs = await SharedPreferences.getInstance();
    final trap = prefs.getBool('intruder_trap_enabled') ?? true;
    final lostActive = _phoneProtectionService.isLostModeActive;
    if (mounted) {
      setState(() {
        _currentPin = pin;
        _isPowerButtonEnabled = pwrEnabled;
        _powerButtonCount = pwrCount;
        _isIntruderTrapEnabled = trap;
        _isLostModeActive = lostActive;
      });
    }
  }

  // --- ACTIONS ---

  void _toggleLostMode() async {
    if (_phoneProtectionService.isLostModeActive) {
      // Matikan: minta PIN
      final pinCtrl = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Matikan Mode HP Hilang'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Masukkan PIN Pemilik untuk mematikan Mode HP Hilang dan memulihkan akses.'),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'PIN Pemilik',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                final success = await _phoneProtectionService.verifyUnlockPin(pin, circleId: widget.selectedCircle?.id);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (success) {
                  setState(() => _isLostModeActive = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mode HP Hilang berhasil dinonaktifkan!')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(backgroundColor: Colors.red, content: Text('PIN salah! Gagal mematikan.')),
                    );
                  }
                }
              },
              child: const Text('Matikan Fitur'),
            ),
          ],
        ),
      );
    } else {
      // Nyalakan
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nyalakan Mode HP Hilang'),
          content: const Text(
            'Mode HP Hilang akan seketika mengunci layar penuh, menyalakan sirine darurat, dan mengaktifkan proteksi anti-bypass.\n\nNyalakan sekarang?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final myUid = _supa.currentUser?.id ?? 'local_user';
                final profile = await _supa.getMyProfile();
                final cmd = await _phoneProtectionService.sendLostModeCommand(
                  targetUserId: myUid,
                  contactPhone: profile?.emergencyContactPhone ?? profile?.phoneNumber ?? '+6281234567890',
                  message: 'PERANGKAT INI DALAM PENGAWASAN KELUARGA. Harap kembalikan ke pemilik.',
                  enableSiren: true,
                  enableFakeShutdown: false,
                  circleId: widget.selectedCircle?.id,
                );
                setState(() => _isLostModeActive = true);
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LostModeScreen(command: cmd)),
                  );
                }
              },
              child: const Text('Nyalakan Fitur'),
            ),
          ],
        ),
      );
    }
  }

  void _toggleFakeShutdown() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nyalakan Kamuflase Layar'),
        content: const Text(
          'Layar akan menjadi hitam pekat menipu pelaku seolah HP mati total. GPS tetap aktif melacak posisi.\n\nKetuk layar 3x secara cepat untuk membuka PIN.\n\nNyalakan sekarang?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final myUid = _supa.currentUser?.id ?? 'local_user';
              final profile = await _supa.getMyProfile();
              final cmd = await _phoneProtectionService.sendLostModeCommand(
                targetUserId: myUid,
                contactPhone: profile?.emergencyContactPhone ?? profile?.phoneNumber ?? '+6281234567890',
                message: 'PERANGKAT DALAM MODE STEALTH / KAMUFLASE.',
                enableSiren: false,
                enableFakeShutdown: true,
                circleId: widget.selectedCircle?.id,
              );
              setState(() => _isLostModeActive = true);
              if (mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => LostModeScreen(command: cmd)),
                );
              }
            },
            child: const Text('Nyalakan Kamuflase'),
          ),
        ],
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

  void _showTripHistoryMemberPicker() async {
    if (widget.selectedCircle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih atau buat lingkaran keluarga terlebih dahulu.')),
      );
      return;
    }

    try {
      final members = await _supa.getCircleMembers(widget.selectedCircle!.id);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timeline, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pilih Anggota untuk Riwayat Perjalanan',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...members.map((m) {
                final isMe = m.userId == _supa.currentUser?.id;
                final name = isMe ? 'Saya (${m.profile?.fullName ?? ""})' : (m.profile?.fullName ?? 'Anggota');
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isMe ? Colors.blue : Colors.teal,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(m.isAdmin ? '👑 Admin Utama' : '👤 Anggota'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    TripHistorySheet.show(context, m, widget.selectedCircle!);
                  },
                );
              }),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat anggota: $e')));
      }
    }
  }

  Future<void> _testLoudAlarm() async {
    if (_isLoudSignalTesting) return;
    setState(() => _isLoudSignalTesting = true);

    try {
      final myUid = _supa.currentUser?.id ?? 'self';
      await _loudSignalService.sendLoudSignal(
        targetUserId: myUid,
        circleId: widget.selectedCircle?.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('🔊 Sinyal Keras dipicu! Volume ponsel dimaksimalkan.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membunyikan sinyal keras: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoudSignalTesting = false);
    }
  }


  Future<void> _confirmVaultLockdown() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.shield, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Kunci Brankas Darurat'),
          ],
        ),
        content: const Text(
          'Tindakan ini akan mengamankan dan membersihkan token sesi, riwayat pencarian lokal, serta mengunci data aplikasi di memori perangkat ini.\n\nLanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kunci Sekarang'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _phoneProtectionService.executeLocalVaultLock();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.black87,
            content: Text('🔒 Brankas lokal berhasil dikunci & dibersihkan.'),
          ),
        );
      }
    }
  }

  Future<void> _changePinDialog() async {
    final ctrl = TextEditingController(text: _currentPin);
    final formKey = GlobalKey<FormState>();

    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah PIN Pemilik'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PIN ini digunakan untuk membuka layar Mode HP Hilang & Kamuflase Mati:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
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

  Future<void> _recordTestAmbientAudio() async {
    if (_isAudioRecording) return;
    setState(() => _isAudioRecording = true);

    try {
      final req = await _audioService.executeSelfTestRecording(
        durationSeconds: 10,
        circleId: widget.selectedCircle?.id,
      );
      if (req != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Text('🎙️ Rekaman 10 detik berhasil dibuat:\n${req.audioUrl ?? "Tersimpan"}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal merekam audio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAudioRecording = false);
    }
  }

  Future<void> _openAddGeofence() async {
    if (widget.selectedCircle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih atau buat lingkaran terlebih dahulu.')),
      );
      return;
    }

    final newGeo = await GeofenceMapPicker.open(
      context,
      circleId: widget.selectedCircle!.id,
    );

    if (newGeo != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Text('✅ Zona Aman "${newGeo.name}" berhasil ditambahkan!'),
        ),
      );
      widget.onRefresh();
    }
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Pusat Fitur LingkarAman',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // Search & Summary Header
          SliverToBoxAdapter(
            child: _buildHeader(),
          ),

          // Categories List
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Anti-Maling & Perlindungan HP
                if (_matches(query, ['anti-maling', 'maling', 'hp hilang', 'lost mode', 'kunci', 'sirene', 'kamuflase', 'pura-pura mati', 'jebakan', 'penyusup', 'salah pin', 'last breath', 'baterai', 'brankas'])) ...[
                  _buildSectionTitle(
                    title: 'Perlindungan HP & Anti-Maling',
                    icon: Icons.shield,
                    color: Colors.red.shade700,
                  ),
                  _buildFeatureCard(
                    title: 'Mode HP Hilang (Lost Mode)',
                    description: 'Kunci darurat layar penuh, pesan kontak pemilik, alarm sirine loop, dan auto-restore saat restart.',
                    icon: Icons.screen_lock_portrait,
                    iconBgColor: Colors.red.shade50,
                    iconColor: Colors.red.shade700,
                    badge: _isLostModeActive ? '🔴 AKTIF (Terkunci)' : '⚪ NONAKTIF',
                    badgeColor: _isLostModeActive ? Colors.red.shade100 : Colors.grey.shade200,
                    badgeTextColor: _isLostModeActive ? Colors.red.shade900 : Colors.grey.shade700,
                    primaryButtonText: _isLostModeActive ? 'Matikan Mode Hilang' : 'Nyalakan Mode Hilang',
                    primaryButtonIcon: _isLostModeActive ? Icons.lock_open : Icons.lock,
                    onPrimaryPressed: _toggleLostMode,
                  ),
                  _buildFeatureCard(
                    title: 'Kamuflase Pura-pura Mati (Fake Shutdown)',
                    description: 'Layar OLED hitam pekat menipu pelaku, GPS tetap aktif melacak posisi. Ketuk layar 3x untuk membuka PIN.',
                    icon: Icons.visibility_off,
                    iconBgColor: Colors.grey.shade200,
                    iconColor: Colors.black87,
                    badge: 'Stealth Mode',
                    badgeColor: Colors.grey.shade300,
                    badgeTextColor: Colors.black87,
                    primaryButtonText: 'Aktifkan Kamuflase Layar',
                    primaryButtonIcon: Icons.power_settings_new,
                    onPrimaryPressed: _toggleFakeShutdown,
                  ),
                  _buildFeatureCard(
                    title: 'Jebakan Penyusup (Intruder Trap)',
                    description: 'Mendeteksi 3x salah PIN. Kamera depan seketika menjepret foto wajah penyusup secara diam-diam dan menyiarkan foto & koordinat GPS ke keluarga.',
                    icon: Icons.camera_front,
                    iconBgColor: Colors.deepOrange.shade50,
                    iconColor: Colors.deepOrange,
                    badge: _isIntruderTrapEnabled ? '🟢 AKTIF (Selfie On)' : '⚪ NONAKTIF',
                    badgeColor: _isIntruderTrapEnabled ? Colors.deepOrange.shade100 : Colors.grey.shade200,
                    badgeTextColor: _isIntruderTrapEnabled ? Colors.deepOrange.shade900 : Colors.grey.shade700,
                    primaryButtonText: _isIntruderTrapEnabled ? 'Matikan Jebakan' : 'Nyalakan Jebakan',
                    primaryButtonIcon: _isIntruderTrapEnabled ? Icons.visibility_off : Icons.camera_front,
                    onPrimaryPressed: _toggleIntruderTrap,
                    secondaryButtonText: 'Ganti PIN',
                    secondaryButtonIcon: Icons.pin,
                    onSecondaryPressed: _changePinDialog,
                  ),
                  _buildFeatureCard(
                    title: 'Last Breath Beacon',
                    description: 'Deteksi otomatis ketika baterai ≤ 5%. Merekam dan menyiarkan koordinat GPS darurat terakhir sebelum HP mati total.',
                    icon: Icons.battery_alert,
                    iconBgColor: Colors.amber.shade50,
                    iconColor: Colors.amber.shade900,
                    badge: 'Aktif Otomatis ≤ 5%',
                    badgeColor: Colors.amber.shade100,
                    badgeTextColor: Colors.amber.shade900,
                  ),
                  _buildFeatureCard(
                    title: 'Kunci Brankas Darurat (Remote Wipe)',
                    description: 'Mengamankan dan menghapus cache lokal, token sesi, dan data privat jika HP dirampas atau hilang.',
                    icon: Icons.enhanced_encryption,
                    iconBgColor: Colors.blueGrey.shade50,
                    iconColor: Colors.blueGrey.shade800,
                    badge: 'Data Vault',
                    badgeColor: Colors.blueGrey.shade100,
                    badgeTextColor: Colors.blueGrey.shade900,
                    primaryButtonText: 'Kunci Brankas',
                    primaryButtonIcon: Icons.cleaning_services,
                    onPrimaryPressed: _confirmVaultLockdown,
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. Respon Cepat & Keselamatan
                if (_matches(query, ['respon', 'darurat', 'sinyal', 'keras', 'suara', 'ambient', 'audio', 'sos', 'power', 'tombol'])) ...[
                  _buildSectionTitle(
                    title: 'Respon Cepat & Keselamatan',
                    icon: Icons.crisis_alert,
                    color: Colors.indigo,
                  ),
                  _buildFeatureCard(
                    title: 'Sinyal Keras Darurat (Loud Siren)',
                    description: 'Membunyikan HP target dengan volume 100% bahkan saat mode hening atau Jangan Ganggu (DND).',
                    icon: Icons.volume_up,
                    iconBgColor: Colors.amber.shade50,
                    iconColor: Colors.orange.shade800,
                    badge: 'Bypass DND',
                    badgeColor: Colors.orange.shade100,
                    badgeTextColor: Colors.orange.shade900,
                    primaryButtonText: _isLoudSignalTesting ? 'Membunyikan...' : 'Tes Sinyal Keras',
                    primaryButtonIcon: Icons.campaign,
                    onPrimaryPressed: _isLoudSignalTesting ? null : _testLoudAlarm,
                  ),
                  _buildFeatureCard(
                    title: 'Monitor Suara Sekitar (Ambient Audio)',
                    description: 'Merekam situasi suara di sekitar perangkat anggota selama 10-30 detik saat ada bahaya atau kecurigaan.',
                    icon: Icons.mic,
                    iconBgColor: Colors.teal.shade50,
                    iconColor: Colors.teal.shade700,
                    badge: 'Audio Pengawas',
                    badgeColor: Colors.teal.shade100,
                    badgeTextColor: Colors.teal.shade900,
                    primaryButtonText: _isAudioRecording ? 'Merekam 10d...' : 'Uji Rekam Suara',
                    primaryButtonIcon: Icons.record_voice_over,
                    onPrimaryPressed: _isAudioRecording ? null : _recordTestAmbientAudio,
                  ),
                  _buildFeatureCard(
                    title: 'Pemicu Cepat Tombol Daya (SOS Shortcut)',
                    description: 'Tekan tombol Power berulang kali secara cepat untuk memicu SOS darurat otomatis tanpa membuka kunci HP.',
                    icon: Icons.bolt,
                    iconBgColor: Colors.purple.shade50,
                    iconColor: Colors.purple.shade700,
                    badge: _isPowerButtonEnabled ? 'Aktif ($_powerButtonCount x)' : 'Nonaktif',
                    badgeColor: _isPowerButtonEnabled ? Colors.purple.shade100 : Colors.grey.shade200,
                    badgeTextColor: _isPowerButtonEnabled ? Colors.purple.shade900 : Colors.grey.shade700,
                    primaryButtonText: 'Pengaturan Tombol',
                    primaryButtonIcon: Icons.settings_power,
                    onPrimaryPressed: () => _showPowerButtonSettings(),
                  ),
                  _buildFeatureCard(
                    title: 'Pusat Alarm Darurat (Layar SOS)',
                    description: 'Tombol SOS utama tahan 5 detik, daftar panggilan darurat keluarga aktif, dan nomor polisi/ambulans.',
                    icon: Icons.notifications_active,
                    iconBgColor: Colors.red.shade50,
                    iconColor: Colors.red,
                    badge: 'Layanan SOS',
                    badgeColor: Colors.red.shade100,
                    badgeTextColor: Colors.red.shade900,
                  ),
                  _buildFeatureCard(
                    title: 'Pengaturan Nada (Ringtone Selector)',
                    description: 'Sesuaikan nada dering untuk Alarm SOS Darurat, Sinyal Keras Pencarian, dan Notifikasi Obrolan Lingkaran.',
                    icon: Icons.music_note,
                    iconBgColor: Colors.indigo.shade50,
                    iconColor: Colors.indigo.shade700,
                    badge: 'Alarm, Suara & Chat',
                    badgeColor: Colors.indigo.shade100,
                    badgeTextColor: Colors.indigo.shade900,
                    primaryButtonText: 'Atur Ringtone',
                    primaryButtonIcon: Icons.tune,
                    onPrimaryPressed: () => SoundSettingsDialog.show(context),
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Lokasi, Geofence & Pengawasan
                if (_matches(query, ['lokasi', 'peta', 'geofence', 'zona aman', 'sekolah', 'rumah', 'riwayat', 'timeline', 'waktu layar', 'aplikasi'])) ...[
                  _buildSectionTitle(
                    title: 'Lokasi & Zona Aman',
                    icon: Icons.location_on,
                    color: Colors.teal.shade800,
                  ),
                  _buildFeatureCard(
                    title: 'Zona Aman Virtual (Geofencing)',
                    description: 'Buat pagar virtual di peta (Rumah, Sekolah, Kantor) dan dapatkan notifikasi saat anggota masuk atau keluar zona.',
                    icon: Icons.share_location,
                    iconBgColor: Colors.teal.shade50,
                    iconColor: Colors.teal.shade800,
                    badge: 'Pagar Virtual',
                    badgeColor: Colors.teal.shade100,
                    badgeTextColor: Colors.teal.shade900,
                    primaryButtonText: 'Tambah Zona Aman',
                    primaryButtonIcon: Icons.add_location_alt,
                    onPrimaryPressed: _openAddGeofence,
                  ),
                  _buildFeatureCard(
                    title: 'Peta Langsung Real-time',
                    description: 'Pelacakan posisi seluruh anggota lingkaran secara visual di peta interaktif lengkap dengan persentase baterai.',
                    icon: Icons.map,
                    iconBgColor: Colors.indigo.shade50,
                    iconColor: Colors.indigo,
                    badge: 'Live GPS',
                    badgeColor: Colors.indigo.shade100,
                    badgeTextColor: Colors.indigo.shade900,
                  ),
                  _buildFeatureCard(
                    title: 'Riwayat Perjalanan (Timeline)',
                    description: 'Melihat rekam jejak rute, titik singgah, dan linimasa pergerakan harian anak/anggota keluarga.',
                    icon: Icons.history,
                    iconBgColor: Colors.blue.shade50,
                    iconColor: Colors.blue.shade700,
                    badge: 'Log Perjalanan',
                    badgeColor: Colors.blue.shade100,
                    badgeTextColor: Colors.blue.shade900,
                    primaryButtonText: 'Buka Riwayat Perjalanan',
                    primaryButtonIcon: Icons.timeline,
                    onPrimaryPressed: _showTripHistoryMemberPicker,
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. Lingkaran Keluarga & Komunitas
                if (_matches(query, ['lingkaran', 'keluarga', 'anggota', 'kode', 'undangan', 'circle'])) ...[
                  _buildSectionTitle(
                    title: 'Lingkaran Keluarga',
                    icon: Icons.group_work,
                    color: Colors.blue.shade800,
                  ),
                  _buildFeatureCard(
                    title: 'Manajemen Anggota Lingkaran',
                    description: 'Daftar seluruh anggota keluarga yang terhubung, status baterai terkini, dan akses tindakan cepat.',
                    icon: Icons.people_alt,
                    iconBgColor: Colors.blue.shade50,
                    iconColor: Colors.blue.shade800,
                    badge: '${widget.circles.length} Lingkaran',
                    badgeColor: Colors.blue.shade100,
                    badgeTextColor: Colors.blue.shade900,
                  ),
                  if (widget.selectedCircle != null)
                    _buildFeatureCard(
                      title: 'Bagikan Kode Undangan',
                      description: 'Ajak anggota keluarga bergabung dengan kode unik: ${widget.selectedCircle!.inviteCode}',
                      icon: Icons.qr_code_2,
                      iconBgColor: Colors.green.shade50,
                      iconColor: Colors.green.shade800,
                      badge: 'Kode: ${widget.selectedCircle!.inviteCode}',
                      badgeColor: Colors.green.shade100,
                      badgeTextColor: Colors.green.shade900,
                      primaryButtonText: 'Salin Kode',
                      primaryButtonIcon: Icons.copy,
                      onPrimaryPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.selectedCircle!.inviteCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Kode undangan "${widget.selectedCircle!.inviteCode}" disalin ke clipboard!'),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 32),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(String query, List<String> keywords) {
    if (query.isEmpty) return true;
    for (final kw in keywords) {
      if (kw.contains(query) || query.contains(kw)) return true;
    }
    return false;
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.indigo,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search box
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Cari fitur (misal: anti-maling, sirine, geofence)...',
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Overview Health Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade400.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_user, color: Colors.greenAccent, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sistem Keamanan Aktif',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lost Mode Siap • GPS Live • Pemicu Cepat Aktif',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade700,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Siaga 24/7',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14.0, bottom: 8.0, left: 4.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String description,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String badge,
    required Color badgeColor,
    required Color badgeTextColor,
    String? primaryButtonText,
    IconData? primaryButtonIcon,
    VoidCallback? onPrimaryPressed,
    String? secondaryButtonText,
    IconData? secondaryButtonIcon,
    VoidCallback? onSecondaryPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: badgeTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((primaryButtonText != null && onPrimaryPressed != null) ||
                (secondaryButtonText != null && onSecondaryPressed != null)) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (secondaryButtonText != null && onSecondaryPressed != null) ...[
                    OutlinedButton.icon(
                      onPressed: onSecondaryPressed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo.shade700,
                        side: BorderSide(color: Colors.indigo.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: secondaryButtonIcon != null ? Icon(secondaryButtonIcon, size: 16) : const SizedBox.shrink(),
                      label: Text(
                        secondaryButtonText,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (primaryButtonText != null && onPrimaryPressed != null)
                    ElevatedButton.icon(
                      onPressed: onPrimaryPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: primaryButtonIcon != null ? Icon(primaryButtonIcon, size: 16) : const SizedBox.shrink(),
                      label: Text(
                        primaryButtonText,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showPowerButtonSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.settings_power, color: Colors.purple),
                    SizedBox(width: 8),
                    Text(
                      'Pengaturan Tombol Power SOS',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktifkan Deteksi Tombol Power'),
                  subtitle: const Text('Tekan tombol power berulang kali untuk memicu SOS'),
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
                const Text(
                  'Jumlah Tekanan Cepat:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [3, 4, 5].map((cnt) {
                    final selected = _powerButtonCount == cnt;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('$cnt Kali'),
                        selected: selected,
                        onSelected: (sel) async {
                          if (sel) {
                            setModalState(() => _powerButtonCount = cnt);
                            setState(() => _powerButtonCount = cnt);
                            await _sosTriggerService.setPowerButtonSettings(
                              enabled: _isPowerButtonEnabled,
                              count: cnt,
                            );
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
