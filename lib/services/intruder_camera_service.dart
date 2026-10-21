import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IntruderCameraService {
  static final IntruderCameraService _instance = IntruderCameraService._internal();
  factory IntruderCameraService() => _instance;
  IntruderCameraService._internal();

  bool _isCapturing = false;

  bool get isCapturing => _isCapturing;

  /// Captures a silent photo from the front camera when intruder enters wrong PIN.
  /// Returns public URL from Supabase Storage if uploaded, or local file path if offline.
  Future<String?> captureIntruderSelfie({String? userId}) async {
    if (_isCapturing) {
      debugPrint('[IntruderCameraService] Capture already in progress, skipping.');
      return null;
    }

    _isCapturing = true;
    CameraController? controller;

    try {
      // 1. Request camera permission if not granted
      final status = await Permission.camera.request();
      if (!status.isGranted && !status.isLimited) {
        debugPrint('[IntruderCameraService] Camera permission not granted: $status');
        return null;
      }

      // 2. Locate available cameras on device
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('[IntruderCameraService] No cameras found on device');
        return null;
      }

      // 3. Prioritize front-facing selfie camera
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // 4. Initialize camera controller silently without audio shutter
      controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      // Brief delay for sensor exposure / focus to stabilize
      await Future.delayed(const Duration(milliseconds: 300));

      // 5. Take silent snapshot
      final XFile picture = await controller.takePicture();
      final File imageFile = File(picture.path);

      debugPrint('[IntruderCameraService] Captured intruder photo at: ${imageFile.path}');

      // 6. Save permanent local copy in App Documents
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final localTarget = File('${appDir.path}/intruder_$timestamp.jpg');
      await imageFile.copy(localTarget.path);

      final effectiveUid = userId ?? Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
      // 7. Upload to Supabase Storage bucket 'ambient_audio' pada folder '<uid>/intruder_photos/intruder_$timestamp.jpg' (SEC-02)
      final storagePath = '$effectiveUid/intruder_photos/intruder_$timestamp.jpg';

      String? publicUrl;
      try {
        final bytes = await localTarget.readAsBytes();
        
        await Supabase.instance.client.storage
            .from('ambient_audio')
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        publicUrl = Supabase.instance.client.storage
            .from('ambient_audio')
            .getPublicUrl(storagePath);

        debugPrint('[IntruderCameraService] Successfully uploaded intruder selfie: $publicUrl');
      } catch (uploadError) {
        debugPrint('[IntruderCameraService] Upload failed (offline), using local path: $uploadError');
        publicUrl = localTarget.path;
      }

      return publicUrl;
    } catch (e, stack) {
      debugPrint('[IntruderCameraService] Error capturing intruder photo: $e\n$stack');
      return null;
    } finally {
      _isCapturing = false;
      try {
        await controller?.dispose();
      } catch (_) {}
    }
  }
}
