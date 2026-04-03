import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/models.dart';

/// Service for managing device location.
/// This service is independent of the backend (Supabase/Firebase).
class LocationService {
  StreamSubscription<Position>? _positionStream;
  Timer? _periodicTimer;
  Position? _lastSentPosition;
  DateTime? _lastSentTime;
  final Battery _battery = Battery();

  /// Check and request location permissions.
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // Request Notification permission for Android 13+
    await Permission.notification.request();

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // Proactively request background permission if only 'whileInUse' is granted
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always) {
        // Log it, but technically whileInUse + foreground notification works
        // however 'always' is far more reliable
        print('LocationService: Always permission NOT granted, but will attempt with foreground service');
      }
    }

    return true;
  }

  /// Get current device position.
  Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      );
    } catch (e) {
      print('LocationService: Error getting location: $e');
      return null;
    }
  }

  /// Reverse geocode coordinates to a human-readable address.
  /// Uses Nominatim (OSM) as primary source, matching web implementation.
  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      // 1. Try Nominatim (Primary - same as web)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&accept-language=vi&addressdetails=1&extratags=1&namedetails=1&zoom=18',
      );

      final response = await http.get(
        url,
        headers: { 'User-Agent': 'FamilyTracker/1.0 (family-tracker-app)' },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final addr = data['address'] ?? {};

        final parts = <String>[];

        // 1. Specific point — priority: house number > POI name > named OSM feature (landmark)
        final extratags = data['extratags'] ?? {};
        final houseNum = addr['house_number'] ?? extratags['addr:housenumber'] ?? addr['building'];
        final poiName = addr['amenity'] ?? addr['shop'] ?? addr['office'] ?? addr['tourism'] ?? addr['leisure'] ?? addr['industrial'];
        // data['name'] is the matched OSM object name (e.g. "Trường THPT Hóc Môn")
        final osmName = data['name'] as String?;
        final effectiveOsmName = (osmName != null && osmName.isNotEmpty && osmName != addr['road']) ? osmName : null;

        String? point;
        if (houseNum != null && poiName != null) {
          point = '$houseNum, $poiName';
        } else if (houseNum != null) {
          point = houseNum as String;
        } else if (poiName != null) {
          point = poiName as String;
        } else if (effectiveOsmName != null) {
          point = 'Gần $effectiveOsmName';
        }
        if (point != null) parts.add(point);

        // 2. Road
        if (addr['road'] != null) parts.add(addr['road'] as String);

        // 3. Area (Suburb, Ward, etc.)
        final area = addr['suburb'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? addr['hamlet'] ?? addr['village'];
        if (area != null) parts.add(area as String);

        // 4. District/Town
        final district = addr['city_district'] ?? addr['town'] ?? addr['district'];
        if (district != null) parts.add(district as String);

        if (parts.isNotEmpty) {
          return parts.join(', ');
        }

        // Fallback to display_name formatting
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          return displayName.split(',').take(2).join(',').trim();
        }
      }
    } catch (e) {
      print('LocationService: Nominatim error: $e');
    }

    // 2. Fallback to native geocoding (Secondary)
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 3));

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        final components = [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
        ].where((c) => c != null && c.isNotEmpty).toList();
        return components.join(', ');
      }
    } catch (e) {
      print('LocationService: Native geocoding fallback error: $e');
    }
    
    return null;
  }

  /// Create a position stream with optimized settings.
  Stream<Position> trackLocation() {
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // update khi di chuyển >= 10m
      intervalDuration: const Duration(seconds: 15),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Family Tracker đang chạy nền",
        notificationTitle: "Chia sẻ vị trí đang bật",
        enableWakeLock: true,
      ),
    );

    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
  }

  /// Start continuous location tracking.
  /// - Stream-based: gửi khi di chuyển >= 10m
  /// - Timer-based: gửi định kỳ mỗi [periodicSeconds] giây dù không di chuyển
  void startTracking(
    Function(UserLocation) onLocationUpdate,
    String userId, {
    int periodicSeconds = 30,
  }) {
    // 🔥 Prevent multiple subscriptions (memory leak fix)
    stopTracking();

    // 1. Subscribe to position stream (khi di chuyển)
    _positionStream = trackLocation().listen((Position position) async {
      final location = await _positionToUserLocation(position, userId);
      onLocationUpdate(location);
    });

    // 2. Periodic timer – gửi định kỳ (Smart Heartbeat)
    _periodicTimer = Timer.periodic(Duration(seconds: periodicSeconds), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          forceAndroidLocationManager: true,
        );

        if (_shouldUpdate(position)) {
          final location = await _positionToUserLocation(position, userId);
          onLocationUpdate(location);
          _lastSentPosition = position;
          _lastSentTime = DateTime.now();
          print('📍 [LocationService] Heartbeat sent (Moved or Timeout): ${position.latitude}, ${position.longitude}');
        }
      } catch (e) {
        print('LocationService: Periodic update error: $e');
      }
    });

    print('✅ [LocationService] Tracking started (stream + periodic every ${periodicSeconds}s)');
  }

  Future<UserLocation> _positionToUserLocation(Position position, String userId) async {
    String? address = await getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    final batteryLevel = await _battery.batteryLevel;

    return UserLocation(
      userId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now().toUtc(),
      accuracy: position.accuracy,
      address: address,
      batteryLevel: batteryLevel,
    );
  }

  bool _shouldUpdate(Position current) {
    if (_lastSentPosition == null || _lastSentTime == null) return true;

    final distance = Geolocator.distanceBetween(
      _lastSentPosition!.latitude,
      _lastSentPosition!.longitude,
      current.latitude,
      current.longitude,
    );

    final timeDiff = DateTime.now().difference(_lastSentTime!).inSeconds;

    // Thuật toán: 
    // - Nếu di chuyển > 30m thì gửi.
    // - Nếu đứng yên nhưng quá 5 phút (300s) thì gửi 1 lần để báo vẫn online.
    if (distance > 30) return true;
    if (timeDiff > 300) return true;

    return false;
  }

  /// Stop location tracking.
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    print('🛑 [LocationService] Tracking stopped');
  }

  /// Calculate distance between two points in meters.
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Check if a user is within a safe zone.
  bool isInSafeZone(
    double userLat,
    double userLon,
    SafeZone zone,
  ) {
    double distance = calculateDistance(
      userLat,
      userLon,
      zone.latitude,
      zone.longitude,
    );
    return distance <= zone.radiusMeters;
  }
}