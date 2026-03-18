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
  String? _inviteCode;
  List<FamilyMember> _familyMembers = [];
  Map<String, UserLocation?> _memberLocations = {};
  List<SafeZone> _safeZones = [];
  bool _isLocationSharing = false;
  bool _isLoading = false;

  RealtimeChannel? _familyChannel;
  RealtimeChannel? _geofencesChannel;
  final Map<String, RealtimeChannel> _locationChannels = {};

  FamilyMember?              get currentUser       => _currentUser;
  String?                    get familyId          => _familyId;
  String?                    get inviteCode        => _inviteCode;
  List<FamilyMember>         get familyMembers     => _familyMembers;
  Map<String, UserLocation?> get memberLocations   => _memberLocations;
  List<SafeZone>             get safeZones         => _safeZones;
  bool                       get isLocationSharing => _isLocationSharing;
  bool                       get isLoading         => _isLoading;

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

      // 2. Get or create familyId (won't create new one if already has one)
      _familyId = await _svc.getOrCreateFamilyId(userId, _currentUser!.name);
      if (_familyId == null) {
        _svc.log('❌ [App] Could not get or create familyId');
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 3. Load invite code for this family
      _inviteCode = await _svc.getInviteCode(_familyId!);

      // 4. Refresh user info to get family_id populated
      _currentUser = await _svc.getUserInfo(userId);

      _isLocationSharing = _currentUser?.isLocationSharing ?? false;
      _svc.log('✅ [App] User loaded: ${_currentUser?.name} | family: $_familyId | code: $_inviteCode | sharing: $_isLocationSharing');

      // 5. Subscribe to family members (realtime)
      _familyChannel?.unsubscribe();
      _familyChannel = _svc.subscribeFamilyMembers(
        familyId: _familyId!,
        onData: (members) {
          _svc.log('👥 [App] Family members updated: ${members.length}');
          _familyMembers = members;
          notifyListeners();
          _subscribeToMemberLocations(members);
        },
      );

      // 6. Subscribe to geofences (realtime)
      _geofencesChannel?.unsubscribe();
      _geofencesChannel = _svc.subscribeGeofences(
        familyId: _familyId!,
        onData: (zones) {
          _svc.log('🔒 [App] Geofences updated: ${zones.length}');
          _safeZones = zones;
          notifyListeners();
        },
      );

      // 7. Resume tracking if was active
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

  void _subscribeToMemberLocations(List<FamilyMember> members) {
    for (final member in members) {
      if (!_locationChannels.containsKey(member.id)) {
        _svc.log('📡 [App] Subscribing to location for: ${member.name}');
        final ch = _svc.subscribeMemberLocation(
          userId: member.id,
          onData: (loc) {
            _memberLocations[member.id] = loc;
            if (loc != null) {
              _svc.log('📍 [App] ${member.name} at ${loc.latitude},${loc.longitude}');
            }
            notifyListeners();
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
    stopLocationSharing();
    await _cleanupSubscriptions();
    await _svc.signOut();
    _currentUser = null;
    _familyId = null;
    _inviteCode = null;
    _familyMembers = [];
    _memberLocations = {};
    _safeZones = [];
    _isLocationSharing = false;
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
      // Immediately update local state so marker moves without waiting realtime
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
    
    // Update local state immediately so marker shows on map
    _memberLocations[_currentUser!.id] = loc;
    notifyListeners();
    
    return loc;
  }

  Future<bool> addFamilyMember(String email) async {
    if (_familyId == null) return false;
    return await _svc.addFamilyMember(email, _familyId!);
  }

  /// Join a family by invite code (for already-logged-in user)
  Future<bool> joinFamilyByCode(String inviteCode) async {
    if (_currentUser == null) return false;
    final ok = await _svc.joinFamilyByCode(_currentUser!.id, inviteCode);
    if (ok) {
      // Reload all data with new family
      await loadUserData(_currentUser!.id);
    }
    return ok;
  }

  Future<List<UserLocation>> getLocationHistory(String userId, {int limit = 50}) async {
    return await _svc.getLocationHistory(userId, limit: limit);
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
    // Reload data to update local state
    _currentUser = await _svc.getUserInfo(_currentUser!.id);
    notifyListeners();
  }

  Future<void> _cleanupSubscriptions() async {
    _familyChannel?.unsubscribe();
    _geofencesChannel?.unsubscribe();
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
