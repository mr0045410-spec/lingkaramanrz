import 'package:flutter/services.dart';

class OemDeviceInfo {
  final String manufacturer;
  final String brandDisplayName;
  final bool isKnownVendor;

  const OemDeviceInfo({
    required this.manufacturer,
    required this.brandDisplayName,
    required this.isKnownVendor,
  });

  factory OemDeviceInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const OemDeviceInfo(
        manufacturer: 'android',
        brandDisplayName: 'Android Device',
        isKnownVendor: false,
      );
    }
    return OemDeviceInfo(
      manufacturer: map['manufacturer'] as String? ?? 'android',
      brandDisplayName: map['brandDisplayName'] as String? ?? 'Android Device',
      isKnownVendor: map['isKnownVendor'] as bool? ?? false,
    );
  }
}

class OemSecurityService {
  static final OemSecurityService instance = OemSecurityService();
  static const MethodChannel _channel = MethodChannel('com.lingkaraman.lingkar_aman/oem_security');

  Future<OemDeviceInfo> getDeviceInfo() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
      return OemDeviceInfo.fromMap(res);
    } catch (_) {
      return const OemDeviceInfo(
        manufacturer: 'android',
        brandDisplayName: 'Android Device',
        isKnownVendor: false,
      );
    }
  }

  Future<bool> openAutostartSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openAutostartSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAccessibilitySettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openAccessibilitySettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
