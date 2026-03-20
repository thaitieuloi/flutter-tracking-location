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
///   - messages      (id, family_id, user_id, content, image_url, location_lat, location_lng)
///   - notifications (id, user_id, title, body, type, read, metadata)
///   - sos_alerts    (id, user_id, latitude, longitude, message)
class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ── Table names (actual DB) ──────────────────────────────
  static const _tUsers          = 'users';
  static const _tFamilies       = 'families';
  static const _tFamilyMembers  = 'family_members';
  static const _tUserLocations  = 'user_locations';
  static const _tLatestLoc      = 'latest_locations';
  static const _tGeofences      = 'geofences';
  static const _tMessages       = 'messages';
  static const _tNotifications  = 'notifications';
  static const _tSosAlerts      = 'sos_alerts';

  // ── Auth ─────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<User?> signUp(String email, String password, String name, {String? inviteCode}) async {
    try {
      log('🔐 [Auth] signUp: $email | inviteCode: ${inviteCode ?? 'none'}');

      // Step 1: Create auth user (include invite_code for the DB trigger to handle)
      final res = await _client.auth.signUp(
        email: email, 
        password: password, 
        data: {
          'name': name,
          'invite_code': inviteCode,
        }
      );
      final user = res.user;
      if (user == null) return null;
      log('✅ [Auth] Auth user created: ${user.id}');

      // The rest of the setup (profiles, users, family membership if inviteCode exists) 
      // is now handled automatically by the Supabase DB Trigger.
      
      // We only need to handle NEW family creation if no invite code was provided
      if (inviteCode == null || inviteCode.trim().isEmpty) {
        log('📝 [DB] No invite code, will create fresh family later in getOrCreateFamilyId');
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
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      try {
        log('🔐 [Auth] Marking offline before signOut: $userId');
        await updateUserStatus(userId, 'offline');
      } catch (e) {
        log('⚠️ [Auth] Failed to set offline status on signOut: $e');
      }
    }
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

  Future<Family?> getFamilyInfo(String id) async {
    try {
      final data = await _client.from(_tFamilies).select('*').eq('id', id).maybeSingle();
      if (data == null) return null;
      return Family(
        id: data['id'],
        name: data['name'],
        createdBy: data['created_by'],
        members: [], // Members loaded separately in Provider
      );
    } catch (e) {
      log('❌ [DB] getFamilyInfo error: $e');
      return null;
    }
  }

  // ── Family ───────────────────────────────────────────────

  /// FIX: Get existing family_id from DB. Create new family ONLY if user has none.
  Future<String?> getOrCreateFamilyId(String userId, String userName) async {
    try {
      final userData = await _client.from(_tUsers).select('family_id').eq('id', userId).maybeSingle();
      String? familyId = userData?['family_id'] as String?;

      if (familyId != null && familyId.isNotEmpty) {
        log('✅ [DB] Existing family_id: $familyId');
        return familyId;
      }

      log('📝 [DB] No family found, creating new family for $userName');
      final code = _generateInviteCode(userName);
      final familyRes = await _client.from(_tFamilies).insert({
        'name': '$userName\'s Family',
        'created_by': userId,
        'invite_code': code,
      }).select('id').single();

      familyId = familyRes['id'] as String;

      await _client.from(_tUsers).update({'family_id': familyId}).eq('id', userId);

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
      await _client.from(_tUsers).update({'family_id': familyId}).eq('id', userId);

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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _fetchFamilyMembers(familyId).then(onData),
        )
        .subscribe((status, [error]) {
          log('📡 [Realtime] users_family status=$status error=$error');
        });
  }

  Future<List<FamilyMember>> _fetchFamilyMembers(String familyId) async {
    try {
      log('📡 [DB] fetchFamilyMembers for family: $familyId');
      
      List<dynamic> rows;
      try {
        // Attempt to fetch users and profiles in one go using join
        rows = await _client
            .from(_tUsers)
            .select('*, profiles!user_id(*)')
            .eq('family_id', familyId);
      } catch (joinErr) {
        log('⚠️ [DB] Joined fetch failed (likely missing FK): $joinErr. Falling back to separate queries.');
        
        // Fallback: Fetch users only
        rows = await _client
            .from(_tUsers)
            .select('*')
            .eq('family_id', familyId);
        
        if (rows.isNotEmpty) {
          final userIds = rows.map((r) => r['id'].toString()).toList();
          final profiles = await _client
              .from('profiles')
              .select('*')
              .inFilter('user_id', userIds);
          
          final profileMap = {for (var p in (profiles as List)) p['user_id'].toString(): p};
          
          // Merge profiles into rows
          for (var row in rows) {
            row['profiles'] = profileMap[row['id'].toString()];
          }
        }
      }

      final members = (rows as List).map((row) {
        // Safe access to joined profile
        final rawProfile = row['profiles'];
        final profile = (rawProfile is List && (rawProfile as List).isNotEmpty)
            ? (rawProfile as List).first
            : (rawProfile is Map ? rawProfile : null);
            
        final combined = Map<String, dynamic>.from(row);
        if (profile != null) {
          combined['status'] = profile['status'];
          if (profile['avatar_url'] != null) {
            combined['photo_url'] = profile['avatar_url'];
          }
          if (profile['display_name'] != null && profile['display_name'].toString().isNotEmpty) {
            combined['name'] = profile['display_name'];
          }
        }
        
        return _userRowToMember(combined);
      }).toList();
      log('✅ [DB] fetchFamilyMembers: ${members.length} members');
      return members;
    } catch (e) {
      log('❌ [DB] fetchFamilyMembers critical error: $e');
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

  /// Remove a member from family (admin only)
  Future<bool> removeFamilyMember(String memberId, String familyId) async {
    try {
      log('🗑️ [DB] removeFamilyMember: $memberId from $familyId');
      
      // Remove from family_members
      await _client.from(_tFamilyMembers)
          .delete()
          .eq('user_id', memberId)
          .eq('family_id', familyId);
      
      // Clear family_id in users table
      await _client.from(_tUsers)
          .update({'family_id': ''})
          .eq('id', memberId);

      log('✅ [DB] removeFamilyMember: removed $memberId');
      return true;
    } catch (e) {
      log('❌ [DB] removeFamilyMember error: $e');
      return false;
    }
  }

  /// Get user's role in a family
  Future<String?> getMemberRole(String userId, String familyId) async {
    try {
      final row = await _client.from(_tFamilyMembers)
          .select('role')
          .eq('user_id', userId)
          .eq('family_id', familyId)
          .maybeSingle();
      return row?['role'] as String?;
    } catch (e) {
      log('❌ [DB] getMemberRole error: $e');
      return null;
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
        'battery_level': location.batteryLevel,
        'updated_at': location.timestamp.toIso8601String(),
      }, onConflict: 'user_id');

      // Update last_seen on users table
      await _client
          .from(_tUsers)
          .update({'last_seen': location.timestamp.toIso8601String()})
          .eq('id', location.userId);

      log('✅ [DB] Location saved to user_locations + latest_locations + status updated');
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

  Future<List<UserLocation>> getLocationHistory(String userId, {int limit = 50, DateTime? startTime, DateTime? endTime}) async {
    try {
      log('📡 [DB] getLocationHistory: $userId (limit=$limit, start=$startTime, end=$endTime)');
      var query = _client
          .from(_tUserLocations)
          .select('user_id, latitude, longitude, accuracy, timestamp')
          .eq('user_id', userId);

      if (startTime != null) {
        query = query.gte('timestamp', startTime.toIso8601String());
      }
      if (endTime != null) {
        query = query.lte('timestamp', endTime.toIso8601String());
      }

      final rows = await query.order('timestamp', ascending: false).limit(limit);

      final list = (rows as List).map((r) => UserLocation(
        userId: r['user_id'] ?? userId,
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(r['timestamp']),
        accuracy: (r['accuracy'] as num?)?.toDouble(),
        address: null, // Column does not exist in DB yet
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

  // ── Notifications ────────────────────────────────────────

  Future<List<AppNotification>> getNotifications(String userId) async {
    try {
      log('📡 [DB] getNotifications for: $userId');
      final rows = await _client
          .from(_tNotifications)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);

      final list = (rows as List).map((r) => AppNotification.fromMap(r)).toList();
      log('✅ [DB] getNotifications: ${list.length}');
      return list;
    } catch (e) {
      log('❌ [DB] getNotifications error: $e');
      return [];
    }
  }

  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final rows = await _client
          .from(_tNotifications)
          .select('id')
          .eq('user_id', userId)
          .eq('read', false);
      return (rows as List).length;
    } catch (e) {
      log('❌ [DB] getUnreadNotificationCount error: $e');
      return 0;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client.from(_tNotifications).update({'read': true}).eq('id', notificationId);
      log('✅ [DB] markNotificationRead: $notificationId');
    } catch (e) {
      log('❌ [DB] markNotificationRead error: $e');
    }
  }

  Future<void> markAllNotificationsRead(String userId) async {
    try {
      await _client.from(_tNotifications)
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);
      log('✅ [DB] markAllNotificationsRead for $userId');
    } catch (e) {
      log('❌ [DB] markAllNotificationsRead error: $e');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _client.from(_tNotifications).delete().eq('id', notificationId);
      log('✅ [DB] deleteNotification: $notificationId');
    } catch (e) {
      log('❌ [DB] deleteNotification error: $e');
    }
  }

  RealtimeChannel subscribeNotifications({
    required String userId,
    required void Function(int unreadCount) onData,
  }) {
    log('📡 [Realtime] Subscribing to notifications for user: $userId');
    getUnreadNotificationCount(userId).then(onData);

    return _client
        .channel('notifs_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tNotifications,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => getUnreadNotificationCount(userId).then(onData),
        )
        .subscribe((status, [error]) {
          log('📡 [Realtime] notifications[$userId] status=$status error=$error');
        });
  }

  // ── SOS Alerts ───────────────────────────────────────────

  Future<bool> sendSosAlert({
    required String userId,
    required double latitude,
    required double longitude,
    String message = 'SOS - Cần giúp đỡ!',
  }) async {
    try {
      log('🚨 [DB] sendSosAlert: $userId');

      // Insert SOS alert record
      await _client.from(_tSosAlerts).insert({
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'message': message,
      });

      // Try to call Edge Function
      try {
        await _client.functions.invoke('send-sos-notification', body: {
          'user_id': userId,
          'latitude': latitude,
          'longitude': longitude,
          'message': message,
        });
        log('✅ [Edge] send-sos-notification called');
      } catch (e) {
        log('⚠️ [Edge] send-sos-notification failed (non-critical): $e');
      }

      log('✅ [DB] SOS alert saved');
      return true;
    } catch (e) {
      log('❌ [DB] sendSosAlert error: $e');
      return false;
    }
  }

  // ── Messages (Chat) ──────────────────────────────────────

  Future<List<ChatMessage>> getMessages(String familyId, {int limit = 100}) async {
    try {
      log('📡 [DB] getMessages for family: $familyId');
      final rows = await _client
          .from(_tMessages)
          .select()
          .eq('family_id', familyId)
          .order('created_at', ascending: true)
          .limit(limit);

      final list = (rows as List).map((r) => ChatMessage.fromMap(r)).toList();
      log('✅ [DB] getMessages: ${list.length}');
      return list;
    } catch (e) {
      log('❌ [DB] getMessages error: $e');
      return [];
    }
  }

  Future<ChatMessage?> sendMessage({
    required String familyId,
    required String userId,
    String? content,
    String? imageUrl,
    double? locationLat,
    double? locationLng,
  }) async {
    try {
      log('📝 [DB] sendMessage: $userId -> $familyId');
      final data = <String, dynamic>{
        'family_id': familyId,
        'user_id': userId,
      };
      if (content != null) data['content'] = content;
      if (imageUrl != null) data['image_url'] = imageUrl;
      if (locationLat != null) data['location_lat'] = locationLat;
      if (locationLng != null) data['location_lng'] = locationLng;

      final res = await _client.from(_tMessages).insert(data).select().single();
      log('✅ [DB] sendMessage success');
      return ChatMessage.fromMap(res);
    } catch (e) {
      log('❌ [DB] sendMessage error: $e');
      return null;
    }
  }

  RealtimeChannel subscribeMessages({
    required String familyId,
    required void Function(ChatMessage) onNewMessage,
  }) {
    log('📡 [Realtime] Subscribing to messages for family: $familyId');

    return _client
        .channel('messages_$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _tMessages,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              onNewMessage(ChatMessage.fromMap(payload.newRecord));
            }
          },
        )
        .subscribe((status, [error]) {
          log('📡 [Realtime] messages[$familyId] status=$status error=$error');
        });
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
      status: data['status'] ?? 'offline',
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

  Future<void> updateUserStatus(String userId, String status) async {
    try {
      log('🔄 [DB] updateUserStatus: $userId -> $status');
      await _client.from('profiles').update({'status': status}).eq('user_id', userId);
    } catch (e) {
      log('❌ [DB] updateUserStatus error: $e');
    }
  }

  void log(String message) {
    // ignore: avoid_print
    print(message);
  }
}
