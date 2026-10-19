import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'supabase_service.dart';

class AppUsageService {
  static final AppUsageService _instance = AppUsageService._internal();
  factory AppUsageService() => _instance;
  AppUsageService._internal();

  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/app_usage');
  final SupabaseService _supa = SupabaseService();

  Future<bool> hasUsagePermission() async {
    try {
      final hasPerm = await _channel.invokeMethod<bool>('hasUsagePermission');
      return hasPerm ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod('openUsageSettings');
    } catch (e) {
      debugPrint('Error opening usage settings: $e');
    }
  }

  Future<List<AppUsageModel>> getTodayLocalUsage() async {
    try {
      final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getTodayAppUsage');
      if (result == null) return [];

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final currentUid = _supa.currentUser?.id ?? 'local';

      return result.map((m) {
        final lastUsedMillis = m['lastTimeUsed'] as num?;
        return AppUsageModel(
          id: '',
          userId: currentUid,
          packageName: m['packageName'] as String,
          appName: m['appName'] as String,
          totalTimeForegroundSeconds: (m['totalTimeSeconds'] as num?)?.toInt() ?? 0,
          lastTimeUsed: lastUsedMillis != null && lastUsedMillis > 0
              ? DateTime.fromMillisecondsSinceEpoch(lastUsedMillis.toInt())
              : null,
          reportDate: todayStr,
          updatedAt: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting local app usage: $e');
      return [];
    }
  }

  Future<void> syncTodayAppUsage() async {
    final uid = _supa.currentUser?.id;
    if (uid == null) return;

    final hasPerm = await hasUsagePermission();
    if (!hasPerm) return;

    final localUsage = await getTodayLocalUsage();
    if (localUsage.isEmpty) return;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (var app in localUsage) {
      try {
        await _supa.client.from('app_usage_reports').upsert({
          'user_id': uid,
          'package_name': app.packageName,
          'app_name': app.appName,
          'total_time_foreground_seconds': app.totalTimeForegroundSeconds,
          'last_time_used': app.lastTimeUsed?.toIso8601String(),
          'report_date': todayStr,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,package_name,report_date');
      } catch (e) {
        debugPrint('Error syncing app usage for ${app.packageName}: $e');
      }
    }
  }

  Future<List<AppUsageModel>> getMemberUsage(String userId, [DateTime? date]) async {
    final targetDateStr = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());

    try {
      final data = await _supa.client
          .from('app_usage_reports')
          .select()
          .eq('user_id', userId)
          .eq('report_date', targetDateStr)
          .order('total_time_foreground_seconds', ascending: false);

      return (data as List).map((d) => AppUsageModel.fromMap(d)).toList();
    } catch (e) {
      debugPrint('Error fetching member app usage: $e');
      return [];
    }
  }
}
