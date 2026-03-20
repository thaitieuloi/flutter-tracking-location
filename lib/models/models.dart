/// Data models for the Family Tracker app.
/// All models use plain Dart maps for Supabase compatibility.

class FamilyMember {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final String familyId;
  final bool isLocationSharing;
  final DateTime? lastSeen;
  final String status; // 'online', 'idle', 'offline'

  FamilyMember({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    required this.familyId,
    this.isLocationSharing = false,
    this.lastSeen,
    this.status = 'offline',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'photo_url': photoUrl,
      'family_id': familyId,
      'is_location_sharing': isLocationSharing,
      'last_seen': lastSeen?.toIso8601String(),
      'status': status,
    };
  }

  /// Create insert map (without id, let Supabase handle it via auth.uid)
  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'photo_url': photoUrl,
      'family_id': familyId,
      'is_location_sharing': isLocationSharing,
      // Status usually handled by profiles table, but included here for consistency if needed
    };
  }

  factory FamilyMember.fromMap(Map<String, dynamic> map) {
    return FamilyMember(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      photoUrl: map['photo_url'],
      familyId: map['family_id'] ?? '',
      isLocationSharing: map['is_location_sharing'] ?? false,
      lastSeen: map['last_seen'] != null
          ? DateTime.tryParse(map['last_seen'].toString())
          : null,
      status: map['status'] ?? 'offline',
    );
  }

  FamilyMember copyWith({
    String? id,
    String? name,
    String? email,
    String? photoUrl,
    String? familyId,
    bool? isLocationSharing,
    DateTime? lastSeen,
    String? status,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      familyId: familyId ?? this.familyId,
      isLocationSharing: isLocationSharing ?? this.isLocationSharing,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
    );
  }
}

class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracy;
  final String? address;
  final int? batteryLevel;

  UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.address,
    this.batteryLevel,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,
      'address': address,
      'battery_level': batteryLevel,
    };
  }

  factory UserLocation.fromMap(Map<String, dynamic> map) {
    return UserLocation(
      userId: map['user_id'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'].toString())
          : DateTime.now(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      address: map['address'],
      batteryLevel: map['battery_level'] as int?,
    );
  }
}

class SafeZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String familyId;
  final bool notifyOnEnter;
  final bool notifyOnExit;

  SafeZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.familyId,
    this.notifyOnEnter = true,
    this.notifyOnExit = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'family_id': familyId,
      'notify_on_enter': notifyOnEnter,
      'notify_on_exit': notifyOnExit,
    };
  }

  factory SafeZone.fromMap(Map<String, dynamic> map) {
    return SafeZone(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 100.0,
      familyId: map['family_id'] ?? '',
      notifyOnEnter: map['notify_on_enter'] ?? true,
      notifyOnExit: map['notify_on_exit'] ?? true,
    );
  }
}

class Family {
  final String id;
  final String name;
  final String createdBy;
  final List<String> members;
  final DateTime? createdAt;

  Family({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.members,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_by': createdBy,
      'members': members,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Family.fromMap(Map<String, dynamic> map) {
    return Family(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      createdBy: map['created_by'] ?? '',
      members: List<String>.from(map['members'] ?? []),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }
}

// ── Notification Model ──────────────────────────────────────

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type; // 'geofence' | 'sos' | 'battery_low' | 'inactivity_alert'
  final bool read;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.read = false,
    this.metadata = const {},
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: map['type'] ?? 'geofence',
      read: map['read'] ?? false,
      metadata: (map['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
    );
  }

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      userId: userId,
      title: title,
      body: body,
      type: type,
      read: read ?? this.read,
      metadata: metadata,
      createdAt: createdAt,
    );
  }
}

// ── Chat Message Model ──────────────────────────────────────

class ChatMessage {
  final String id;
  final String familyId;
  final String userId;
  final String? content;
  final String? imageUrl;
  final double? locationLat;
  final double? locationLng;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.familyId,
    required this.userId,
    this.content,
    this.imageUrl,
    this.locationLat,
    this.locationLng,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] ?? '',
      familyId: map['family_id'] ?? '',
      userId: map['user_id'] ?? '',
      content: map['content'],
      imageUrl: map['image_url'],
      locationLat: (map['location_lat'] as num?)?.toDouble(),
      locationLng: (map['location_lng'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'family_id': familyId,
      'user_id': userId,
      if (content != null) 'content': content,
      if (imageUrl != null) 'image_url': imageUrl,
      if (locationLat != null) 'location_lat': locationLat,
      if (locationLng != null) 'location_lng': locationLng,
    };
  }
}

// ── SOS Alert Model ─────────────────────────────────────────

class SosAlert {
  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final String message;
  final DateTime createdAt;

  SosAlert({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.message = 'SOS - Cần giúp đỡ!',
    required this.createdAt,
  });

  factory SosAlert.fromMap(Map<String, dynamic> map) {
    return SosAlert(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      message: map['message'] ?? 'SOS - Cần giúp đỡ!',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'message': message,
    };
  }
}
