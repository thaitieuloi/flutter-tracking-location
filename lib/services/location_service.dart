import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../models/models.dart';

/// Service for managing device location.
/// This service is independent of the backend (Supabase/Firebase).
class LocationService {
  StreamSubscription<Position>? _positionStream;
  Timer? _periodicTimer;

  /// Check and request location permissions.
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

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
  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 5));

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
    } on TimeoutException {
      return null;
    } catch (e) {
      print('LocationService: Error getting address: $e');
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

    // 2. Periodic timer – gửi định kỳ mỗi [periodicSeconds] giây
    _periodicTimer = Timer.periodic(Duration(seconds: periodicSeconds), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          forceAndroidLocationManager: true,
        );
        final location = await _positionToUserLocation(position, userId);
        onLocationUpdate(location);
        print('📍 [LocationService] Periodic heartbeat sent: ${position.latitude}, ${position.longitude}');
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

    return UserLocation(
      userId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now().toUtc(),
      accuracy: position.accuracy,
      address: address,
    );
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