import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../widgets/map_adapter/map_adapter.dart';
import '../widgets/map_adapter/leaflet_adapter.dart';
import 'location_history_screen.dart';
import 'notifications_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  AppMapController? _mapController;

  // Custom marker colors
  static const Color _currentUserColor = Color(0xFF1A73E8);
  static const Color _familyMemberColor = Color(0xFFE53935);
  static const Color _safeZoneColor = Color(0xFF43A047);

  // Pulse animation for current user marker
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialLocation() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final location = await provider.getCurrentLocation();
    if (location != null && _mapController != null) {
      _mapController!.moveTo(AppLatLng(location.latitude, location.longitude), zoom: 14);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Consumer<AppProvider>(
          builder: (context, provider, _) => GestureDetector(
            onTap: _showFamilyMembersSheet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.familyName.isEmpty ? 'Together Home' : provider.familyName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (provider.familyMembers.isNotEmpty)
                  Text(
                    '${provider.familyMembers.length} thành viên',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          _buildNotificationBadge(),
          _buildMyPositionButton(),
          _buildMoreMenu(),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          return Stack(
            children: [
              LeafletMapWidget(
                initialCenter: const AppLatLng(10.8231, 106.6297),
                initialZoom: 12,
                onMapCreated: (controller) {
                  _mapController = controller;
                  _loadInitialLocation();
                },
                circles: _buildCircles(provider),
                markers: _buildMarkers(provider),
              ),
              // Invite code banner at top
              if (provider.inviteCode != null)
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: _buildInviteCodeBanner(provider.inviteCode!, colorScheme),
                ),
              // SOS button at bottom-left
              Positioned(
                bottom: 24,
                left: 16,
                child: _buildSosButton(colorScheme),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _buildFab(colorScheme),
    );
  }

  // ── Invite Code Banner ───────────────────────────────────

  Widget _buildInviteCodeBanner(String code, ColorScheme colorScheme) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.primaryContainer),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Mã: $code', 
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Đã copy mã gia đình!'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 16, color: colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SOS Button ───────────────────────────────────────────

  Widget _buildSosButton(ColorScheme colorScheme) {
    return GestureDetector(
      onLongPress: () => _handleSos(),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sos, color: Colors.white, size: 24),
            Text('Giữ', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sos, color: Colors.red, size: 48),
        title: const Text('Gửi SOS?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Tín hiệu SOS sẽ được gửi đến tất cả thành viên gia đình kèm vị trí hiện tại của bạn.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('GỬI SOS'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final ok = await provider.sendSos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? '🚨 SOS đã được gửi!' : '❌ Không thể gửi SOS'),
          backgroundColor: ok ? Colors.red : Colors.grey,
        ));
      }
    }
  }

  // ── Map Elements Builders ────────────────────────────────

  List<AppMapCircle> _buildCircles(AppProvider provider) {
    return provider.safeZones.map((zone) {
      return AppMapCircle(
        id: zone.id,
        center: AppLatLng(zone.latitude, zone.longitude),
        radiusMeters: zone.radiusMeters,
        color: _safeZoneColor.withOpacity(0.15),
        borderColor: _safeZoneColor.withOpacity(0.6),
      );
    }).toList();
  }

  List<AppMapMarker> _buildMarkers(AppProvider provider) {
    final markers = <AppMapMarker>[];

    for (var member in provider.familyMembers) {
      final isCurrentUser = member.id == provider.currentUser?.id;
      var loc = provider.memberLocations[member.id];
      
      if (loc == null) {
        if (!isCurrentUser) continue;
        continue; 
      }

      markers.add(AppMapMarker(
        id: member.id,
        position: AppLatLng(loc.latitude, loc.longitude),
        child: GestureDetector(
          onTap: () => _showMemberDetails(member, loc),
          child: isCurrentUser
              ? AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) => _buildCurrentUserMarker(member, _pulseAnimation.value),
                )
              : _buildFamilyMemberMarker(member),
        ),
      ));
    }

    for (var zone in provider.safeZones) {
      markers.add(AppMapMarker(
        id: 'zone_ic_${zone.id}',
        position: AppLatLng(zone.latitude, zone.longitude),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _safeZoneColor.withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _safeZoneColor.withOpacity(0.4), blurRadius: 6)],
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 18),
        ),
      ));
    }

    return markers;
  }

  // ── Marker Widgets ───────────────────────────────────────

  Widget _buildCurrentUserMarker(FamilyMember member, double pulseValue) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _currentUserColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: _currentUserColor.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, size: 10, color: Colors.white),
              const SizedBox(width: 3),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 44 * pulseValue,
              height: 44 * pulseValue,
              decoration: BoxDecoration(
                color: _currentUserColor.withOpacity(0.2 * pulseValue),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _currentUserColor.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _currentUserColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: _currentUserColor.withOpacity(0.6), blurRadius: 8)],
              ),
              child: _buildAvatarChild(member, size: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarChild(FamilyMember member, {double size = 10, Color textColor = Colors.white}) {
    if (member.photoUrl != null && member.photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          member.photoUrl!,
          width: size * 2,
          height: size * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildInitialsAvatar(member, size, textColor),
        ),
      );
    }
    return _buildInitialsAvatar(member, size, textColor);
  }

  Widget _buildInitialsAvatar(FamilyMember member, double size, Color textColor) {
    return Center(
      child: Text(
        member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
        style: TextStyle(color: textColor, fontSize: size, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFamilyMemberMarker(FamilyMember member) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
            border: Border.all(color: _familyMemberColor.withOpacity(0.3)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _familyMemberColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _familyMemberColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _familyMemberColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: _familyMemberColor.withOpacity(0.5), blurRadius: 6)],
              ),
              child: _buildAvatarChild(member, size: 10),
            ),
          ],
        ),
        CustomPaint(
          size: const Size(10, 6),
          painter: _TrianglePainter(color: _familyMemberColor),
        ),
      ],
    );
  }

  // ── AppBar Buttons ───────────────────────────────────────

  Widget _buildLocationToggle() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) => IconButton(
        icon: Icon(
          provider.isLocationSharing ? Icons.location_on : Icons.location_off_outlined,
          color: provider.isLocationSharing ? Colors.green : null,
        ),
        tooltip: provider.isLocationSharing ? 'Tắt chia sẻ vị trí' : 'Bật chia sẻ vị trí',
        onPressed: () => provider.isLocationSharing
            ? provider.stopLocationSharing()
            : provider.startLocationSharing(),
      ),
    );
  }

  Widget _buildNotificationBadge() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) => Stack(
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Thông báo',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          if (provider.unreadNotificationCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  provider.unreadNotificationCount > 99
                      ? '99+'
                      : '${provider.unreadNotificationCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyPositionButton() {
    return IconButton(
      icon: const Icon(Icons.my_location),
      tooltip: 'Vị trí của tôi',
      onPressed: () async {
        final loc = await Provider.of<AppProvider>(context, listen: false).getCurrentLocation();
        if (loc != null) _mapController?.moveTo(AppLatLng(loc.latitude, loc.longitude), zoom: 16);
      },
    );
  }

  Widget _buildMoreMenu() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) async {
          if (value == 'signout') {
            await provider.signOut();
          } else if (value == 'profile') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          } else if (value == 'join_family') {
            _showJoinFamilyDialog();
          } else if (value == 'add_member') {
            _showAddMemberDialog();
          } else if (value == 'chat') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
          } else if (value == 'location_toggle') {
            provider.isLocationSharing 
                ? provider.stopLocationSharing() 
                : provider.startLocationSharing();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'profile',
            child: Row(children: [
              Icon(Icons.person_outline, size: 20),
              SizedBox(width: 8),
              Text('Cài đặt cá nhân'),
            ]),
          ),
          const PopupMenuItem(
            value: 'chat',
            child: Row(children: [
              Icon(Icons.chat_bubble_outline, size: 20),
              SizedBox(width: 8),
              Text('Chat gia đình'),
            ]),
          ),
          PopupMenuItem(
            value: 'location_toggle',
            child: Row(children: [
              Icon(
                provider.isLocationSharing ? Icons.location_on : Icons.location_off_outlined,
                size: 20,
                color: provider.isLocationSharing ? Colors.green : null,
              ),
              const SizedBox(width: 8),
              Text(provider.isLocationSharing ? 'Tắt chia sẻ vị trí' : 'Bật chia sẻ vị trí'),
            ]),
          ),
          const PopupMenuItem(
            value: 'join_family',
            child: Row(children: [
              Icon(Icons.group_add, size: 20),
              SizedBox(width: 8),
              Text('Tham gia gia đình'),
            ]),
          ),
          const PopupMenuItem(
            value: 'add_member',
            child: Row(children: [
              Icon(Icons.person_add, size: 20),
              SizedBox(width: 8),
              Text('Thêm thành viên'),
            ]),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'signout',
            child: Row(children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 8),
              Text('Đăng xuất'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildFab(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'add_zone',
          backgroundColor: colorScheme.secondaryContainer,
          child: const Icon(Icons.add_location_alt),
          onPressed: () => _showAddSafeZoneDialog(),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'family',
          backgroundColor: colorScheme.primaryContainer,
          child: const Icon(Icons.people),
          onPressed: () => _showFamilyMembersSheet(),
        ),
      ],
    );
  }

  // ── Sheets & Dialogs ─────────────────────────────────────

  void _showMemberDetails(FamilyMember member, UserLocation loc) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrentUser = member.id == Provider.of<AppProvider>(context, listen: false).currentUser?.id;
    final ago = _timeAgo(_getFreshestTimestamp(member, loc));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Stack(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: isCurrentUser ? _currentUserColor : _familyMemberColor,
                  child: _buildAvatarChild(member, size: 28),
                ),
                if (member.isLocationSharing)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: colorScheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(member.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(member.email, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),

            const SizedBox(height: 12),
            _buildStatusBadge(member.status, colorScheme),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Cập nhật $ago', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.my_location, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                  if (loc.address != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(loc.address!, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Lịch sử'),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LocationHistoryScreen(member: member),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.location_searching),
                    label: const Text('Tập trung'),
                    onPressed: () {
                      _mapController?.moveTo(AppLatLng(loc.latitude, loc.longitude), zoom: 16);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, ColorScheme colorScheme) {
    String label;
    Color color;
    IconData icon;

    switch (status) {
      case 'online':
        label = 'Đang trực tuyến';
        color = Colors.green;
        icon = Icons.flash_on;
        break;
      case 'idle':
        label = 'Chế độ chờ (Nền)';
        color = Colors.orange;
        icon = Icons.hourglass_empty;
        break;
      case 'background':
        label = 'Truy cập (Service)';
        color = Colors.blue;
        icon = Icons.track_changes;
        break;
      default:
        label = 'Ngoại tuyến';
        color = Colors.grey;
        icon = Icons.power_settings_new;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showAddSafeZoneDialog() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final location = await provider.getCurrentLocation();
    if (location == null) return;

    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '200');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo vùng an toàn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Tên vùng',
                prefixIcon: Icon(Icons.home),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: radiusController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Bán kính (m)',
                prefixIcon: Icon(Icons.radar),
                suffixText: 'mét',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              final radius = double.tryParse(radiusController.text) ?? 200;
              await provider.createSafeZone(SafeZone(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameController.text,
                latitude: location.latitude,
                longitude: location.longitude,
                radiusMeters: radius,
                familyId: provider.currentUser!.familyId,
              ));
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  void _showJoinFamilyDialog() {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tham gia gia đình'),
        content: TextField(
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Mã gia đình',
            prefixIcon: Icon(Icons.group_add),
            hintText: 'Nhập mã 8 ký tự',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(context);
              final provider = Provider.of<AppProvider>(context, listen: false);
              final ok = await provider.joinFamilyByCode(code);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? '✅ Tham gia gia đình thành công!' : '❌ Mã không hợp lệ'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: ok ? Colors.green : Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              }
            },
            child: const Text('Tham gia'),
          ),
        ],
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
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email thành viên',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(context);
              final provider = Provider.of<AppProvider>(context, listen: false);
              final ok = await provider.addFamilyMember(email);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? '✅ Đã thêm $email' : '❌ Không tìm thấy email'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: ok ? Colors.green : Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showFamilyMembersSheet() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: isLandscape ? 0.8 : 0.5,
        minChildSize: isLandscape ? 0.4 : 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Consumer<AppProvider>(
                builder: (context, provider, _) {
                  if (provider.currentUser == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: _currentUserColor,
                                child: _buildAvatarChild(provider.currentUser!, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${provider.currentUser!.name} (Tôi)',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            provider.currentUser!.email,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        if (provider.isAdmin) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Admin',
                                              style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Đang online',
                                  style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(indent: 20, endIndent: 20),
                    ],
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 4),
                child: Text('Thành viên gia đình',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    final members = provider.familyMembers;
                    if (members.isEmpty && provider.currentUser != null) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _currentUserColor,
                          child: _buildAvatarChild(provider.currentUser!, size: 16),
                        ),
                        title: Text(provider.currentUser!.name),
                        subtitle: const Text('Đang tải danh sách...'),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final loc = provider.memberLocations[member.id];
                        final isCurrentUser = member.id == provider.currentUser?.id;

                        // Senior Fix: Replaced standard ListTile with a custom Row to handle flexible widths better and prevent overflows
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              // 1. LEADING: Avatar
                              Stack(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: member.status == 'online' 
                                            ? Colors.green 
                                            : member.status == 'idle' 
                                                ? Colors.amber 
                                                : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      backgroundColor: isCurrentUser ? _currentUserColor : _familyMemberColor,
                                      child: _buildAvatarChild(member, size: 16),
                                    ),
                                  ),
                                  if (member.isLocationSharing)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              
                              // 2. MIDDLE: Text Info (Expanded to take available space and prevent overflow)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            member.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: (member.status == 'online' ? Colors.green : (member.status == 'idle' ? Colors.amber : Colors.grey)).withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: (member.status == 'online' ? Colors.green : (member.status == 'idle' ? Colors.amber : Colors.grey)).withOpacity(0.3)),
                                          ),
                                          child: Text(
                                            member.status == 'online' ? 'Online' : (member.status == 'idle' ? 'Vừa xong' : 'Offline'),
                                            style: TextStyle(
                                              color: member.status == 'online' ? Colors.green : (member.status == 'idle' ? Colors.amber[800] : Colors.grey[700]), 
                                              fontSize: 9, 
                                              fontWeight: FontWeight.bold
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      provider.getDisplayAddress(loc),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: member.isLocationSharing ? Colors.black54 : Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '🕒 ${_timeAgo(_getFreshestTimestamp(member, loc))}',
                                      style: const TextStyle(fontSize: 10, color: Colors.black26),
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(width: 8),

                              // 3. TRAILING: Action Buttons (Fixed width to prevent ANY overflow)
                              SizedBox(
                                width: (provider.isAdmin && !isCurrentUser) ? 100 : 70,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _buildSmallActionButton(
                                      icon: Icons.history,
                                      tooltip: 'Lịch sử',
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => LocationHistoryScreen(member: member)));
                                      },
                                    ),
                                    if (loc != null) ...[
                                      _buildSmallActionButton(
                                        icon: Icons.location_searching,
                                        tooltip: 'Tập trung',
                                        onPressed: () {
                                          _mapController?.moveTo(AppLatLng(loc.latitude, loc.longitude), zoom: 16);
                                          Navigator.pop(context);
                                        },
                                      ),
                                    ],
                                    if (provider.isAdmin && !isCurrentUser) ...[
                                      _buildSmallActionButton(
                                        icon: Icons.person_remove,
                                        color: Colors.red,
                                        tooltip: 'Xóa',
                                        onPressed: () => _confirmRemoveMember(member, provider),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmRemoveMember(FamilyMember member, AppProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa thành viên?'),
        content: Text('Bạn có chắc muốn xóa ${member.name} khỏi gia đình?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await provider.removeFamilyMember(member.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? '✅ Đã xóa ${member.name}' : '❌ Không thể xóa'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              }
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────

  Widget _buildSmallActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color ?? Colors.black54),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final now = Provider.of<AppProvider>(context, listen: false).serverNow;
    final diff = now.difference(dt.isUtc ? dt.toLocal() : dt);
    if (diff.isNegative || diff.inSeconds < 30) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return '${(diff.inDays / 30).floor()} tháng trước';
  }

  DateTime _getFreshestTimestamp(FamilyMember member, UserLocation? loc) {
    final lastSeen = member.lastSeen;
    final locTime = loc?.timestamp;
    if (lastSeen == null) return locTime ?? DateTime.now();
    if (locTime == null) return lastSeen;
    return lastSeen.isAfter(locTime) ? lastSeen : locTime;
  }
}

// ── Triangle painter for marker pointer ─────────────────

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
