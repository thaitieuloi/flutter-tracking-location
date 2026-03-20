import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';

class AppProvider extends ChangeNotifier {
  final SupabaseService _svc = SupabaseService();
  final LocationService _locationSvc = LocationService();

  FamilyMember? _currentUser;
  String? _familyId;
  String? _familyName;
  String? _inviteCode;
  String? _currentUserRole; // 'admin' or 'member'
  List<FamilyMember> _familyMembers = [];
  Map<String, UserLocation?> _memberLocations = {};
  List<SafeZone> _safeZones = [];
  bool _isLocationSharing = false;
  bool _isLoading = false;
  int _unreadNotificationCount = 0;

  RealtimeChannel? _familyChannel;
  RealtimeChannel? _geofencesChannel;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _messagesChannel;
  final Map<String, RealtimeChannel> _locationChannels = {};

  FamilyMember?              get currentUser            => _currentUser;
  String?                    get familyId               => _familyId;
  String                     get familyName             => _familyName ?? 'Together Home';
  String?                    get inviteCode             => _inviteCode;
  String?                    get currentUserRole        => _currentUserRole;
  bool                       get isAdmin                => _currentUserRole == 'admin';
  List<FamilyMember>         get familyMembers          => _familyMembers;
  Map<String, UserLocation?> get memberLocations        => _memberLocations;
  List<SafeZone>             get safeZones              => _safeZones;
  bool                       get isLocationSharing      => _isLocationSharing;
  bool                       get isLoading              => _isLoading;
  int                        get unreadNotificationCount => _unreadNotificationCount;

  Future<void> initialize() async {
    final user = _svc.currentUser;
    if (user != null) {
      _svc.log('🚀 [App] Auto-login for ${user.id}');
      await loadUserData(user.id);
    } else {
      _svc.log('🚀 [App] No session found, waiting for login');
    }
  }

