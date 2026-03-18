import 'package:flutter/material.dart';

/// Define a common coordinate class to avoid dependency on specific map packages in the UI.
class AppLatLng {
  final double latitude;
  final double longitude;
  const AppLatLng(this.latitude, this.longitude);
}

/// Interface for map markers.
class AppMapMarker {
  final String id;
  final AppLatLng position;
  final Widget child;
  final VoidCallback? onTap;

  AppMapMarker({
    required this.id,
    required this.position,
    required this.child,
    this.onTap,
  });
}

/// Interface for map circles (Safe Zones).
class AppMapCircle {
  final String id;
  final AppLatLng center;
  final double radiusMeters;
  final Color color;
  final Color borderColor;
  final double borderWidth;

  AppMapCircle({
    required this.id,
    required this.center,
    required this.radiusMeters,
    this.color = const Color(0x332196F3),
    this.borderColor = const Color(0xFF2196F3),
    this.borderWidth = 2.0,
  });
}

/// Controller interface to interact with the map.
abstract class AppMapController {
  void moveTo(AppLatLng location, {double zoom = 14});
  void dispose();
}

/// The main Map Widget interface.
abstract class AppMapWidget extends StatefulWidget {
  final AppLatLng initialCenter;
  final double initialZoom;
  final List<AppMapMarker> markers;
  final List<AppMapCircle> circles;
  final Function(AppMapController controller)? onMapCreated;

  const AppMapWidget({
    Key? key,
    required this.initialCenter,
    this.initialZoom = 12,
    this.markers = const [],
    this.circles = const [],
    this.onMapCreated,
  }) : super(key: key);
}
