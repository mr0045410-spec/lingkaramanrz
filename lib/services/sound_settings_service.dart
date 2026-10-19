import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundOption {
  final String id;
  final String name;
  final String description;

  const SoundOption({
    required this.id,
    required this.name,
    required this.description,
  });
}

class SoundSettingsService {
  static final SoundSettingsService _instance = SoundSettingsService._internal();
  factory SoundSettingsService() => _instance;
  SoundSettingsService._internal();

  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/sound_settings');

  static const String keySosAlarm = 'ringtone_sos_alarm';
  static const String keyLoudSignal = 'ringtone_loud_signal';
  static const String keyChat = 'ringtone_chat';

  // Sound Options Definitions
  static const List<SoundOption> sosAlarmOptions = [
    SoundOption(
      id: 'siren_pulse',
      name: 'Sirine Darurat Bertubi-tubi',
      description: 'Sirine loop keras, frekuensi tinggi tembus bising',
    ),
    SoundOption(
      id: 'siren_fire',
      name: 'Peringatan Bahaya Frekuensi Tinggi',
      description: 'Peringatan cepat intensitas tinggi untuk kondisi kritis',
    ),
    SoundOption(
      id: 'system_alarm',
      name: 'Alarm Sistem Android',
      description: 'Nada alarm bawaan ponsel pengguna',
    ),
    SoundOption(
      id: 'system_ringtone',
      name: 'Ringtone Panggilan Keras',
      description: 'Nada dering telepon bawaan sistem',
    ),
  ];

  static const List<SoundOption> loudSignalOptions = [
    SoundOption(
      id: 'radar_beep',
      name: 'Radar Bip Panggilan',
      description: 'Beeper sonar berulang untuk menemukan posisi HP',
    ),
    SoundOption(
      id: 'digital_bell',
      name: 'Lonceng Digital',
      description: 'Lonceng nada tinggi berulang',
    ),
    SoundOption(
      id: 'system_ringtone',
      name: 'Nada Dering Sistem',
      description: 'Ringtone default panggilan telepon',
    ),
    SoundOption(
      id: 'siren_pulse',
      name: 'Sirine Darurat',
      description: 'Sirine darurat bertubi-tubi',
    ),
  ];

  static const List<SoundOption> chatOptions = [
    SoundOption(
      id: 'bubble_pop',
      name: 'Gelembung Pesan (Pop)',
      description: 'Nada pop gelembung bersih dan ramah',
    ),
    SoundOption(
      id: 'crystal_ping',
      name: 'Kristal Ding (Clean Ping)',
      description: 'Nada ding jernih elegan',
    ),
    SoundOption(
      id: 'double_tone',
      name: 'Dobel Tone Lembut',
      description: 'Dua ketukan nada lembut modern',
    ),
    SoundOption(
      id: 'system_notif',
      name: 'Notifikasi Default Sistem',
      description: 'Nada notifikasi standar bawaan Android',
    ),
  ];

  Future<String> getSelectedSound(String categoryKey) async {
    final prefs = await SharedPreferences.getInstance();
    switch (categoryKey) {
      case keySosAlarm:
        return prefs.getString(keySosAlarm) ?? 'siren_pulse';
      case keyLoudSignal:
        return prefs.getString(keyLoudSignal) ?? 'radar_beep';
      case keyChat:
        return prefs.getString(keyChat) ?? 'bubble_pop';
      default:
        return 'bubble_pop';
    }
  }

  Future<void> setSelectedSound(String categoryKey, String soundId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(categoryKey, soundId);
  }

  Future<void> previewSound(String soundId) async {
    try {
      await _channel.invokeMethod('previewSound', {'soundId': soundId});
    } catch (_) {}
  }

  Future<void> stopPreview() async {
    try {
      await _channel.invokeMethod('stopPreview');
    } catch (_) {}
  }

  Future<void> showChatNotification({
    required String senderName,
    required String message,
    required String circleName,
  }) async {
    try {
      final soundId = await getSelectedSound(keyChat);
      final title = '$senderName • $circleName';
      await _channel.invokeMethod('showChatNotification', {
        'title': title,
        'message': message,
        'soundId': soundId,
      });
    } catch (_) {}
  }

  Future<void> showEmergencyNotification({
    required String title,
    required String message,
  }) async {
    try {
      await _channel.invokeMethod('showEmergencyNotification', {
        'title': title,
        'message': message,
      });
    } catch (_) {}
  }

  Future<void> cancelEmergencyNotification() async {
    try {
      await _channel.invokeMethod('cancelEmergencyNotification');
    } catch (_) {}
  }
}
