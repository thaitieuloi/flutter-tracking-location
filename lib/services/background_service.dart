import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:battery_plus/battery_plus.dart';
import '../config/supabase_config.dart';
import '../models/models.dart';

/// Top-level function for background service entry point.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter_background_service_android
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 1. Initialize Supabase in background isolate
  final prefs = await SharedPreferences.getInstance();
  
  final supabaseUrl = prefs.getString('supabase_url');
  final supabaseKey = prefs.getString('supabase_anon_key');
  final userId = prefs.getString('current_user_id');
  final sessionJson = prefs.getString('session_json');
  final accessToken = prefs.getString('access_token');   // fallback
  final refreshToken = prefs.getString('refresh_token'); // fallback

  if (supabaseUrl == null || supabaseKey == null || userId == null) {
    debugPrint('[BackgroundService] Missing essential credentials, stopping');
    service.stopSelf();
    return;
  }

  // 2. Set as Foreground IMMEDIATELY to avoid OS kill on startup
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Family Tracker",
      content: "Đang chia sẻ vị trí của bạn...",
    );
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
    
    // Authenticate using full session JSON (recoverSession expects JSON, NOT raw token string).
    // Fallback to access_token if session_json not yet saved (race condition on first launch).
    if (sessionJson != null) {
      try {
        await Supabase.instance.client.auth.recoverSession(sessionJson);
        debugPrint('[BackgroundService] Session recovered via session_json for $userId');
      } catch (recoverErr) {
        debugPrint('[BackgroundService] recoverSession failed: $recoverErr');
        // Fallback: set access token directly (works until expiry ~1h)
        if (accessToken != null) {
          try {
            await Supabase.instance.client.auth.setSession(accessToken);
            debugPrint('[BackgroundService] Fallback setSession OK for $userId');
          } catch (setErr) {
            debugPrint('[BackgroundService] setSession also failed: $setErr');
          }
        }
      }
    } else if (accessToken != null) {
      try {
        await Supabase.instance.client.auth.setSession(accessToken);
        debugPrint('[BackgroundService] Session set via access_token (no session_json yet) for $userId');
      } catch (e) {
        debugPrint('[BackgroundService] setSession failed: $e');
      }
    }
  } catch (e) {
    debugPrint('[BackgroundService] Supabase init or auth recovery error: $e');
  }

  final supabase = Supabase.instance.client;
  
  // Final verification of auth state before starting
  final session = supabase.auth.currentSession;
  if (session == null) {
    debugPrint('[BackgroundService] ⚠️ Critical: No session recovered for $userId. Tracking will likely fail.');
  } else {
    debugPrint('[BackgroundService] ✅ Auth verified. UID: ${supabase.auth.currentUser?.id}');
  }

  final battery = Battery();

  // Initial update - wrap in delayed to ensure auth state is propagated internally
  Future.delayed(const Duration(seconds: 2), () {
    _sendUpdate(service, supabase, battery, userId);
  });

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await _sendUpdate(service, supabase, battery, userId);
  });
}

Future<void> _sendUpdate(ServiceInstance service, SupabaseClient supabase, Battery battery, String userId) async {
  try {
    // Check auth state again before sending
    var currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      // Race condition: main app may not have saved session_json yet at first launch.
      // Re-read SharedPreferences and attempt recovery now.
      debugPrint('[BackgroundService] ⚠️ No auth user, attempting late recovery for $userId');
      try {
        final freshPrefs = await SharedPreferences.getInstance();
        final freshSessionJson = freshPrefs.getString('session_json');
        final freshAccessToken = freshPrefs.getString('access_token');
        if (freshSessionJson != null) {
          await supabase.auth.recoverSession(freshSessionJson);
        } else if (freshAccessToken != null) {
          await supabase.auth.setSession(freshAccessToken);
        }
        currentUser = supabase.auth.currentUser;
      } catch (e) {
        debugPrint('[BackgroundService] Late recovery failed: $e');
      }
    }
    if (currentUser == null) {
      debugPrint('[BackgroundService] ❌ Abort update: No authenticated user. (Exp: $userId)');
      return;
    }

    if (currentUser.id != userId) {
      debugPrint('[BackgroundService] ⚠️ User ID mismatch: Auth=${currentUser.id} vs Prefs=$userId');
      // Use the actual auth ID to avoid RLS violation
    }
    
    final activeUserId = currentUser.id;
    debugPrint('[BackgroundService] 🛰️ Sending update for UID: $activeUserId');

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
      forceAndroidLocationManager: true, // More robust for background
    );

    final batteryLevel = await battery.batteryLevel;

    // Only update location data — status is managed by lifecycle events in main.dart
    await Future.wait([
      supabase.from('latest_locations').upsert({
        'user_id': activeUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'battery_level': batteryLevel,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id'),
      supabase.from('user_locations').insert({
        'user_id': activeUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }),
    ]);


    if (service is AndroidServiceInstance) {
      final now = DateTime.now();
      service.setForegroundNotificationInfo(
        title: "Family Tracker - Đang hoạt động",
        content: "Cập nhật lúc: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
      );
    }
    debugPrint('[BackgroundService] Update successful for $userId');
  } catch (e) {
    debugPrint('[BackgroundService] Update error: $e');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
class BackgroundServiceManager {
  /// Initialize the background service.
  @pragma('vm:entry-point')
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'Family Tracker',
        initialNotificationContent: 'Đang khởi động chia sẻ vị trí...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }
}
