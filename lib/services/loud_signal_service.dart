import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'supabase_service.dart';

class LoudSignalService {
  static final LoudSignalService _instance = LoudSignalService._internal();
  factory LoudSignalService() => _instance;
  LoudSignalService._internal();

  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/loud_signal');
  final SupabaseService _supa = SupabaseService();

  RealtimeChannel? _subscription;
  final StreamController<LoudSignalModel> _incomingSignalController = StreamController<LoudSignalModel>.broadcast();
  Stream<LoudSignalModel> get onIncomingSignal => _incomingSignalController.stream;

  final StreamController<String> _signalStoppedController = StreamController<String>.broadcast();
  Stream<String> get onSignalStopped => _signalStoppedController.stream;

  LoudSignalModel? _activeRingingSignal;
  LoudSignalModel? get activeRingingSignal => _activeRingingSignal;

  bool _isListening = false;

  void startListening() {
    if (_isListening) return;
    final currentUserId = _supa.currentUser?.id;
    if (currentUserId == null) return;

    _isListening = true;

    _subscription = _supa.client
        .channel('public:loud_signals:$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'loud_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'target_user_id',
            value: currentUserId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isEmpty) return;

            final signal = LoudSignalModel.fromMap(newRecord);

            if (signal.status == 'pending') {
              _activeRingingSignal = signal;
              // Mark as ringing in db
              try {
                await _supa.client.from('loud_signals').update({
                  'status': 'ringing',
                }).eq('id', signal.id);
              } catch (_) {}

              // Play native loud alarm bypassing DND
              await playNativeAlarm();
              _incomingSignalController.add(signal);
            } else if (signal.status == 'stopped') {
              if (_activeRingingSignal?.id == signal.id) {
                _activeRingingSignal = null;
                await stopNativeAlarm();
                _signalStoppedController.add(signal.id);
              }
            }
          },
        )
        .subscribe();
  }

  void stopListening() {
    _subscription?.unsubscribe();
    _subscription = null;
    _isListening = false;
  }

  Future<LoudSignalModel> sendLoudSignal({
    required String targetUserId,
    String? circleId,
  }) async {
    final uid = _supa.currentUser?.id;
    if (uid == null) throw Exception('Belum login');

    final data = await _supa.client
        .from('loud_signals')
        .insert({
          'sender_id': uid,
          'target_user_id': targetUserId,
          'circle_id': circleId,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return LoudSignalModel.fromMap(data);
  }

  Future<void> stopLoudSignal(String signalId) async {
    await _supa.client.from('loud_signals').update({
      'status': 'stopped',
      'stopped_at': DateTime.now().toIso8601String(),
    }).eq('id', signalId);

    if (_activeRingingSignal?.id == signalId) {
      _activeRingingSignal = null;
      await stopNativeAlarm();
    }
  }

  Future<void> stopCurrentRingingSignal() async {
    final active = _activeRingingSignal;
    if (active != null) {
      await stopLoudSignal(active.id);
    } else {
      await stopNativeAlarm();
    }
  }

  Future<void> playNativeAlarm() async {
    try {
      await _channel.invokeMethod('playLoudAlarm');
    } catch (e) {
      debugPrint('Error playing native loud alarm: $e');
    }
  }

  Future<void> stopNativeAlarm() async {
    try {
      await _channel.invokeMethod('stopLoudAlarm');
    } catch (e) {
      debugPrint('Error stopping native loud alarm: $e');
    }
  }
}
