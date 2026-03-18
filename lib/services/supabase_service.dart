import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// SupabaseService aligned with actual DB schema:
///   - users         (id, email, name, family_id, is_location_sharing, last_seen)
///   - profiles      (id, user_id, display_name, avatar_url, push_token)
///   - families      (id, name, created_by, invite_code)
///   - family_members(id, user_id, family_id, role, joined_at)
///   - user_locations(id, user_id, latitude, longitude, accuracy, timestamp)
///   - latest_locations(user_id, latitude, longitude, accuracy, speed, heading, is_moving, updated_at)
///   - geofences     (id, name, family_id, latitude, longitude, radius_meters, created_by)
class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ── Table names (actual DB) ──────────────────────────────
  static const _tUsers          = 'users';
  static const _tFamilies       = 'families';
  static const _tFamilyMembers  = 'family_members';
  static const _tUserLocations  = 'user_locations';
  static const _tLatestLoc      = 'latest_locations';
  static const _tGeofences      = 'geofences';

  // ── Auth ─────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<User?> signUp(String email, String password, String name, {String? inviteCode}) async {
    try {
      log('🔐 [Auth] signUp: $email | inviteCode: ${inviteCode ?? 'none'}');

      // Step 1: Create auth user
      final res = await _client.auth.signUp(email: email, password: password, data: {'name': name});
      final user = res.user;
      if (user == null) return null;
      log('✅ [Auth] Auth user created: ${user.id}');

      String? familyId;
      String role = 'admin';

      // Step 2: Find or create family
      if (inviteCode != null && inviteCode.trim().isNotEmpty) {
        // Try to find family by invite code
        log('🔑 [DB] Looking up family by invite_code: $inviteCode');
        final familyRow = await _client
            .from(_tFamilies)
            .select('id, name')
            .eq('invite_code', inviteCode.trim().toUpperCase())
            .maybeSingle();

        if (familyRow != null) {
          familyId = familyRow['id'] as String;
          role = 'member';
          log('✅ [DB] Found family: ${familyRow['name']} ($familyId)');
        } else {
          log('⚠️ [DB] Invite code not found, creating new family');
        }
      }

      if (familyId == null) {
        // Create new family (generate a simple invite code)
        final code = _generateInviteCode(name);
        log('📝 [DB] Creating new family with invite_code: $code');
        final familyRes = await _client.from(_tFamilies).insert({
          'name': '$name\'s Family',
          'created_by': user.id,
          'invite_code': code,
        }).select('id').single();
        familyId = familyRes['id'] as String;
        log('✅ [DB] Family created: $familyId (code: $code)');
      }

      // Step 3: Insert user with family_id
      log('📝 [DB] Inserting user into users table');
      await _client.from(_tUsers).upsert({
        'id': user.id,
        'email': email,
        'name': name,
        'family_id': familyId,
        'is_location_sharing': true,
      });
      log('✅ [DB] User inserted | family: $familyId | role: $role');

      // Step 4: Try to add to family_members (optional, RLS may block)
      try {
        await _client.from(_tFamilyMembers).upsert({
          'user_id': user.id,
          'family_id': familyId,
          'role': role,
        });
        log('✅ [DB] Added to family_members as $role');
      } catch (e) {
        log('⚠️ [DB] family_members insert skipped (RLS): $e');
      }

      return user;
    } catch (e) {
      log('❌ [Auth] signUp error: $e');
      return null;
    }
  }

  String _generateInviteCode(String name) {
    final prefix = name.length >= 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
    final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    return '$prefix$suffix';
  }

  Future<User?> signIn(String email, String password) async {
    try {
      log('🔐 [Auth] signIn: $email');
      final res = await _client.auth.signInWithPassword(email: email, password: password);
      log('✅ [Auth] signIn success: ${res.user?.id}');
      return res.user;
    } catch (e) {
      log('❌ [Auth] signIn error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    log('🔐 [Auth] signOut');
    await _client.auth.signOut();
  }

  // ── User Info ────────────────────────────────────────────

  Future<FamilyMember?> getUserInfo(String userId) async {
    try {
      log('📡 [DB] getUserInfo: $userId');
      final data = await _client.from(_tUsers).select().eq('id', userId).maybeSingle();
      if (data == null) {
        log('⚠️ [DB] User not found in users table, will create profile');
        return null;
      }
      log('✅ [DB] getUserInfo: ${data['name']} | family_id=${data['family_id']}');
      return _userRowToMember(data);
    } catch (e) {
      log('❌ [DB] getUserInfo error: $e');
      return null;
    }
  }

  Future<void> toggleLocationSharing(String userId, bool enabled) async {
    try {
      log('🔄 [DB] toggleLocationSharing: $userId -> $enabled');
      await _client.from(_tUsers).update({'is_location_sharing': enabled}).eq('id', userId);
    } catch (e) {
      log('❌ [DB] toggleLocationSharing error: $e');
    }
  }

  // ── Family ───────────────────────────────────────────────

  /// FIX: Get existing family_id from DB. Create new family ONLY if user has none.
  /// Do NOT create new family on each login — that was the root bug.
  Future<String?> getOrCreateFamilyId(String userId, String userName) async {
    try {
      // Always read from DB first
      final userData = await _client.from(_tUsers).select('family_id').eq('id', userId).maybeSingle();
      String? familyId = userData?['family_id'] as String?;

      if (familyId != null && familyId.isNotEmpty) {
        log('✅ [DB] Existing family_id: $familyId');
        return familyId;
      }

      // Only create new family if user genuinely has no family_id
      log('📝 [DB] No family found, creating new family for $userName');
      final code = _generateInviteCode(userName);
      final familyRes = await _client.from(_tFamilies).insert({
        'name': '$userName\'s Family',
        'created_by': userId,
        'invite_code': code,
      }).select('id').single();

      familyId = familyRes['id'] as String;

      // Link user to family
      await _client.from(_tUsers).update({'family_id': familyId}).eq('id', userId);

      // Try to add self to family_members
      try {
        await _client.from(_tFamilyMembers).upsert({
          'user_id': userId,
          'family_id': familyId,
          'role': 'admin',
        });
      } catch (e) {
        log('⚠️ [DB] family_members insert skipped (RLS): $e');
      }

      log('✅ [DB] Created family: $familyId (code: $code)');
      return familyId;
    } catch (e) {
      log('❌ [DB] getOrCreateFamilyId error: $e');
      return null;
    }
  }

  /// Get the invite code for a family
  Future<String?> getInviteCode(String familyId) async {
    try {
      final row = await _client
          .from(_tFamilies)
          .select('invite_code, name')
          .eq('id', familyId)
          .maybeSingle();
      return row?['invite_code'] as String?;
    } catch (e) {
      log('❌ [DB] getInviteCode error: $e');
      return null;
    }
  }

  /// Join an existing family using invite code (for logged-in user)
  Future<bool> joinFamilyByCode(String userId, String inviteCode) async {
    try {
      log('🔑 [DB] joinFamilyByCode: $userId -> $inviteCode');
      final familyRow = await _client
          .from(_tFamilies)
          .select('id, name')
          .eq('invite_code', inviteCode.trim().toUpperCase())
          .maybeSingle();

      if (familyRow == null) {
        log('⚠️ [DB] Family not found for code: $inviteCode');
        return false;
      }

      final familyId = familyRow['id'] as String;

      // Update user's family_id
      await _client.from(_tUsers).update({'family_id': familyId}).eq('id', userId);

      // Add to family_members
      try {
        await _client.from(_tFamilyMembers).upsert({
          'user_id': userId,
          'family_id': familyId,
          'role': 'member',
        });
      } catch (e) {
        log('⚠️ [DB] family_members insert skipped (RLS): $e');
      }

      log('✅ [DB] joinFamilyByCode success: joined ${familyRow['name']}');
      return true;
    } catch (e) {
      log('❌ [DB] joinFamilyByCode error: $e');
      return false;
    }
  }

  RealtimeChannel subscribeFamilyMembers({
    required String familyId,
    required void Function(List<FamilyMember>) onData,
  }) {
    log('📡 [Realtime] Subscribing to users by family: $familyId');
    _fetchFamilyMembers(familyId).then(onData);

    return _client
        .channel('users_family_$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tUsers,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => _fetchFamilyMembers(familyId).then(onData),
        )
        .subscribe((status, [error]) {
          log('📡 [Realtime] users_family status=$status error=$error');
        });
  }

  Future<List<FamilyMember>> _fetchFamilyMembers(String familyId) async {
    try {
      log('📡 [DB] fetchFamilyMembers for family: $familyId');
      // Query users directly by family_id (simpler, no RLS issues)
      final rows = await _client
          .from(_tUsers)
          .select()
          .eq('family_id', familyId);

      final members = (rows as List).map((row) => _userRowToMember(row)).toList();
      log('✅ [DB] fetchFamilyMembers: ${members.length} members');
      return members;
    } catch (e) {
      log('❌ [DB] fetchFamilyMembers error: $e');
      return [];
    }
  }

  Future<bool> addFamilyMember(String email, String familyId) async {
    try {
      log('📝 [DB] addFamilyMember: $email to $familyId');
      final userRow = await _client.from(_tUsers).select('id').eq('email', email).maybeSingle();
      if (userRow == null) {
        log('⚠️ [DB] addFamilyMember: user not found with email $email');
        return false;
      }
      final memberId = userRow['id'] as String;
      await _client.from(_tUsers).update({'family_id': familyId}).eq('id', memberId);
      try {
        await _client.from(_tFamilyMembers).upsert({'user_id': memberId, 'family_id': familyId, 'role': 'member'});
      } catch (e) {
        log('⚠️ [DB] family_members insert skipped (RLS): $e');
      }
      log('✅ [DB] addFamilyMember: $email added');
      return true;
    } catch (e) {
      log('❌ [DB] addFamilyMember error: $e');
      return false;
    }
  }

  // ── Location ─────────────────────────────────────────────

  Future<void> updateUserLocation(UserLocation location) async {
    try {
      log('📍 [DB] updateUserLocation: ${location.userId} lat=${location.latitude} lng=${location.longitude}');

      // Insert into user_locations (history)
      await _client.from(_tUserLocations).insert({
        'user_id': location.userId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracy': location.accuracy,
        'timestamp': location.timestamp.toIso8601String(),
      });

      // Upsert into latest_locations (for realtime view / dashboard)
      await _client.from(_tLatestLoc).upsert({
        'user_id': location.userId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracy': location.accuracy,
        'updated_at': location.timestamp.toIso8601String(),
      }, onConflict: 'user_id');

      // Update last_seen on users table
      await _client
          .from(_tUsers)
          .update({'last_seen': location.timestamp.toIso8601String()})
          .eq('id', location.userId);

      log('✅ [DB] Location saved to user_locations + latest_locations');
    } catch (e) {
      log('❌ [DB] updateUserLocation error: $e');
    }
  }

  Future<UserLocation?> getUserLatestLocation(String userId) async {
    try {
      log('📡 [DB] getUserLatestLocation: $userId');
      final data = await _client.from(_tLatestLoc).select().eq('user_id', userId).maybeSingle();
      if (data == null) return null;
      return UserLocation(
        userId: userId,
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        timestamp: data['updated_at'] != null ? DateTime.parse(data['updated_at']) : DateTime.now(),
        accuracy: (data['accuracy'] as num?)?.toDouble(),
      );
    } catch (e) {
      log('❌ [DB] getUserLatestLocation error: $e');
      return null;
    }
  }

  /// Get location history for a user (last N records)
  Future<List<UserLocation>> getLocationHistory(String userId, {int limit = 50}) async {
    try {
      log('📡 [DB] getLocationHistory: $userId (limit=$limit)');
      final rows = await _client
          .from(_tUserLocations)
          .select('user_id, latitude, longitude, accuracy, timestamp')
          .eq('user_id', userId)
          .order('timestamp', ascending: false)
          .limit(limit);

      final list = (rows as List).map((r) => UserLocation(
        userId: r['user_id'] ?? userId,
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(r['timestamp']),
        accuracy: (r['accuracy'] as num?)?.toDouble(),
      )).toList();

      log('✅ [DB] getLocationHistory: ${list.length} records');
      return list;
    } catch (e) {
      log('❌ [DB] getLocationHistory error: $e');
      return [];
    }
  }

  RealtimeChannel subscribeMemberLocation({
    required String userId,
    required void Function(UserLocation?) onData,
  }) {
    log('📡 [Realtime] Subscribing to latest_locations for user: $userId');
    getUserLatestLocation(userId).then(onData);

    return _client
        .channel('latest_loc_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tLatestLoc,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            log('📍 [Realtime] location update for $userId: ${payload.newRecord}');
            if (payload.newRecord.isNotEmpty) {
              onData(UserLocation(
                userId: userId,
                latitude: (payload.newRecord['latitude'] as num).toDouble(),
                longitude: (payload.newRecord['longitude'] as num).toDouble(),
                timestamp: payload.newRecord['updated_at'] != null
                    ? DateTime.parse(payload.newRecord['updated_at'])
                    : DateTime.now(),
                accuracy: (payload.newRecord['accuracy'] as num?)?.toDouble(),
              ));
            }
          },
        )
        .subscribe((status, [error]) {
          log('📡 [Realtime] latest_locations[$userId] status=$status error=$error');
        });
  }

  // ── Geofences (Safe Zones) ───────────────────────────────

  RealtimeChannel subscribeGeofences({
    required String familyId,
    required void Function(List<SafeZone>) onData,
  }) {
    log('📡 [Realtime] Subscribing to geofences for family: $familyId');
    _fetchGeofences(familyId).then(onData);

    return _client
        .channel('geofences_$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tGeofences,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => _fetchGeofences(familyId).then(onData),
        )
        .subscribe();
  }

  Future<List<SafeZone>> _fetchGeofences(String familyId) async {
    try {
      final rows = await _client.from(_tGeofences).select().eq('family_id', familyId);
      return (rows as List).map((r) => SafeZone(
        id: r['id'].toString(),
        name: r['name'] ?? '',
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
        radiusMeters: (r['radius_meters'] as num?)?.toDouble() ?? 100.0,
        familyId: r['family_id'] ?? familyId,
      )).toList();
    } catch (e) {
      log('❌ [DB] fetchGeofences error: $e');
      return [];
    }
  }

  Future<void> createGeofence(SafeZone zone) async {
    try {
      log('📝 [DB] createGeofence: ${zone.name}');
      await _client.from(_tGeofences).insert({
        'name': zone.name,
        'family_id': zone.familyId,
        'latitude': zone.latitude,
        'longitude': zone.longitude,
        'radius_meters': zone.radiusMeters,
        'created_by': currentUser?.id,
      });
      log('✅ [DB] createGeofence: ${zone.name}');
    } catch (e) {
      log('❌ [DB] createGeofence error: $e');
    }
  }

  Future<void> deleteGeofence(String geofenceId) async {
    try {
      await _client.from(_tGeofences).delete().eq('id', geofenceId);
      log('✅ [DB] deleteGeofence: $geofenceId');
    } catch (e) {
      log('❌ [DB] deleteGeofence error: $e');
    }
  }

  // ── Cleanup ──────────────────────────────────────────────

  Future<void> removeAllChannels() async {
    await _client.removeAllChannels();
  }

  // ── Helpers ──────────────────────────────────────────────

  FamilyMember _userRowToMember(Map<String, dynamic> data) {
    return FamilyMember(
      id: data['id'] ?? '',
      name: data['name'] ?? 'Unknown',
      email: data['email'] ?? '',
      photoUrl: data['photo_url'],
      familyId: data['family_id'] ?? '',
      isLocationSharing: data['is_location_sharing'] ?? false,
      lastSeen: data['last_seen'] != null ? DateTime.tryParse(data['last_seen'].toString()) : null,
    );
  }

  Future<void> updateProfile({required String userId, String? name, String? photoUrl}) async {
    try {
      log('🔄 [DB] updateProfile: $userId');
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (photoUrl != null) updates['photo_url'] = photoUrl;

      if (updates.isEmpty) return;

      await _client.from(_tUsers).update(updates).eq('id', userId);
      log('✅ [DB] updateProfile success');
    } catch (e) {
      log('❌ [DB] updateProfile error: $e');
    }
  }

  void log(String message) {
    // ignore: avoid_print
    print(message);
  }
}
