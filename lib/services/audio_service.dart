import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'supabase_service.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final SupabaseService _supa = SupabaseService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  RealtimeChannel? _subscription;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Mendapatkan direktori penyimpanan rekaman permanen di perangkat pengguna
  Future<Directory> getRecordingsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/ambient_recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return recordingsDir;
  }

  /// Otomatis menghapus file rekaman lokal yang usianya lebih dari 7 hari (seminggu)
  Future<void> cleanOldRecordings({Duration maxAge = const Duration(days: 7)}) async {
    try {
      final recordingsDir = await getRecordingsDirectory();
      if (!await recordingsDir.exists()) return;

      final now = DateTime.now();
      final entities = recordingsDir.listSync();

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.m4a')) {
          try {
            final stat = await entity.stat();
            final age = now.difference(stat.modified);
            if (age > maxAge) {
              await entity.delete();
              debugPrint('[AudioService] Menghapus rekaman lama (>7 hari): ${entity.path}');
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[AudioService] Gagal membersihkan rekaman lama: $e');
    }
  }

  /// Mengambil daftar semua file rekaman lokal yang tersimpan di perangkat
  Future<List<File>> getLocalRecordings() async {
    try {
      final dir = await getRecordingsDirectory();
      if (!await dir.exists()) return [];
      final list = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.m4a')).toList();
      list.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return list;
    } catch (_) {
      return [];
    }
  }

  void startListeningForRequests() {
    _subscription?.unsubscribe();

    // Pembersihan otomatis rekaman lokal lama (>7 hari) saat inisialisasi
    cleanOldRecordings();

    _subscription = _supa.subscribeToMyAudioRequests((request) async {
      // Ignore if requester is self (handled directly by executeSelfTestRecording)
      if (request.requesterId == _supa.currentUser?.id) {
        return;
      }
      debugPrint('[AudioService] Incoming audio request: ${request.id} for ${request.durationSeconds}s');
      await _handleIncomingRequest(request);
    });
    debugPrint('[AudioService] Listening for ambient audio requests');
  }

  void stopListening() {
    _subscription?.unsubscribe();
    _subscription = null;
  }

  Future<void> _handleIncomingRequest(AudioRequestModel request) async {
    if (_isRecording) {
      debugPrint('[AudioService] Already recording, skipping request ${request.id}');
      return;
    }

    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) {
        debugPrint('[AudioService] Microphone permission not granted');
        await _supa.updateAudioRequest(request.id, status: 'failed');
        return;
      }

      _isRecording = true;
      await _supa.updateAudioRequest(request.id, status: 'recording');

      final recordingsDir = await getRecordingsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${recordingsDir.path}/ambient_${request.id}_$timestamp.m4a';

      // Start recording silently in background
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      // Record for durationSeconds
      await Future.delayed(Duration(seconds: request.durationSeconds));

      final outputPath = await _audioRecorder.stop();
      _isRecording = false;

      final recordedFile = File(outputPath ?? filePath);
      if (await recordedFile.exists() && await recordedFile.length() > 0) {
        final storagePath = 'recordings/${request.id}.m4a';
        final audioUrl = await _supa.uploadAudioFile(recordedFile.path, storagePath);

        await _supa.updateAudioRequest(
          request.id,
          status: 'completed',
          audioUrl: audioUrl,
        );
        debugPrint('[AudioService] Audio uploaded successfully: $audioUrl (Tersimpan lokal di: ${recordedFile.path})');

        // Bersihkan rekaman lokal yang usianya lebih dari 7 hari
        cleanOldRecordings();
      } else {
        await _supa.updateAudioRequest(request.id, status: 'failed');
      }
    } catch (e, stack) {
      _isRecording = false;
      debugPrint('[AudioService] Error processing audio request: $e\n$stack');
      try {
        await _supa.updateAudioRequest(request.id, status: 'failed');
      } catch (_) {}
    }
  }

  Future<AudioRequestModel?> executeSelfTestRecording({
    int durationSeconds = 10,
    String? circleId,
    void Function(int remainingSeconds)? onProgress,
  }) async {
    final uid = _supa.currentUser?.id;
    if (uid == null) return null;

    if (_isRecording) {
      debugPrint('[AudioService] Already recording');
      return null;
    }

    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) {
      debugPrint('[AudioService] Microphone permission not granted');
      return null;
    }

    _isRecording = true;
    final recordingsDir = await getRecordingsDirectory();
    final fileName = 'selftest_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final filePath = '${recordingsDir.path}/$fileName';

    AudioRequestModel? req;
    try {
      req = await _supa.createAudioRequest(
        targetUserId: uid,
        circleId: circleId,
        durationSeconds: durationSeconds,
      );
      await _supa.updateAudioRequest(req.id, status: 'recording');

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      for (int i = durationSeconds; i > 0; i--) {
        onProgress?.call(i);
        await Future.delayed(const Duration(seconds: 1));
      }
      onProgress?.call(0);

      final outputPath = await _audioRecorder.stop();
      _isRecording = false;

      final recordedFile = File(outputPath ?? filePath);
      if (await recordedFile.exists() && await recordedFile.length() > 0) {
        String audioUrl = recordedFile.path;
        try {
          final storagePath = 'recordings/${req.id}.m4a';
          audioUrl = await _supa.uploadAudioFile(recordedFile.path, storagePath);
        } catch (e) {
          debugPrint('[AudioService] Storage upload fallback: $e');
        }

        await _supa.updateAudioRequest(
          req.id,
          status: 'completed',
          audioUrl: audioUrl,
        );

        // Bersihkan rekaman lokal yang usianya lebih dari 7 hari
        cleanOldRecordings();

        return req.copyWith(
          status: 'completed',
          audioUrl: audioUrl,
        );
      } else {
        await _supa.updateAudioRequest(req.id, status: 'failed');
      }
    } catch (e, stack) {
      _isRecording = false;
      debugPrint('[AudioService] Error during self-test recording: $e\n$stack');
      if (req != null) {
        try {
          await _supa.updateAudioRequest(req.id, status: 'failed');
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> dispose() async {
    stopListening();
    await _audioRecorder.dispose();
  }
}
