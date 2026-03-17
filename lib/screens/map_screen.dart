import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final location = await provider.getCurrentLocation();

    if (location != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          14,
        ),
      );
    }
  }

  void _updateMarkers(AppProvider provider) {
    _markers.clear();
    _circles.clear();

    // Add markers for family members
    for (var member in provider.familyMembers) {
      final location = provider.memberLocations[member.id];

      if (location != null && member.isLocationSharing) {
        final isCurrentUser = member.id == provider.currentUser?.id;

        _markers.add(
          Marker(
            markerId: MarkerId(member.id),
            position: LatLng(location.latitude, location.longitude),
            infoWindow: InfoWindow(
              title: member.name,
              snippet: location.address ?? 'Đang cập nhật...',
            ),
            icon: isCurrentUser
                ? BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueBlue)
                : BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed),
          ),
        );
      }
    }

    // Add circles & markers for safe zones
    for (var zone in provider.safeZones) {
      _circles.add(
        Circle(
          circleId: CircleId(zone.id),
          center: LatLng(zone.latitude, zone.longitude),
          radius: zone.radiusMeters,
          fillColor: Colors.blue.withValues(alpha: 0.15),
          strokeColor: Colors.blue.shade400,
          strokeWidth: 2,
        ),
      );

      _markers.add(
        Marker(
          markerId: MarkerId('zone_${zone.id}'),
          position: LatLng(zone.latitude, zone.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: zone.name,
            snippet: '${zone.radiusMeters.toInt()}m',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bản đồ gia đình',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          // Location sharing toggle
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              return IconButton(
                icon: Icon(
                  provider.isLocationSharing
                      ? Icons.location_on
                      : Icons.location_off_outlined,
                ),
                tooltip: provider.isLocationSharing
                    ? 'Tắt chia sẻ vị trí'
                    : 'Bật chia sẻ vị trí',
                onPressed: () async {
                  if (provider.isLocationSharing) {
                    await provider.stopLocationSharing();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã tắt chia sẻ vị trí'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } else {
                    await provider.startLocationSharing();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã bật chia sẻ vị trí'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              );
            },
          ),

          // Center on current location
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Vị trí của tôi',
            onPressed: () async {
              final provider =
                  Provider.of<AppProvider>(context, listen: false);
              final location = await provider.getCurrentLocation();

              if (location != null && _mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(location.latitude, location.longitude),
                    16,
                  ),
                );
              }
            },
          ),

          // Sign out
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'signout') {
                final provider =
                    Provider.of<AppProvider>(context, listen: false);
                await provider.signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Đăng xuất'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          _updateMarkers(provider);

          return GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _loadInitialLocation();
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(10.8231, 106.6297), // Ho Chi Minh City
              zoom: 12,
            ),
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Add safe zone
          FloatingActionButton.small(
            heroTag: 'add_zone',
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
            child: const Icon(Icons.add_location_alt),
            onPressed: () => _showAddSafeZoneDialog(),
          ),
          const SizedBox(height: 12),

          // Show family members
          FloatingActionButton(
            heroTag: 'family',
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: const Icon(Icons.people),
            onPressed: () => _showFamilyMembersSheet(),
          ),
        ],
      ),
    );
  }

  void _showAddSafeZoneDialog() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final location = await provider.getCurrentLocation();

    if (location == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể lấy vị trí hiện tại'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '200');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo vùng an toàn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Tên vùng (VD: Nhà, Trường)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: radiusController,
              decoration: InputDecoration(
                labelText: 'Bán kính (mét)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;

              final zone = SafeZone(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameController.text,
                latitude: location.latitude,
                longitude: location.longitude,
                radiusMeters:
                    double.tryParse(radiusController.text) ?? 200,
                familyId: provider.currentUser!.familyId,
              );

              await provider.createSafeZone(zone);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã tạo vùng an toàn'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  void _showFamilyMembersSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Consumer<AppProvider>(
          builder: (context, provider, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Thành viên gia đình',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton.filled(
                        icon: const Icon(Icons.person_add, size: 20),
                        onPressed: () => _showAddMemberDialog(),
                      ),
                    ],
                  ),
                  const Divider(),

                  // Members list
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: provider.familyMembers.length,
                      itemBuilder: (context, index) {
                        final member = provider.familyMembers[index];
                        final location =
                            provider.memberLocations[member.id];
                        final isOnline = member.isLocationSharing;

                        return Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isOnline
                                      ? colorScheme.primaryContainer
                                      : colorScheme.surfaceContainerHighest,
                                  child: Text(
                                    member.name.isNotEmpty
                                        ? member.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: isOnline
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isOnline)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colorScheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              member.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              location?.address ??
                                  (isOnline
                                      ? 'Đang cập nhật...'
                                      : 'Chưa chia sẻ vị trí'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isOnline && location != null
                                ? IconButton(
                                    icon: const Icon(
                                        Icons.location_searching),
                                    onPressed: () {
                                      _mapController?.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                          LatLng(
                                            location.latitude,
                                            location.longitude,
                                          ),
                                          16,
                                        ),
                                      );
                                      Navigator.pop(context);
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAddMemberDialog() {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm thành viên'),
        content: TextField(
          controller: emailController,
          decoration: InputDecoration(
            labelText: 'Email thành viên',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final provider =
                  Provider.of<AppProvider>(context, listen: false);
              final success = await provider.addFamilyMember(
                emailController.text.trim(),
              );

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Đã thêm thành viên'
                          : 'Không tìm thấy người dùng',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
