import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sound_settings_service.dart';

class FakeCallScreen extends StatefulWidget {
  final String callerName;
  final String callerNumber;

  const FakeCallScreen({
    super.key,
    required this.callerName,
    required this.callerNumber,
  });

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> with SingleTickerProviderStateMixin {
  bool _isAnswered = false;
  int _callDurationSeconds = 0;
  Timer? _callDurationTimer;

  bool _isMuted = false;
  bool _isSpeaker = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _callDurationTimer?.cancel();
    _pulseController.dispose();
    SoundSettingsService().stopPreview();
    super.dispose();
  }

  void _answerCall() {
    SoundSettingsService().stopPreview();
    setState(() {
      _isAnswered = true;
    });

    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  void _endCall() {
    SoundSettingsService().stopPreview();
    _callDurationTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _endCall();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Dark slate premium
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 30),

              // Status Bar Panggilan
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isAnswered ? Icons.phone_in_talk_rounded : Icons.ring_volume_rounded,
                    color: _isAnswered ? Colors.greenAccent : Colors.amberAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAnswered
                        ? 'Terhubung • ${_formatDuration(_callDurationSeconds)}'
                        : 'Panggilan Masuk Darurat',
                    style: TextStyle(
                      color: _isAnswered ? Colors.greenAccent : Colors.white70,
                      fontSize: 14,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Avatar & Pulse
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = _isAnswered ? 1.0 : (1.0 + _pulseController.value * 0.08);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1E293B),
                        boxShadow: [
                          BoxShadow(
                            color: _isAnswered
                                ? Colors.greenAccent.withOpacity(0.2)
                                : Colors.indigoAccent.withOpacity(0.35 * _pulseController.value),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Nama Penelepon
              Text(
                widget.callerName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.callerNumber,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),

              const Spacer(),

              // Tampilan jika sudah terhubung (Active Call)
              if (_isAnswered) ...[
                // Kartu naskah penyelamat
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.record_voice_over_rounded, color: Colors.indigoAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Alasan Menyelamatkan Diri (Naskah):',
                            style: TextStyle(
                              color: Colors.indigoAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '"Halo? Kamu di mana sekarang? Ini Ibu sudah sampai di depan nungguin kamu di mobil. Ayo buruan keluar sekarang, jangan kelamaan ya!"',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Tombol Kontrol Panggilan (Mute, Keypad, Speaker)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCallToolButton(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: 'Mute',
                        isActive: _isMuted,
                        onTap: () => setState(() => _isMuted = !_isMuted),
                      ),
                      _buildCallToolButton(
                        icon: Icons.dialpad_rounded,
                        label: 'Keypad',
                        isActive: false,
                        onTap: () {},
                      ),
                      _buildCallToolButton(
                        icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: 'Speaker',
                        isActive: _isSpeaker,
                        onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Tombol Tutup Panggilan (End Call)
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent,
                      boxShadow: [
                        BoxShadow(color: Colors.red, blurRadius: 16, spreadRadius: 2),
                      ],
                    ),
                    child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Tutup Panggilan', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ] else ...[
                // Tampilan Panggilan Masuk (Incoming Call)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Tombol Tolak
                      Column(
                        children: [
                          GestureDetector(
                            onTap: _endCall,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.redAccent,
                                boxShadow: [
                                  BoxShadow(color: Colors.red, blurRadius: 14, spreadRadius: 1),
                                ],
                              ),
                              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('Tolak', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),

                      // Tombol Terima
                      Column(
                        children: [
                          GestureDetector(
                            onTap: _answerCall,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green,
                                boxShadow: [
                                  BoxShadow(color: Colors.greenAccent, blurRadius: 18, spreadRadius: 2),
                                ],
                              ),
                              child: const Icon(Icons.call_rounded, color: Colors.white, size: 38),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('Terima', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallToolButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : const Color(0xFF334155),
            ),
            child: Icon(icon, color: isActive ? Colors.black87 : Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
