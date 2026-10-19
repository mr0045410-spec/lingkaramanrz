import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../utils/disposable_email_checker.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isSignUp = false;
  bool _isOtpSent = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;

  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 60);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() => _resendCountdown--);
      } else {
        setState(() => _resendCountdown = 0);
        timer.cancel();
      }
    });
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    if (!isResend) {
      if (!_formKey.currentState!.validate()) return;
    }

    final email = _emailController.text.trim();

    // Verifikasi anti-temp mail sebelum kirim ke server
    final tempMailError = DisposableEmailChecker.validateEmail(email);
    if (tempMailError != null) {
      setState(() => _errorMessage = tempMailError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService().sendEmailOtp(
        email: email,
        shouldCreateUser: true,
        fullName: _isSignUp ? _nameController.text.trim() : null,
        phoneNumber: (_isSignUp && _phoneController.text.trim().isNotEmpty)
            ? _phoneController.text.trim()
            : null,
      );

      if (mounted) {
        setState(() {
          _isOtpSent = true;
          _isLoading = false;
        });
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.mark_email_read, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isResend
                        ? 'Kode OTP baru telah dikirim ke $email'
                        : 'Kode verifikasi 6 digit telah dikirim ke $email',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Masukkan 6 digit kode OTP secara lengkap');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService().verifyEmailOtp(
        email: _emailController.text.trim(),
        token: otp,
      );

      if (mounted) {
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          final rawMsg = e.toString().replaceAll('Exception:', '').trim();
          if (rawMsg.toLowerCase().contains('invalid') ||
              rawMsg.toLowerCase().contains('expired') ||
              rawMsg.toLowerCase().contains('token')) {
            _errorMessage = 'Kode OTP salah atau sudah kedaluwarsa. Silakan periksa kembali email Anda.';
          } else {
            _errorMessage = rawMsg;
          }
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService().signInWithGoogle();
      if (mounted) {
        widget.onAuthenticated();
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception:', '').trim();
      if (!msg.toLowerCase().contains('batal') && !msg.toLowerCase().contains('cancel')) {
        if (mounted) {
          setState(() => _errorMessage = msg);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Card(
                elevation: 8,
                color: Colors.white.withValues(alpha: 0.95),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _isOtpSent ? _buildOtpStep(theme) : _buildEmailStep(theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// TAHAP 1: INPUT NAMA & EMAIL (DENGAN PROTEKSI ANTI-TEMP MAIL)
  Widget _buildEmailStep(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo / Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 56,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'LingkarAman',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          Text(
            'Pelindung Keluarga & Komunitas',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),

          // Tab Selector: Masuk / Daftar
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (_isSignUp) {
                        setState(() {
                          _isSignUp = false;
                          _errorMessage = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isSignUp ? Colors.redAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Masuk',
                        style: TextStyle(
                          color: !_isSignUp ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (!_isSignUp) {
                        setState(() {
                          _isSignUp = true;
                          _errorMessage = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isSignUp ? Colors.redAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Daftar Baru',
                        style: TextStyle(
                          color: _isSignUp ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (_errorMessage != null) _buildErrorCard(_errorMessage!),

          // Badge Info Keamanan Email Asli
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 18, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Verifikasi aman via OTP email. Temp mail otomatis ditolak.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),

          if (_isSignUp) ...[
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Lengkap',
                hintText: 'Contoh: Budi Santoso',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nama lengkap wajib diisi' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Nomor WhatsApp / HP (Opsional)',
                hintText: 'Contoh: 081234567890',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Alamat Email Pribadi',
              hintText: 'nama@gmail.com',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: DisposableEmailChecker.validateEmail,
          ),
          const SizedBox(height: 20),

          // Tombol Kirim Kode OTP
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isLoading
                  ? const SizedBox.shrink()
                  : const Icon(Icons.send_rounded, size: 20),
              label: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isSignUp ? 'Kirim Kode OTP Pendaftaran' : 'Kirim Kode OTP Masuk',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              onPressed: _isLoading ? null : () => _sendOtp(isResend: false),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ATAU',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 16),

          // Tombol Masuk dengan Google
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_isLoading || _isGoogleLoading) ? null : _signInWithGoogle,
              child: _isGoogleLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.redAccent,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Lanjutkan dengan Google',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// TAHAP 2: INPUT KODE VERIFIKASI OTP 6 DIGIT
  Widget _buildOtpStep(ThemeData theme) {
    final email = _emailController.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon Email Terkirim
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mark_email_read_outlined,
            size: 52,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 14),

        const Text(
          'Masukkan Kode Verifikasi',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'Kode 6 digit telah dikirim ke:',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          email,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 20),

        if (_errorMessage != null) _buildErrorCard(_errorMessage!),

        // Input 6 Digit OTP
        TextFormField(
          controller: _otpController,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 14,
            color: Colors.black87,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: TextStyle(
              letterSpacing: 14,
              color: Colors.grey.shade400,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 2),
            ),
          ),
          onChanged: (val) {
            if (val.trim().length == 6) {
              _verifyOtp();
            }
          },
        ),
        const SizedBox(height: 20),

        // Tombol Verifikasi
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _isLoading ? null : _verifyOtp,
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Verifikasi & Masuk',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Kirim Ulang & Ganti Email
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Ganti Email', style: TextStyle(fontSize: 13)),
              onPressed: _isLoading
                  ? null
                  : () {
                      _countdownTimer?.cancel();
                      setState(() {
                        _isOtpSent = false;
                        _errorMessage = null;
                        _otpController.clear();
                      });
                    },
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: (_resendCountdown == 0 && !_isLoading)
                  ? () => _sendOtp(isResend: true)
                  : null,
              child: Text(
                _resendCountdown > 0
                    ? 'Kirim ulang (${_resendCountdown}s)'
                    : 'Kirim Ulang Kode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _resendCountdown == 0 ? Colors.indigo : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorCard(String errorText) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
