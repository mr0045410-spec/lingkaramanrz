import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk mengelola nama panggilan / alias anggota lingkaran.
/// Disimpan secara lokal per-user sehingga fleksibel (misal: "Ayah", "Ibu", "Kakak", "Adek").
class MemberNicknameService extends ChangeNotifier {
  static final MemberNicknameService _instance = MemberNicknameService._internal();
  factory MemberNicknameService() => _instance;
  static MemberNicknameService get instance => _instance;
  MemberNicknameService._internal();

  static const String _prefix = 'member_nickname_';
  final Map<String, String> _cache = {};
  bool _isInitialized = false;

  /// Inisialisasi awal membaca semua nickname yang tersimpan di SharedPreferences
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_prefix)) {
          final userId = key.substring(_prefix.length);
          final value = prefs.getString(key);
          if (value != null && value.trim().isNotEmpty) {
            _cache[userId] = value.trim();
          }
        }
      }
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[MemberNicknameService] Error initializing: $e');
    }
  }

  /// Ambil nama panggilan tersimpan secara sinkron dari cache lokal
  String? getNickname(String userId) {
    final nick = _cache[userId];
    if (nick != null && nick.trim().isNotEmpty) {
      return nick.trim();
    }
    return null;
  }

  /// Helper untuk mendapatkan nama tampilan terbaik:
  /// Prioritas: Nama Panggilan lokal -> Nama Asli Profil -> Fallback ('Anggota')
  String getDisplayName(String userId, String? fallbackFullName) {
    final nick = getNickname(userId);
    if (nick != null && nick.isNotEmpty) {
      return nick;
    }
    if (fallbackFullName != null && fallbackFullName.trim().isNotEmpty) {
      return fallbackFullName.trim();
    }
    return 'Anggota';
  }

  /// Simpan atau perbarui nama panggilan anggota
  Future<void> setNickname(String userId, String nickname) async {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      await removeNickname(userId);
      return;
    }

    _cache[userId] = trimmed;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$userId', trimmed);
    } catch (e) {
      debugPrint('[MemberNicknameService] Error saving nickname: $e');
    }
  }

  /// Hapus nama panggilan (kembali menggunakan nama profil asli)
  Future<void> removeNickname(String userId) async {
    _cache.remove(userId);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$userId');
    } catch (e) {
      debugPrint('[MemberNicknameService] Error removing nickname: $e');
    }
  }
}
