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

class _LostModeScreenState extends State<LostModeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final PhoneProtectionService _protectionService = PhoneProtectionService();
  final LoudSignalService _loudSignal = LoudSignalService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isFakeShutdown = false;
  int _fakeShutdownTapCount = 0;
  Timer? _tapResetTimer;
  bool _isSirenActive = false;
  StreamSubscription<LostModeCommand>? _lostModeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sembunyikan status bar dan bar sistem agar fullscreen murni
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _isFakeShutdown = widget.command.enableFakeShutdown;
    _isSirenActive = widget.command.enableSiren;

    _lostModeSub = _protectionService.onLostModeChanged.listen((cmd) {
      if (!cmd.isActive && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _lostModeSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
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

  // 1. NORMAL LOST MODE VIEW (Sesuai Referensi Layar 5)
  Widget _buildNormalLostModeView() {
    final contact = widget.command.contactPhone.trim();
    final message = widget.command.message.trim().isNotEmpty
        ? widget.command.message.trim()
        : 'Tolong hubungi pemilik. Ada imbalan bagi yang mengembalikan.';

    return Container(
      color: const Color(0xFF1E212B),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                    child: Column(
                      children: [
                        const Spacer(),

                        // Lingkaran Merah dengan Ikon Perisai Putih (Denyut)
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626), // Merah cerah
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDC2626).withOpacity(0.4),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.shield_rounded,
                                color: Colors.white,
                                size: 52,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Judul: "HP INI HILANG"
                        const Text(
                          'HP INI HILANG',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Container Pesan Pemilik (Biru Gelap / Slate)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF282D3A),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Tombol Hijau: "TELEPON PEMILIK"
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A), // Hijau solid
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.phone, size: 20, color: Colors.white),
                            label: Text(
                              contact.isNotEmpty ? 'TELEPON PEMILIK ($contact)' : 'TELEPON PEMILIK',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            onPressed: contact.isNotEmpty ? _callContactNumber : null,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Tombol Outline Putih: "MASUKKAN PIN"
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _showUnlockDialog,
                            child: const Text(
                              'MASUKKAN PIN',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 4 Bulatan Indikator PIN (o o o o)
                        GestureDetector(
                          onTap: _showUnlockDialog,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white70, width: 1.5),
                                  color: Colors.transparent,
                                ),
                              );
                            }),
                          ),
                        ),

                        const Spacer(),
                        const SizedBox(height: 24),

                        // Footer Status GPS
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Lokasi HP ini sedang dibagikan ke keluarga pemilik',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
