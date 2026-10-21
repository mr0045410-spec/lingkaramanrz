import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import 'phone_protection_service.dart';
import 'supabase_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static const MethodChannel _gpsChannel = MethodChannel('com.lingkaraman.lingkar_aman/gps_status');

  final Battery _battery = Battery();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  Timer? _periodicTimer;

  final StreamController<Position> _positionStreamController = StreamController<Position>.broadcast();
  Stream<Position> get onPositionChanged => _positionStreamController.stream;

  final StreamController<bool> _gpsStatusController = StreamController<bool>.broadcast();
  Stream<bool> get onGpsStatusChanged => _gpsStatusController.stream;

  bool _isGpsEnabled = true;
  bool get isGpsEnabled => _isGpsEnabled;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  int _batteryLevel = 100;
  int get batteryLevel => _batteryLevel;

  /// Memulai pemantauan status GPS/Layanan Lokasi secara real-time.
  void startGpsListener() {
    _serviceStatusSubscription?.cancel();
    checkGpsStatus();

    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
      final isEnabled = (status == ServiceStatus.enabled);
      _updateGpsStatus(isEnabled);
    });
  }

  /// Memeriksa status GPS saat ini.
  Future<bool> checkGpsStatus() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      _updateGpsStatus(isEnabled);
      return isEnabled;
    } catch (_) {
      return true;
    }
  }

  void _updateGpsStatus(bool isEnabled) {
    if (_isGpsEnabled == isEnabled) return;
    _isGpsEnabled = isEnabled;
    _gpsStatusController.add(isEnabled);

    // Kirim notifikasi status bar jika GPS mati, atau batalkan jika sudah aktif
    if (!isEnabled) {
      try {
        _gpsChannel.invokeMethod('showGpsNotification');
      } catch (_) {}
    } else {
      try {
        _gpsChannel.invokeMethod('cancelGpsNotification');
      } catch (_) {}
      if (_isTracking) {
        _syncLocation();
      }
    }
  }

  /// Membuka layar Pengaturan Lokasi / GPS perangkat
  Future<void> openGpsSettings() async {
    try {
      await _gpsChannel.invokeMethod('openGpsSettings');
    } catch (_) {
      await Geolocator.openLocationSettings();
    }
  }

  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await checkGpsStatus();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return null;

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (_currentPosition != null) {
        _positionStreamController.add(_currentPosition!);
      }
      return _currentPosition;
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _currentPosition = last;
        _positionStreamController.add(last);
      }
      return _currentPosition;
    }
  }

  Future<void> startTracking({Duration interval = const Duration(seconds: 15)}) async {
    startGpsListener();

    if (_isTracking) return;
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return;

    _isTracking = true;

    // Initial update
    await _syncLocation();

    // Setup periodic sync
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => _syncLocation());

    // Setup continuous position stream dengan Foreground Service agar tembus Doze Mode saat layar mati
    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // meters
        forceLocationManager: false,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'LingkarAman Aktif Menjaga Anda',
          notificationText: 'Pelacakan lokasi & perlindungan anti-maling aktif di latar belakang',
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        _currentPosition = position;
        _positionStreamController.add(position);
      },
    );
  }

  Future<void> _syncLocation() async {
    try {
      final pos = await getCurrentLocation();
      if (pos == null) return;

      int bat = 100;
      bool charging = false;
      try {
        bat = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        charging = state == BatteryState.charging;
      } catch (_) {}

      _batteryLevel = bat;

      await SupabaseService().updateMyLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        batteryLevel: bat,
        isCharging: charging,
        speed: pos.speed,
      );

      // Simpan koordinat terakhir & kredensial ke SharedPreferences untuk Native Service (SosPowerService & SosTileService)
      await _saveNativePreferences(pos.latitude, pos.longitude);

      await PhoneProtectionService().checkBatteryAndTriggerLastBreath(
        lat: pos.latitude,
        lng: pos.longitude,
        batteryLevel: bat,
        isCharging: charging,
      );
    } catch (_) {}
  }

  Future<void> _saveNativePreferences(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_lat', lat);
      await prefs.setDouble('last_lng', lng);
      await prefs.setString('last_lat_str', lat.toString());
      await prefs.setString('last_lng_str', lng.toString());
      await prefs.setString('supabase_url', AppConstants.supabaseUrl);
      await prefs.setString('supabase_anon_key', AppConstants.supabaseAnonKey);

      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null && token.isNotEmpty) {
        // Obfuskasi token agar tidak tersimpan plaintext JWT di SharedPreferences (SEC-11 / B3)
        final encodedToken = 'sec_v1:${base64Url.encode(utf8.encode(token).reversed.toList())}';
        await prefs.setString('access_token', encodedToken);
      }

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null && uid.isNotEmpty) {
        await prefs.setString('user_id', uid);
      }

      var activeCircleId = prefs.getString('active_circle_id');
      if (activeCircleId == null || activeCircleId.isEmpty) {
        final circles = await SupabaseService().getMyCircles();
        if (circles.isNotEmpty) {
          activeCircleId = circles.first.id;
          await prefs.setString('active_circle_id', activeCircleId);
        }
      }
    } catch (e) {
      debugPrint('[LocationService] _saveNativePreferences error: $e');
    }
  }

  void stopTracking() {
    _isTracking = false;
    _positionSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _periodicTimer?.cancel();
    try {
      _gpsChannel.invokeMethod('cancelGpsNotification');
    } catch (_) {}
  }
}
