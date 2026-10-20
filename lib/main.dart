import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lost_mode_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/phone_protection_service.dart';
import 'services/push_notification_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  runApp(const LingkarAmanApp());

  // Initialize Phone Protection (Lost Mode persistence & anti-theft)
  unawaited(PhoneProtectionService().initialize());
  // Initialize Push Notification Service
  unawaited(PushNotificationService().initialize());
}

class LingkarAmanApp extends StatefulWidget {
  const LingkarAmanApp({super.key});

  @override
  State<LingkarAmanApp> createState() => _LingkarAmanAppState();
}

class _LingkarAmanAppState extends State<LingkarAmanApp> {
  final SupabaseService _supa = SupabaseService();
  final PhoneProtectionService _protectionService = PhoneProtectionService();
  StreamSubscription<LostModeCommand>? _lostModeSub;

  bool _isAuthenticated = false;
  bool _onboardingCompleted = false;
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();

    _lostModeSub = _protectionService.onLostModeChanged.listen((cmd) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lostModeSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('onboarding_completed') ?? false;

    if (mounted) {
      setState(() {
        _isAuthenticated = _supa.isAuthenticated;
        _onboardingCompleted = onboarded;
        _isCheckingAuth = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget homeWidget;
    if (_protectionService.isLostModeActive) {
      homeWidget = LostModeScreen(
        command: _protectionService.activeLostMode ??
            LostModeCommand(
              id: 'persisted_active',
              targetUserId: _supa.currentUser?.id ?? '',
              senderId: 'remote',
              isActive: true,
              contactPhone: '',
              message: 'HP ini dalam mode hilang. Segera hubungi pemilik.',
              enableSiren: true,
              enableFakeShutdown: false,
              updatedAt: DateTime.now(),
            ),
      );
    } else if (_isCheckingAuth) {
      homeWidget = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (!_onboardingCompleted) {
      homeWidget = OnboardingScreen(onFinished: () => setState(() => _onboardingCompleted = true));
    } else if (!_isAuthenticated) {
      homeWidget = AuthScreen(onAuthenticated: () => _checkAuth());
    } else {
      homeWidget = HomeScreen(onSignedOut: () => setState(() => _isAuthenticated = false));
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Deep Indigo / Navy
          primary: const Color(0xFF1E3A8A),
          error: Colors.redAccent,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: homeWidget,
    );
  }
}