  Future<void> loadUserData(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _svc.log('🔄 [App] loadUserData: $userId');

      // 1. Load user profile
      _currentUser = await _svc.getUserInfo(userId);

      if (_currentUser == null) {
        _svc.log('⚠️ [App] User profile not in DB yet, this is normal for new users');
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 2. Get or create familyId
      _familyId = await _svc.getOrCreateFamilyId(userId, _currentUser!.name);
      if (_familyId == null) {
        _svc.log('❌ [App] Could not get or create familyId');
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 3. Load invite code for this family
      _inviteCode = await _svc.getInviteCode(_familyId!);

      // 4. Load family name
      final family = await _svc.getFamilyInfo(_familyId!);
      _familyName = family?.name;

      // 5. Get user role
      _currentUserRole = await _svc.getMemberRole(userId, _familyId!);

      // 6. Refresh user info (latest state)
      _currentUser = await _svc.getUserInfo(userId);

      _isLocationSharing = _currentUser?.isLocationSharing ?? false;
      _svc.log('✅ [App] User loaded: ${_currentUser?.name} | family: $_familyId | code: $_inviteCode | role: $_currentUserRole | sharing: $_isLocationSharing');

      // 6. Subscribe to family members (realtime)
      _familyChannel?.unsubscribe();
      _familyChannel = _svc.subscribeFamilyMembers(
        familyId: _familyId!,
        onData: (members) {
          _svc.log('👥 [App] Family members updated: ${members.length}');
          members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          _familyMembers = members;
          notifyListeners();
          _subscribeToMemberLocations(members);
        },
      );

      // 7. Subscribe to geofences (realtime)
      _geofencesChannel?.unsubscribe();
      _geofencesChannel = _svc.subscribeGeofences(
        familyId: _familyId!,
        onData: (zones) {
          _svc.log('🔒 [App] Geofences updated: ${zones.length}');
          _safeZones = zones;
          notifyListeners();
        },
      );

      // 8. Subscribe to notifications (realtime badge count)
      _notificationsChannel?.unsubscribe();
      _notificationsChannel = _svc.subscribeNotifications(
        userId: userId,
        onData: (count) {
          _unreadNotificationCount = count;
          notifyListeners();
        },
      );

      // 9. Resume tracking if was active
      if (_isLocationSharing) {
        _svc.log('📍 [App] Resuming location sharing');
        startLocationSharing();
      }
    } catch (e) {
      _svc.log('❌ [App] loadUserData error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  final Map<String, String> _addressCache = {};

  String getDisplayAddress(UserLocation? loc) {
    if (loc == null) return 'N/A';
    final key = "${loc.latitude.toStringAsFixed(6)},${loc.longitude.toStringAsFixed(6)}";
    if (_addressCache.containsKey(key)) return _addressCache[key]!;
    if (loc.address != null && loc.address!.isNotEmpty) return loc.address!;
    return 'Tọa độ: ${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
  }

  void _subscribeToMemberLocations(List<FamilyMember> members) {
    for (final member in members) {
      if (!_locationChannels.containsKey(member.id)) {
        _svc.log('📡 [App] Subscribing to location for: ${member.name}');
        final ch = _svc.subscribeMemberLocation(
          userId: member.id,
          onData: (loc) async {
            if (loc == null) {
              _memberLocations[member.id] = null;
              notifyListeners();
              return;
            }

            // Immediately set the location point
            _memberLocations[member.id] = loc;
            notifyListeners();

            // Background geocoding logic (similar to History screen)
            final key = "${loc.latitude.toStringAsFixed(6)},${loc.longitude.toStringAsFixed(6)}";
            if (!_addressCache.containsKey(key)) {
              final addr = await _locationSvc.getAddressFromCoordinates(loc.latitude, loc.longitude);
              if (addr != null) {
                _addressCache[key] = addr;
                notifyListeners(); // Refresh UI to show the new address from cache
              }
            }
          },
        );
        _locationChannels[member.id] = ch;
      }
    }
  }

  Future<bool> signIn(String email, String password) async {
    _svc.log('🔐 [App] signIn: $email');
    final user = await _svc.signIn(email, password);
    if (user != null) {
      await loadUserData(user.id);
      return true;
    }
    return false;
  }

  Future<bool> signUp(String email, String password, String name, {String? inviteCode}) async {
    _svc.log('🔐 [App] signUp: $email | code: ${inviteCode ?? 'none'}');
    final user = await _svc.signUp(email, password, name, inviteCode: inviteCode);
    if (user != null) {
      await loadUserData(user.id);
      return true;
    }
    return false;
  }

  Future<void> signOut() async {
    _svc.log('🔐 [App] signOut');
    if (_currentUser != null) {
      await _svc.updateUserStatus(_currentUser!.id, 'offline');
    }
    stopLocationSharing();
    await _cleanupSubscriptions();
    await _svc.signOut();
    _currentUser = null;
    _familyId = null;
    _inviteCode = null;
    _currentUserRole = null;
    _familyMembers = [];
    _memberLocations = {};
    _safeZones = [];
    _isLocationSharing = false;
    _unreadNotificationCount = 0;
    notifyListeners();
  }

  Future<void> startLocationSharing() async {
    if (_currentUser == null) {
      _svc.log('⚠️ [App] startLocationSharing: no user, abort');
      return;
    }

    final ok = await _locationSvc.requestLocationPermission();
    if (!ok) {
      _svc.log('❌ [App] Location permission denied');
      return;
    }

    _isLocationSharing = true;
    await _svc.toggleLocationSharing(_currentUser!.id, true);

    _locationSvc.startTracking((location) {
      _svc.log('📍 [Tracking] New position: ${location.latitude}, ${location.longitude}');
      _svc.updateUserLocation(location);
      _memberLocations[_currentUser!.id] = location;
      notifyListeners();
    }, _currentUser!.id, periodicSeconds: 30);

    notifyListeners();
    _svc.log('✅ [App] Location sharing started (periodic: 30s)');
  }

  Future<void> stopLocationSharing() async {
    if (_currentUser == null) return;
    _isLocationSharing = false;
    await _svc.toggleLocationSharing(_currentUser!.id, false);
    _locationSvc.stopTracking();
    notifyListeners();
    _svc.log('🛑 [App] Location sharing stopped');
  }

  Future<UserLocation?> getCurrentLocation() async {
    if (_currentUser == null) return null;
    final pos = await _locationSvc.getCurrentLocation();
    if (pos == null) {
      _svc.log('❌ [App] Could not get device position');
      return null;
    }
    
    _svc.log('✅ [App] Device position: ${pos.latitude}, ${pos.longitude}');
    final loc = UserLocation(
      userId: _currentUser!.id,
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: DateTime.now().toUtc(),
      accuracy: pos.accuracy,
    );
    
    _memberLocations[_currentUser!.id] = loc;
    notifyListeners();
    
    return loc;
  }

  Future<bool> addFamilyMember(String email) async {
    if (_familyId == null) return false;
    return await _svc.addFamilyMember(email, _familyId!);
  }

  /// Remove a family member (admin only)
  Future<bool> removeFamilyMember(String memberId) async {
    if (_familyId == null || !isAdmin) return false;
    final ok = await _svc.removeFamilyMember(memberId, _familyId!);
    if (ok) {
      _familyMembers.removeWhere((m) => m.id == memberId);
      notifyListeners();
    }
    return ok;
  }

  /// Join a family by invite code (for already-logged-in user)
  Future<bool> joinFamilyByCode(String inviteCode) async {
    if (_currentUser == null) return false;
    final ok = await _svc.joinFamilyByCode(_currentUser!.id, inviteCode);
    if (ok) {
      await loadUserData(_currentUser!.id);
    }
    return ok;
  }

  Future<List<UserLocation>> getLocationHistory(String userId, {int limit = 50, DateTime? startTime, DateTime? endTime}) async {
    return await _svc.getLocationHistory(userId, limit: limit, startTime: startTime, endTime: endTime);
  }

  Future<void> createSafeZone(SafeZone zone) async {
    await _svc.createGeofence(zone);
  }

  Future<void> deleteSafeZone(String zoneId) async {
    await _svc.deleteGeofence(zoneId);
  }

  Future<void> updateProfile({String? name, String? photoUrl}) async {
    if (_currentUser == null) return;
    await _svc.updateProfile(userId: _currentUser!.id, name: name, photoUrl: photoUrl);
    _currentUser = await _svc.getUserInfo(_currentUser!.id);
    notifyListeners();
  }

  // ── SOS ──────────────────────────────────────────────────

  Future<bool> sendSos({String message = 'SOS - Cần giúp đỡ!'}) async {
    if (_currentUser == null) return false;
    final loc = await getCurrentLocation();
    if (loc == null) return false;

    return await _svc.sendSosAlert(
      userId: _currentUser!.id,
      latitude: loc.latitude,
      longitude: loc.longitude,
      message: message,
    );
  }

  // ── Notifications ────────────────────────────────────────

  Future<List<AppNotification>> getNotifications() async {
    if (_currentUser == null) return [];
    return await _svc.getNotifications(_currentUser!.id);
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _svc.markNotificationRead(notificationId);
    _unreadNotificationCount = (_unreadNotificationCount - 1).clamp(0, 9999);
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    if (_currentUser == null) return;
    await _svc.markAllNotificationsRead(_currentUser!.id);
    _unreadNotificationCount = 0;
    notifyListeners();
  }

  Future<void> deleteNotification(String notificationId) async {
    await _svc.deleteNotification(notificationId);
  }

  // ── Chat / Messages ─────────────────────────────────────

  Future<List<ChatMessage>> getMessages() async {
    if (_familyId == null) return [];
    return await _svc.getMessages(_familyId!);
  }

  Future<ChatMessage?> sendMessage(String content) async {
    if (_familyId == null || _currentUser == null) return null;
    return await _svc.sendMessage(
      familyId: _familyId!,
      userId: _currentUser!.id,
      content: content,
    );
  }

  Future<ChatMessage?> sendLocationMessage(double lat, double lng) async {
    if (_familyId == null || _currentUser == null) return null;
    return await _svc.sendMessage(
      familyId: _familyId!,
      userId: _currentUser!.id,
      content: '📍 Chia sẻ vị trí',
      locationLat: lat,
      locationLng: lng,
    );
  }

  void subscribeMessages({required void Function(ChatMessage) onNewMessage}) {
    if (_familyId == null) return;
    _messagesChannel?.unsubscribe();
    _messagesChannel = _svc.subscribeMessages(
      familyId: _familyId!,
      onNewMessage: onNewMessage,
    );
  }

  // ── Cleanup ──────────────────────────────────────────────

  Future<void> _cleanupSubscriptions() async {
    _familyChannel?.unsubscribe();
    _geofencesChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    _messagesChannel?.unsubscribe();
    for (final ch in _locationChannels.values) ch.unsubscribe();
    _locationChannels.clear();
    await _svc.removeAllChannels();
  }

  @override
  void dispose() {
    _cleanupSubscriptions();
    _locationSvc.stopTracking();
    super.dispose();
  }
}
