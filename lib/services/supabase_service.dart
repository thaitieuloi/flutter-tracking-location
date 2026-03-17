import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// Service layer for all Supabase operations.
/// Replaces the previous FirebaseService with Supabase equivalents.
class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;
  static const _uuid = Uuid();

  // Table names (PostgreSQL convention: snake_case)
  static const String usersTable = 'users';
  static const String locationsTable = 'locations';
  static const String familiesTable = 'families';
  static const String safeZonesTable = 'safe_zones';

  // ──────────────────────────────────────────────
  // AUTH
  // ──────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign up with email/password and create user profile + family.
  Future<User?> signUp(String email, String password, String name) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

      final user = response.user;
      if (user != null) {
        final familyId = _uuid.v4();

        // Create user profile
        await _client.from(usersTable).upsert({
          'id': user.id,
          'name': name,
          'email': email,
          'family_id': familyId,
          'is_location_sharing': false,
        });

        // Create family
        await _client.from(familiesTable).insert({
          'id': familyId,
          'name': '$name\'s Family',
          'created_by': user.id,
          'members': [user.id],
        });
      }
      return user;
    } on AuthException catch (e) {
      print('Auth error signing up: ${e.message}');
      return null;
    } catch (e) {
      print('Error signing up: $e');
      return null;
    }
  }

  /// Sign in with email/password.
  Future<User?> signIn(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user;
    } on AuthException catch (e) {
      print('Auth error signing in: ${e.message}');
      return null;
    } catch (e) {
      print('Error signing in: $e');
      return null;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ──────────────────────────────────────────────
  // USER OPERATIONS
  // ──────────────────────────────────────────────

  /// Get user profile from the users table.
  Future<FamilyMember?> getUserInfo(String userId) async {
    try {
      final data = await _client
          .from(usersTable)
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        return FamilyMember.fromMap(data);
      }
    } catch (e) {
      print('Error getting user info: $e');
    }
    return null;
  }

  /// Toggle location sharing for a user.
  Future<void> toggleLocationSharing(String userId, bool enabled) async {
    try {
      await _client
          .from(usersTable)
          .update({'is_location_sharing': enabled})
          .eq('id', userId);
    } catch (e) {
      print('Error toggling location sharing: $e');
    }
  }

  // ──────────────────────────────────────────────
  // LOCATION OPERATIONS
  // ──────────────────────────────────────────────

  /// Upsert user location (insert or update).
  Future<void> updateUserLocation(UserLocation location) async {
    try {
      await _client.from(locationsTable).upsert(
        location.toMap(),
        onConflict: 'user_id',
      );

      // Update last_seen on user profile
      await _client
          .from(usersTable)
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', location.userId);
    } catch (e) {
      print('Error updating location: $e');
    }
  }

  /// Get location for a specific user (one-time fetch).
  Future<UserLocation?> getUserLocation(String userId) async {
    try {
      final data = await _client
          .from(locationsTable)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null) {
        return UserLocation.fromMap(data);
      }
    } catch (e) {
      print('Error getting user location: $e');
    }
    return null;
  }

  // ──────────────────────────────────────────────
  // REALTIME SUBSCRIPTIONS
  // ──────────────────────────────────────────────

  /// Subscribe to family members changes (realtime).
  RealtimeChannel subscribeFamilyMembers({
    required String familyId,
    required void Function(List<FamilyMember>) onData,
  }) {
    // Initial fetch
    _fetchFamilyMembers(familyId).then(onData);

    // Realtime subscription
    final channel = _client
        .channel('family_members_$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: usersTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            // Re-fetch all members on any change
            _fetchFamilyMembers(familyId).then(onData);
          },
        )
        .subscribe();

    return channel;
  }

  Future<List<FamilyMember>> _fetchFamilyMembers(String familyId) async {
    try {
      final data = await _client
          .from(usersTable)
          .select()
          .eq('family_id', familyId);

      return (data as List)
          .map((item) => FamilyMember.fromMap(item))
          .toList();
    } catch (e) {
      print('Error fetching family members: $e');
      return [];
    }
  }

  /// Subscribe to a member's location changes (realtime).
  RealtimeChannel subscribeMemberLocation({
    required String userId,
    required void Function(UserLocation?) onData,
  }) {
    // Initial fetch
    getUserLocation(userId).then(onData);

    // Realtime subscription
    final channel = _client
        .channel('location_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: locationsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              onData(UserLocation.fromMap(payload.newRecord));
            }
          },
        )
        .subscribe();

    return channel;
  }

  /// Subscribe to safe zones changes (realtime).
  RealtimeChannel subscribeSafeZones({
    required String familyId,
    required void Function(List<SafeZone>) onData,
  }) {
    // Initial fetch
    _fetchSafeZones(familyId).then(onData);

    // Realtime subscription
    final channel = _client
        .channel('safe_zones_$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: safeZonesTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            _fetchSafeZones(familyId).then(onData);
          },
        )
        .subscribe();

    return channel;
  }

  Future<List<SafeZone>> _fetchSafeZones(String familyId) async {
    try {
      final data = await _client
          .from(safeZonesTable)
          .select()
          .eq('family_id', familyId);

      return (data as List)
          .map((item) => SafeZone.fromMap(item))
          .toList();
    } catch (e) {
      print('Error fetching safe zones: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // FAMILY OPERATIONS
  // ──────────────────────────────────────────────

  /// Add a member to the family by email.
  Future<bool> addFamilyMember(String email, String familyId) async {
    try {
      // Find user by email
      final data = await _client
          .from(usersTable)
          .select()
          .eq('email', email)
          .maybeSingle();

      if (data == null) {
        return false;
      }

      final userId = data['id'] as String;

      // Update user's family_id
      await _client
          .from(usersTable)
          .update({'family_id': familyId})
          .eq('id', userId);

      // Add to family members array
      final familyData = await _client
          .from(familiesTable)
          .select('members')
          .eq('id', familyId)
          .single();

      final members = List<String>.from(familyData['members'] ?? []);
      if (!members.contains(userId)) {
        members.add(userId);
        await _client
            .from(familiesTable)
            .update({'members': members})
            .eq('id', familyId);
      }

      return true;
    } catch (e) {
      print('Error adding family member: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // SAFE ZONE OPERATIONS
  // ──────────────────────────────────────────────

  /// Create a new safe zone.
  Future<void> createSafeZone(SafeZone zone) async {
    try {
      await _client.from(safeZonesTable).upsert(zone.toMap());
    } catch (e) {
      print('Error creating safe zone: $e');
    }
  }

  /// Delete a safe zone by ID.
  Future<void> deleteSafeZone(String zoneId) async {
    try {
      await _client.from(safeZonesTable).delete().eq('id', zoneId);
    } catch (e) {
      print('Error deleting safe zone: $e');
    }
  }

  // ──────────────────────────────────────────────
  // CLEANUP
  // ──────────────────────────────────────────────

  /// Remove all realtime subscriptions.
  Future<void> removeAllChannels() async {
    _client.removeAllChannels();
  }

  /// Remove a specific channel.
  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
