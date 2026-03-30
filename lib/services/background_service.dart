import 'dart:async';
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
  final accessToken = prefs.getString('access_token');

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
    
    // Authenticate with access token if available
    if (accessToken != null) {
      // Use setSession to restore the authenticated state
      await Supabase.instance.client.auth.setSession(accessToken);
      debugPrint('[BackgroundService] Session recovered for $userId');
    }
  } catch (e) {
    debugPrint('[BackgroundService] Supabase init error: $e');
  }

  final supabase = Supabase.instance.client;
  final battery = Battery();

  // Initial update
  _sendUpdate(service, supabase, battery, userId);

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await _sendUpdate(service, supabase, battery, userId);
  });
}

Future<void> _sendUpdate(ServiceInstance service, SupabaseClient supabase, Battery battery, String userId) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
      forceAndroidLocationManager: true, // More robust for background
    );

    final batteryLevel = await battery.batteryLevel;

    // Parallel upsert and insert for stability
    await Future.wait([
      supabase.from('latest_locations').upsert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'battery_level': batteryLevel,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id'),
      supabase.from('user_locations').insert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }),
      // Also refresh presence status
      supabase.from('profiles').update({
        'status': 'online',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId)
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
