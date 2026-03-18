import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../widgets/map_adapter/map_adapter.dart';
import '../widgets/map_adapter/leaflet_adapter.dart';
import 'location_history_screen.dart';

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
          builder: (context, provider, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Family Tracker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              if (provider.familyMembers.isNotEmpty)
                Text(
                  '${provider.familyMembers.length} thành viên',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          _buildLocationToggle(),
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
            Text('Mã gia đình: ', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
            Text(
              code,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                letterSpacing: 1.5,
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

    // Family members - show all with location
    for (var member in provider.familyMembers) {
      final isCurrentUser = member.id == provider.currentUser?.id;
      var loc = provider.memberLocations[member.id];
      
      // FALLBACK: If current user doesn't have a location in provider.memberLocations yet,
      // it might not show. We can skip other members without loc, but show current user if possible.
      if (loc == null) {
        if (!isCurrentUser) continue;
        // Don't skip current user, try to use a default or wait for location
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

    // Safe Zone icons
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

  /// Current user marker with pulsing animation
  Widget _buildCurrentUserMarker(FamilyMember member, double pulseValue) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name tag
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
              Text(
                member.name,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        // Pulsing marker
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Container(
              width: 44 * pulseValue,
              height: 44 * pulseValue,
              decoration: BoxDecoration(
                color: _currentUserColor.withOpacity(0.2 * pulseValue),
                shape: BoxShape.circle,
              ),
            ),
            // Inner ring
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _currentUserColor.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
            ),
            // Core dot
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

  /// Family member marker (static, red)
  Widget _buildFamilyMemberMarker(FamilyMember member) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name tag
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
            border: Border.all(color: _familyMemberColor.withOpacity(0.3)),
          ),
          child: Text(
            member.name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _familyMemberColor,
            ),
          ),
        ),
        const SizedBox(height: 3),
        // Avatar marker
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
        // Down pointer
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
          } else if (value == 'join_family') {
            _showJoinFamilyDialog();
          } else if (value == 'add_member') {
            _showAddMemberDialog();
          }
        },
        itemBuilder: (context) => [
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
    final ago = _timeAgo(loc.timestamp);

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
            // Handle bar
            Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            // Avatar
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

            const SizedBox(height: 16),
            // Location info
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
            // Actions
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

  void _showAddSafeZoneDialog() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final location = await provider.getCurrentLocation();
    if (location == null) return;

    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo vùng an toàn'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Tên vùng', prefixIcon: Icon(Icons.home))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              await provider.createSafeZone(SafeZone(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameController.text,
                latitude: location.latitude,
                longitude: location.longitude,
                radiusMeters: 200,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
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
                                    Text(
                                      provider.currentUser!.email,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
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
                child: Text('Khác trong gia đình',
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

                        return ListTile(
                          onTap: () {
                            if (loc != null) {
                              _mapController?.moveTo(AppLatLng(loc.latitude, loc.longitude), zoom: 16);
                              Navigator.pop(context);
                            }
                          },
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: isCurrentUser ? _currentUserColor : _familyMemberColor,
                                child: _buildAvatarChild(member, size: 16),
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
                          title: Text(member.name),
                          subtitle: Text(
                            member.isLocationSharing
                                ? loc != null
                                    ? '📍 ${_timeAgo(loc.timestamp)}'
                                    : '📡 Đang kết nối...'
                                : '📵 Không chia sẻ vị trí',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.history, size: 20),
                                tooltip: 'Lịch sử',
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
                              if (loc != null)
                                IconButton(
                                  icon: const Icon(Icons.location_searching, size: 20),
                                  tooltip: 'Tập trung',
                                  onPressed: () {
                                    _mapController?.moveTo(AppLatLng(loc.latitude, loc.longitude), zoom: 16);
                                    Navigator.pop(context);
                                  },
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

  // ── Helpers ──────────────────────────────────────────────

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
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


