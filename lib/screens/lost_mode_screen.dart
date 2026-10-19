import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/loud_signal_service.dart';
import '../services/phone_protection_service.dart';

class LostModeScreen extends StatefulWidget {
  final LostModeCommand command;

  const LostModeScreen({
    super.key,
    required this.command,
  });

  @override
  State<LostModeScreen> createState() => _LostModeScreenState();
}

class _LostModeScreenState extends State<LostModeScreen> with SingleTickerProviderStateMixin {
  final PhoneProtectionService _protectionService = PhoneProtectionService();
  final LoudSignalService _loudSignal = LoudSignalService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isFakeShutdown = false;
  int _fakeShutdownTapCount = 0;
  Timer? _tapResetTimer;
  bool _isSirenActive = false;

  @override
  void initState() {
    super.initState();
    _isFakeShutdown = widget.command.enableFakeShutdown;
    _isSirenActive = widget.command.enableSiren;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_isSirenActive) {
      _loudSignal.playNativeAlarm();
    }

    if (widget.command.isActive) {
      _protectionService.enableNativeAntiBypass(
        contactPhone: widget.command.contactPhone,
        message: widget.command.message,
        enableSiren: widget.command.enableSiren,
      );
    }

    if (_isFakeShutdown) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pulseController.dispose();
    _tapResetTimer?.cancel();
    _loudSignal.stopNativeAlarm();
    super.dispose();
  }

  Future<void> _callContactNumber() async {
    final phone = widget.command.contactPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _toggleSiren() {
    setState(() {
      _isSirenActive = !_isSirenActive;
      if (_isSirenActive) {
        _loudSignal.playNativeAlarm();
      } else {
        _loudSignal.stopNativeAlarm();
      }
    });
  }

  void _onFakeShutdownTap() {
    _tapResetTimer?.cancel();
    _fakeShutdownTapCount++;
    if (_fakeShutdownTapCount >= 3) {
      _fakeShutdownTapCount = 0;
      _showUnlockDialog();
    } else {
      _tapResetTimer = Timer(const Duration(milliseconds: 1500), () {
        _fakeShutdownTapCount = 0;
      });
    }
  }

  Future<void> _showUnlockDialog() async {
    final pinController = TextEditingController();
    String? errorMsg;
    bool isChecking = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final failedCount = _protectionService.failedPinAttempts;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: const [
                  Icon(Icons.lock_open_rounded, color: Colors.amberAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Buka Kunci Pemilik',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Masukkan 4-digit PIN keamanan pemilik untuk menonaktifkan Mode HP Hilang.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        counterText: '',
                        hintText: '••••',
                        hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.amberAccent, width: 2),
                        ),
                      ),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                errorMsg!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (failedCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Peringatan: Percobaan salah ($failedCount). Jika mencapai 3x, Jebakan Penyusup akan mengirimkan sinyal & titik GPS ke lingkaran keluarga!',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isChecking
                      ? null
                      : () {
                          Navigator.of(dialogCtx).pop();
                        },
                  child: const Text('Batal', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isChecking
                      ? null
                      : () async {
                          final pin = pinController.text.trim();
                          if (pin.isEmpty) {
                            setDialogState(() => errorMsg = 'PIN tidak boleh kosong');
                            return;
                          }

                          setDialogState(() => isChecking = true);
                          final nav = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);

                          final ok = await _protectionService.verifyUnlockPin(
                            pin,
                            circleId: widget.command.circleId,
                          );

                          if (ok) {
                            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                            if (mounted) {
                              await _loudSignal.stopNativeAlarm();
                              if (nav.canPop()) {
                                nav.pop();
                              }
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Kunci berhasil dibuka. Mode HP Hilang nonaktif.'),
                                  backgroundColor: Colors.teal,
                                ),
                              );
                            }
                          } else {
                            final attempts = _protectionService.failedPinAttempts;
                            setDialogState(() {
                              isChecking = false;
                              errorMsg = attempts >= 3
                                  ? '📸 JEBAKAN PENYUSUP AKTIF! Percobaan ke-$attempts telah dilaporkan & foto wajah telah diambil!'
                                  : 'PIN Salah! Percobaan ke-$attempts';
                            });
                          }
                        },
                  child: isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                        )
                      : const Text('Verifikasi PIN', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ScaffoldMessenger(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.black,
          body: _isFakeShutdown ? _buildFakeShutdownView() : _buildNormalLostModeView(),
        ),
      ),
    );
  }

  // 4. PURA-PURA MATI (FAKE SHUTDOWN) VIEW
  Widget _buildFakeShutdownView() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onFakeShutdownTap,
      onLongPress: _showUnlockDialog,
      child: SizedBox.expand(
        child: Container(
          color: Colors.black,
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 24),
          child: Opacity(
            opacity: 0.15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.touch_app, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text(
                  'Ketuk 3x atau tahan layar untuk buka kunci',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. NORMAL LOST MODE VIEW
  Widget _buildNormalLostModeView() {
    final contact = widget.command.contactPhone.trim();
    final message = widget.command.message.trim().isNotEmpty
        ? widget.command.message.trim()
        : 'HP ini dalam mode hilang. Mohon bantu kembalikan ke pemiliknya.';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2A0000),
            const Color(0xFF0F0000),
            Colors.black,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    child: Column(
                      children: [
              const SizedBox(height: 16),

              // Animated Pulsing Warning Icon
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 2),
                  ),
                  child: const Icon(
                    Icons.phonelink_lock_rounded,
                    color: Colors.redAccent,
                    size: 58,
                  ),
                ),
              ),

              const SizedBox(height: 18),
              const Text(
                'MODE HP HILANG AKTIF',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ponsel ini dalam pengawasan keluarga LingkarAman.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // Message Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade800.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.speaker_notes, color: Colors.amberAccent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pesan dari Pemilik:',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Direct Phone Call Button
              if (contact.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.phone, size: 22),
                    label: Text(
                      'Hubungi Pemilik: $contact',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _callContactNumber,
                  ),
                ),

              const SizedBox(height: 14),

              // GPS Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.gps_fixed, color: Colors.tealAccent, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pelacakan GPS aktif. Koordinat terus dikirimkan secara langsung ke keluarga.',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Siren & Fake Shutdown Toggles
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _isSirenActive ? Colors.redAccent : Colors.white70,
                        side: BorderSide(
                          color: _isSirenActive ? Colors.redAccent : Colors.white24,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(_isSirenActive ? Icons.volume_up : Icons.volume_off, size: 18),
                      label: Text(
                        _isSirenActive ? 'Sirine Nyala' : 'Sirine Hening',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _toggleSiren,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: const BorderSide(color: Colors.cyanAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.power_settings_new, size: 18),
                      label: const Text(
                        'Kamuflase Mati',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        setState(() => _isFakeShutdown = true);
                        _protectionService.toggleFakeShutdown(true);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Owner Unlock Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.lock_open, size: 20),
                  label: const Text(
                    'Buka Kunci Pemilik (PIN)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _showUnlockDialog,
                ),
              ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
}
