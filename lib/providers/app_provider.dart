import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';

/// Main application state provider.
/// Manages auth state, family data, locations, and safe zones.
class AppProvider extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final LocationService _locationService = LocationService();

  FamilyMember? _currentUser;
  List<FamilyMember> _familyMembers = [];
  Map<String, UserLocation?> _memberLocations = {};
  List<SafeZone> _safeZones = [];
  bool _isLocationSharing = false;
  bool _isLoading = false;

  // Realtime channel references for cleanup
  RealtimeChannel? _familyChannel;
  final Map<String, RealtimeChannel> _locationChannels = {};
  RealtimeChannel? _safeZonesChannel;

  // Getters
  FamilyMember? get currentUser => _currentUser;
  List<FamilyMember> get familyMembers => _familyMembers;
  Map<String, UserLocation?> get memberLocations => _memberLocations;
  List<SafeZone> get safeZones => _safeZones;
  bool get isLocationSharing => _isLocationSharing;
  bool get isLoading => _isLoading;

  /// Initialize app state - check if user is already logged in.
  Future<void> initialize() async {
    final user = _supabaseService.currentUser;
    if (user != null) {
      await loadUserData(user.id);
    }
  }

  /// Load all user data and setup realtime subscriptions.
  Future<void> loadUserData(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _currentUser = await _supabaseService.getUserInfo(userId);

      if (_currentUser != null) {
        _isLocationSharing = _currentUser!.isLocationSharing;

        // Subscribe to family members (realtime)
        _familyChannel?.unsubscribe();
        _familyChannel = _supabaseService.subscribeFamilyMembers(
          familyId: _currentUser!.familyId,
          onData: (members) {
            _familyMembers = members;
            notifyListeners();

            // Subscribe to each member's location
            _subscribeToMemberLocations(members);
          },
        );

        // Subscribe to safe zones (realtime)
        _safeZonesChannel?.unsubscribe();
        _safeZonesChannel = _supabaseService.subscribeSafeZones(
          familyId: _currentUser!.familyId,
          onData: (zones) {
            _safeZones = zones;
            notifyListeners();
          },
        );

        // Start location sharing if previously enabled
        if (_isLocationSharing) {
          startLocationSharing();
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Subscribe to location updates for each family member.
  void _subscribeToMemberLocations(List<FamilyMember> members) {
    for (var member in members) {
      if (member.isLocationSharing && !_locationChannels.containsKey(member.id)) {
        final channel = _supabaseService.subscribeMemberLocation(
          userId: member.id,
          onData: (location) {
            _memberLocations[member.id] = location;
            notifyListeners();
          },
        );
        _locationChannels[member.id] = channel;
      }
    }
  }

  /// Sign in with email and password.
  Future<bool> signIn(String email, String password) async {
    final user = await _supabaseService.signIn(email, password);
    if (user != null) {
      await loadUserData(user.id);
      return true;
    }
    return false;
  }

  /// Sign up with email, password, and name.
  Future<bool> signUp(String email, String password, String name) async {
    final user = await _supabaseService.signUp(email, password, name);
    if (user != null) {
      await loadUserData(user.id);
      return true;
    }
    return false;
  }

  /// Sign out and clean up state.
  Future<void> signOut() async {
    stopLocationSharing();
    await _cleanupSubscriptions();
    await _supabaseService.signOut();

    _currentUser = null;
    _familyMembers = [];
    _memberLocations = {};
    _safeZones = [];
    _isLocationSharing = false;
    notifyListeners();
  }

  /// Enable location sharing.
  Future<void> startLocationSharing() async {
    if (_currentUser == null) return;

    bool hasPermission = await _locationService.requestLocationPermission();
    if (!hasPermission) return;

    _isLocationSharing = true;
    await _supabaseService.toggleLocationSharing(_currentUser!.id, true);

    _locationService.startTracking((location) {
      _supabaseService.updateUserLocation(location);
    }, _currentUser!.id);

    notifyListeners();
  }

  /// Disable location sharing.
  Future<void> stopLocationSharing() async {
    if (_currentUser == null) return;

    _isLocationSharing = false;
    await _supabaseService.toggleLocationSharing(_currentUser!.id, false);
    _locationService.stopTracking();
    notifyListeners();
  }

  /// Add a family member by email.
  Future<bool> addFamilyMember(String email) async {
    if (_currentUser == null) return false;
    return await _supabaseService.addFamilyMember(
      email,
      _currentUser!.familyId,
    );
  }

  /// Create a new safe zone.
  Future<void> createSafeZone(SafeZone zone) async {
    await _supabaseService.createSafeZone(zone);
  }

  /// Delete a safe zone.
  Future<void> deleteSafeZone(String zoneId) async {
    await _supabaseService.deleteSafeZone(zoneId);
  }

  /// Get the current device location.
  Future<UserLocation?> getCurrentLocation() async {
    if (_currentUser == null) return null;

    final position = await _locationService.getCurrentLocation();
    if (position == null) return null;

    final address = await _locationService.getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return UserLocation(
      userId: _currentUser!.id,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now().toUtc(),
      accuracy: position.accuracy,
      address: address,
    );
  }

  /// Clean up all realtime subscriptions.
  Future<void> _cleanupSubscriptions() async {
    _familyChannel?.unsubscribe();
    _safeZonesChannel?.unsubscribe();
    for (var channel in _locationChannels.values) {
      channel.unsubscribe();
    }
    _locationChannels.clear();
    await _supabaseService.removeAllChannels();
  }

  @override
  void dispose() {
    _cleanupSubscriptions();
    _locationService.stopTracking();
    super.dispose();
  }
}
