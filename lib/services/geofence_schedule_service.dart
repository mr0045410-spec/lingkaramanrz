import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeofenceSchedule {
  final String geofenceId;
  final bool isEnabled;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<int> daysOfWeek; // 1=Senin, ..., 7=Minggu

  const GeofenceSchedule({
    required this.geofenceId,
    this.isEnabled = false,
    this.startHour = 7,
    this.startMinute = 0,
    this.endHour = 15,
    this.endMinute = 0,
    this.daysOfWeek = const [1, 2, 3, 4, 5], // default Senin-Jumat
  });

  Map<String, dynamic> toMap() => {
        'geofenceId': geofenceId,
        'isEnabled': isEnabled,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'daysOfWeek': daysOfWeek,
      };

  factory GeofenceSchedule.fromMap(Map<String, dynamic> map) => GeofenceSchedule(
        geofenceId: map['geofenceId'] as String? ?? '',
        isEnabled: map['isEnabled'] as bool? ?? false,
        startHour: map['startHour'] as int? ?? 7,
        startMinute: map['startMinute'] as int? ?? 0,
        endHour: map['endHour'] as int? ?? 15,
        endMinute: map['endMinute'] as int? ?? 0,
        daysOfWeek: (map['daysOfWeek'] as List<dynamic>?)?.map((e) => e as int).toList() ??
            const [1, 2, 3, 4, 5],
      );

  String get timeRangeString {
    final sH = startHour.toString().padLeft(2, '0');
    final sM = startMinute.toString().padLeft(2, '0');
    final eH = endHour.toString().padLeft(2, '0');
    final eM = endMinute.toString().padLeft(2, '0');
    return '$sH:$sM - $eH:$eM';
  }

  String get daysSummary {
    if (daysOfWeek.length == 7) return 'Setiap Hari';
    if (daysOfWeek.length == 5 &&
        daysOfWeek.contains(1) &&
        daysOfWeek.contains(2) &&
        daysOfWeek.contains(3) &&
        daysOfWeek.contains(4) &&
        daysOfWeek.contains(5)) {
      return 'Sen - Jum';
    }
    const dayNames = {1: 'Sen', 2: 'Sel', 3: 'Rab', 4: 'Kam', 5: 'Jum', 6: 'Sab', 7: 'Min'};
    return daysOfWeek.map((d) => dayNames[d] ?? '').where((s) => s.isNotEmpty).join(', ');
  }

  bool isCurrentlyActive(DateTime now) {
    if (!isEnabled) return true; // Jika jadwal tidak diaktifkan, selalu aktif (24/7)

    // Cek hari (DateTime.weekday: 1=Senin, 7=Minggu)
    if (!daysOfWeek.contains(now.weekday)) return false;

    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;

    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } else {
      // Rentang melewati tengah malam (misal 22:00 - 04:00)
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  }
}

class GeofenceScheduleService {
  static final GeofenceScheduleService _instance = GeofenceScheduleService._internal();
  factory GeofenceScheduleService() => _instance;
  GeofenceScheduleService._internal();

  static const String _prefPrefix = 'geo_sched_';

  Future<GeofenceSchedule> getSchedule(String geofenceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefPrefix$geofenceId');
      if (raw != null) {
        return GeofenceSchedule.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return GeofenceSchedule(geofenceId: geofenceId);
  }

  Future<void> saveSchedule(GeofenceSchedule schedule) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefPrefix${schedule.geofenceId}', jsonEncode(schedule.toMap()));
    } catch (_) {}
  }

  Future<bool> isGeofenceActiveNow(String geofenceId) async {
    final schedule = await getSchedule(geofenceId);
    return schedule.isCurrentlyActive(DateTime.now());
  }
}
