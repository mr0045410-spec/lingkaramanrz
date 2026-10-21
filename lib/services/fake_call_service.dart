import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sound_settings_service.dart';
import '../screens/fake_call_screen.dart';

class FakeCallService {
  static final FakeCallService _instance = FakeCallService._internal();
  factory FakeCallService() => _instance;
  FakeCallService._internal();

  static const String _prefCallerName = 'fake_call_caller_name';
  static const String _prefCallerNumber = 'fake_call_caller_number';

  Timer? _scheduleTimer;
  int _countdownRemaining = 0;
  final StreamController<int> _countdownController = StreamController<int>.broadcast();
  Stream<int> get onCountdown => _countdownController.stream;

  bool get isScheduled => _scheduleTimer != null && _scheduleTimer!.isActive;
  int get countdownRemaining => _countdownRemaining;

  Future<String> getCallerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCallerName) ?? 'Ibu (Rumah)';
  }

  Future<void> setCallerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCallerName, name);
  }

  Future<String> getCallerNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCallerNumber) ?? '+62 812-3456-7890';
  }

  Future<void> setCallerNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCallerNumber, number);
  }

  void cancelScheduledCall() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _countdownRemaining = 0;
    _countdownController.add(0);
  }

  void scheduleCall(BuildContext context, {required Duration delay, String? customName, String? customNumber}) {
    cancelScheduledCall();
    _countdownRemaining = delay.inSeconds;
    _countdownController.add(_countdownRemaining);

    if (_countdownRemaining <= 0) {
      launchCallNow(context, callerName: customName, callerNumber: customNumber);
      return;
    }

    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownRemaining--;
      _countdownController.add(_countdownRemaining);

      if (_countdownRemaining <= 0) {
        timer.cancel();
        _scheduleTimer = null;
        launchCallNow(context, callerName: customName, callerNumber: customNumber);
      }
    });
  }

  Future<void> launchCallNow(BuildContext context, {String? callerName, String? callerNumber}) async {
    cancelScheduledCall();

    final name = callerName ?? await getCallerName();
    final number = callerNumber ?? await getCallerNumber();

    // Mulai nada dering sistem
    try {
      await SoundSettingsService().previewSound('system_ringtone');
    } catch (_) {}

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => FakeCallScreen(
            callerName: name,
            callerNumber: number,
          ),
        ),
      );
    }
  }
}
