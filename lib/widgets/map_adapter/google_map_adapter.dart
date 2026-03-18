/* 
IMPORT: google_maps_flutter: ^2.5.0 in pubspec.yaml if you want to use this again.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_adapter.dart';

class GoogleMapAdapterWidget extends StatefulWidget implements AppMapWidget {
  @override
  final AppLatLng initialCenter;
  @override
  final double initialZoom;
  @override
  final List<AppMapMarker> markers;
  @override
  final List<AppMapCircle> circles;
  @override
  final Function(AppMapController controller)? onMapCreated;

  const GoogleMapAdapterWidget({
    Key? key,
    required this.initialCenter,
    this.initialZoom = 12,
    this.markers = const [],
    this.circles = const [],
    this.onMapCreated,
  }) : super(key: key);

  @override
  State<GoogleMapAdapterWidget> createState() => _GoogleMapAdapterWidgetState();
}

class _GoogleMapAdapterWidgetState extends State<GoogleMapAdapterWidget> implements AppMapController {
  GoogleMapController? _innerController;

  @override
  void moveTo(AppLatLng location, {double zoom = 14}) {
    _innerController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(location.latitude, location.longitude),
        zoom,
      ),
    );
  }

  @override
  void dispose() {
    _innerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      onMapCreated: (controller) {
        _innerController = controller;
        widget.onMapCreated?.call(this);
      },
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initialCenter.latitude, widget.initialCenter.longitude),
        zoom: widget.initialZoom,
      ),
      markers: widget.markers.map((m) => Marker(
        markerId: MarkerId(m.id),
        position: LatLng(m.position.latitude, m.position.longitude),
        // Note: Google Maps Markers are more limited in custom widgets 
        // than Leaflet, usually requiring BitmapDescriptor.
      )).toSet(),
      circles: widget.circles.map((c) => Circle(
        circleId: CircleId(c.id),
        center: LatLng(c.center.latitude, c.center.longitude),
        radius: c.radiusMeters,
        fillColor: c.color,
        strokeColor: c.borderColor,
        strokeWidth: c.borderWidth.toInt(),
      )).toSet(),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
    );
  }
}
*/
