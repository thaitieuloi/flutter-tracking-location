import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../models/models.dart';

/// Service for managing device location.
/// This service is independent of the backend (Supabase/Firebase).
class LocationService {
  StreamSubscription<Position>? _positionStream;

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
      );
    } catch (e) {
      print('Error getting location: $e');
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
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return '${place.street}, ${place.subLocality}, ${place.locality}';
      }
    } catch (e) {
      print('Error getting address: $e');
    }
    return null;
  }

  /// Create a position stream with distance filter.
  Stream<Position> trackLocation() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update when moved 10m
    );

    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
  }

  /// Start continuous location tracking.
  void startTracking(Function(UserLocation) onLocationUpdate, String userId) {
    _positionStream = trackLocation().listen((Position position) async {
      String? address = await getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      UserLocation location = UserLocation(
        userId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now().toUtc(),
        accuracy: position.accuracy,
        address: address,
      );

      onLocationUpdate(location);
    });
  }

  /// Stop location tracking.
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
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
