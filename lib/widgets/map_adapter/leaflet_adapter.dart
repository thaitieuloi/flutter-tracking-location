import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_adapter.dart';

class LeafletMapWidget extends StatefulWidget implements AppMapWidget {
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

  const LeafletMapWidget({
    Key? key,
    required this.initialCenter,
    this.initialZoom = 12,
    this.markers = const [],
    this.circles = const [],
    this.onMapCreated,
  }) : super(key: key);

  @override
  State<LeafletMapWidget> createState() => _LeafletMapWidgetState();
}

class _LeafletMapWidgetState extends State<LeafletMapWidget> implements AppMapController {
  final MapController _innerController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMapCreated?.call(this);
    });
  }

  @override
  void moveTo(AppLatLng location, {double zoom = 14}) {
    _innerController.move(
      LatLng(location.latitude, location.longitude),
      zoom,
    );
  }

  @override
  void dispose() {
    _innerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FlutterMap(
      mapController: _innerController,
      options: MapOptions(
        initialCenter: LatLng(widget.initialCenter.latitude, widget.initialCenter.longitude),
        initialZoom: widget.initialZoom,
      ),
      children: [
        // Tile Layer
        TileLayer(
          urlTemplate: isDark
              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
              : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: RetinaMode.isHighDensity(context),
        ),

        // Safe Zones
        CircleLayer(
          circles: widget.circles.map((c) => CircleMarker(
            point: LatLng(c.center.latitude, c.center.longitude),
            radius: c.radiusMeters,
            useRadiusInMeter: true,
            color: c.color,
            borderColor: c.borderColor,
            borderStrokeWidth: c.borderWidth,
          )).toList(),
        ),

        // Markers
        MarkerLayer(
          markers: widget.markers.map((m) => Marker(
            point: LatLng(m.position.latitude, m.position.longitude),
            width: 80,
            height: 80,
            child: m.child,
          )).toList(),
        ),
      ],
    );
  }
}
