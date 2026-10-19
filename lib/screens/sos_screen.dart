import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/sos_trigger_service.dart';
import '../services/supabase_service.dart';

class SosScreen extends StatefulWidget {
  final CircleModel? selectedCircle;
  final List<SosAlert> activeAlerts;
  final VoidCallback onRefreshAlerts;

  const SosScreen({
    super.key,
    required this.selectedCircle,
    required this.activeAlerts,
    required this.onRefreshAlerts,
  });

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supa = SupabaseService();
  final LocationService _locService = LocationService();
  final SosTriggerService _sosTriggerService = SosTriggerService();

  late AnimationController _holdController;
  bool _isHolding = false;
  bool _isSending = false;
  UserProfile? _userProfile;
  bool _powerButtonEnabled = true;
  int _powerButtonCount = 3;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadTriggerSettings();

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerSOSDirectly();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prof = await _supa.getProfile();
    if (mounted) setState(() => _userProfile = prof);
  }

  Future<void> _loadTriggerSettings() async {
    final enabled = await _sosTriggerService.isPowerButtonEnabled();
    final count = await _sosTriggerService.getPowerButtonCount();
    if (mounted) {
      setState(() {
        _powerButtonEnabled = enabled;
        _powerButtonCount = count;
      });
    }
  }

  Future<void> _togglePowerButton(bool enabled) async {
    setState(() => _powerButtonEnabled = enabled);
    await _sosTriggerService.setPowerButtonSettings(
      enabled: enabled,
      count: _powerButtonCount,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled
              ? 'Deteksi Tombol Power diaktifkan ($_powerButtonCount x tekan cepat)'
              : 'Deteksi Tombol Power dinonaktifkan'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _setPowerButtonCount(int count) async {
    setState(() => _powerButtonCount = count);
    await _sosTriggerService.setPowerButtonSettings(
      enabled: _powerButtonEnabled,
      count: count,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Target tekan tombol power diubah ke $count x tekan cepat'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pinShortcut() async {
    final supported = await _sosTriggerService.isPinShortcutSupported();
    if (!supported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perangkat atau peluncur ini tidak mendukung penambahan pintasan otomatis.')),
        );
      }
      return;
    }

    final success = await _sosTriggerService.pinSosShortcut();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Pintasan Tombol SOS berhasil dikirim ke Layar Utama!'
              : 'Gagal menambahkan pintasan ke Layar Utama.'),
        ),
      );
    }
  }

  void _showQuickTileGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dashboard_customize, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text('Quick Settings Tile', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cara Menambahkan Tombol SOS ke Panel Atas HP:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('1. Tarik bar status (bagian paling atas HP) ke bawah 2 kali sampai panel tombol cepat terlihat penuh.'),
            SizedBox(height: 8),
            Text('2. Tekan ikon pensil / edit (Ubah Urutan Tombol).'),
            SizedBox(height: 8),
            Text('3. Cari tombol bertuliskan "SOS Darurat" di daftar tombol bawah, lalu geser ke atas.'),
            SizedBox(height: 10),
            Text(
              'Setelah dipasang, Anda bisa langsung memicu SOS hanya dengan 1 ketukan dari panel atas tanpa membuka aplikasi.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  void _startHold() {
    if (_isSending) return;
    setState(() => _isHolding = true);
    HapticFeedback.heavyImpact();
    _holdController.forward(from: 0.0);
  }

  void _cancelHold() {
    if (!_isHolding) return;
    if (_holdController.value < 1.0) {
      setState(() => _isHolding = false);
      _holdController.reset();
    }
  }

  Future<void> _triggerSOSDirectly() async {
    setState(() {
      _isSending = true;
      _isHolding = false;
    });
    HapticFeedback.heavyImpact();

    try {
      final pos = await _locService.getCurrentLocation();
      final lat = pos?.latitude ?? 0.0;
      final lng = pos?.longitude ?? 0.0;

      await _supa.triggerSOS(
        latitude: lat,
        longitude: lng,
        circleId: widget.selectedCircle?.id,
        customMessage: 'DARURAT! Saya membutuhkan pertolongan segera!',
      );

      widget.onRefreshAlerts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
            content: Text('Sinyal SOS BERHASIL diaktifkan & disiarkan ke seluruh anggota lingkaran!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim SOS: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _holdController.reset();
      }
    }
  }

  Future<void> _resolveSOS(String alertId) async {
    try {
      await _supa.resolveSOS(alertId);
      widget.onRefreshAlerts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status darurat telah diselesaikan.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui status: $e')),
        );
      }
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat memanggil $number')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _supa.currentUser?.id;
    final myActiveAlert = widget.activeAlerts.where((a) => a.userId == myUid).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pusat Darurat SOS'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Active SOS Status if triggered by user
            if (myActiveAlert != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red, width: 2),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.crisis_alert, color: Colors.red, size: 28),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'STATUS: SOS SEDANG AKTIF',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dikirim pada ${DateFormat('HH:mm:ss, d MMM').format(myActiveAlert.triggeredAt)}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Saya Sudah Aman (Selesaikan SOS)'),
                      onPressed: () => _resolveSOS(myActiveAlert.id),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Giant Panic Button (Hold 5 Seconds to Activate)
            Center(
              child: Column(
                children: [
                  Text(
                    _isHolding
                        ? 'Tetap tahan tombol sampai lingkaran merah penuh!'
                        : 'Tekan & tahan tombol selama 5 detik untuk mengaktifkan SOS darurat',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isHolding ? Colors.red.shade700 : Colors.grey,
                      fontSize: 13,
                      fontWeight: _isHolding ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _holdController,
                    builder: (context, _) {
                      final secondsLeft = (5.0 * (1.0 - _holdController.value)).ceil().clamp(1, 5);

                      return SizedBox(
                        width: 210,
                        height: 210,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Progress Outer Ring
                            SizedBox(
                              width: 210,
                              height: 210,
                              child: CircularProgressIndicator(
                                value: _isHolding ? _holdController.value : 0.0,
                                strokeWidth: 8,
                                backgroundColor: Colors.red.shade100,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade800),
                              ),
                            ),
                            // Button Body
                            GestureDetector(
                              onTapDown: (_) => _startHold(),
                              onTapUp: (_) => _cancelHold(),
                              onTapCancel: () => _cancelHold(),
                              child: Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isHolding ? Colors.red.shade800 : Colors.red.shade600,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: _isHolding ? 0.7 : 0.4),
                                      blurRadius: _isHolding ? 35 : 25,
                                      spreadRadius: _isHolding ? 12 : 8,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isSending
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : _isHolding
                                          ? Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '$secondsLeft',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 52,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const Text(
                                                  'TAHAN TERUS...',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.5,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.touch_app, color: Colors.white, size: 44),
                                                SizedBox(height: 4),
                                                Text(
                                                  'SOS',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 32,
                                                    letterSpacing: 2,
                                                  ),
                                                ),
                                                Text(
                                                  'TAHAN 5 DETIK',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),

            const Divider(),
            const SizedBox(height: 12),

            // Fast SOS Triggers Section (Without Opening App)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bolt, color: Colors.orange.shade800, size: 24),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Pemicu Cepat (Tanpa Buka Aplikasi)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pilih cara cepat yang ingin Anda aktifkan untuk memicu SOS darurat saat aplikasi tertutup atau layar mati:',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const Divider(height: 24),

                    // Trigger 1: Power Button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.power_settings_new, color: Colors.red.shade700, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Tombol Power Fisik',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  Switch(
                                    value: _powerButtonEnabled,
                                    activeThumbColor: Colors.red.shade700,
                                    onChanged: _togglePowerButton,
                                  ),
                                ],
                              ),
                              Text(
                                'Tekan tombol power di samping HP secara cepat berturut-turut di dalam saku untuk mengirim SOS rahasia.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              if (_powerButtonEnabled) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Sensitivitas: ',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                                    ),
                                    ChoiceChip(
                                      label: const Text('3x Tekan', style: TextStyle(fontSize: 11)),
                                      selected: _powerButtonCount == 3,
                                      selectedColor: Colors.red.shade100,
                                      onSelected: (sel) {
                                        if (sel) _setPowerButtonCount(3);
                                      },
                                    ),
                                    ChoiceChip(
                                      label: const Text('4x Tekan', style: TextStyle(fontSize: 11)),
                                      selected: _powerButtonCount == 4,
                                      selectedColor: Colors.red.shade100,
                                      onSelected: (sel) {
                                        if (sel) _setPowerButtonCount(4);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 24),

                    // Trigger 2: Quick Settings Tile
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.dashboard_customize, color: Colors.blue.shade700, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Panel Atas Android (Quick Tile)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'Tombol SOS langsung di bar status atas sebelah Wi-Fi/Senter. Tarik layar atas dan tap 1 kali.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.help_outline, size: 16),
                                label: const Text('Panduan Pasang', style: TextStyle(fontSize: 12)),
                                onPressed: _showQuickTileGuide,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 24),

                    // Trigger 3: Home Screen Shortcut
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add_to_home_screen, color: Colors.green.shade700, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pintasan Layar Utama (Home Screen)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'Tempatkan ikon tombol merah SOS langsung di halaman beranda ponsel Anda.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Pasang ke Layar Utama', style: TextStyle(fontSize: 12)),
                                onPressed: _pinShortcut,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Quick Hotlines Section
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Panggilan Cepat Darurat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),

            if (_userProfile?.emergencyContactPhone != null &&
                _userProfile!.emergencyContactPhone!.isNotEmpty)
              Card(
                color: Colors.indigo.shade50,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.favorite, color: Colors.white),
                  ),
                  title: const Text(
                    'Kontak Darurat Pribadi',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(_userProfile!.emergencyContactPhone!),
                  trailing: IconButton(
                    icon: const Icon(Icons.call, color: Colors.indigo),
                    onPressed: () => _callNumber(_userProfile!.emergencyContactPhone!),
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: _buildHotlineButton('Polisi', '110', Icons.local_police, Colors.blue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildHotlineButton('Ambulans', '118', Icons.medical_services, Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildHotlineButton('Damkar', '113', Icons.fire_truck, Colors.orange),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildHotlineButton('Basarnas / SAR', '115', Icons.health_and_safety, Colors.teal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotlineButton(String name, String number, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _callNumber(number),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 10.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(number, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
