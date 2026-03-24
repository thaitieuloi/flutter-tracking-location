import 'dart:developer';
import 'dart:io';
import 'package:flutter/services.dart';

/// Service that bridges Flutter credentials to the native Android layer.
/// This allows the native ProcessLifecycleOwner to send status updates
/// even when the Dart VM is being killed (swipe-to-close).
class NativeLifecycleService {
  static const _channel = MethodChannel('com.familytracker.app/lifecycle');

  /// Save Supabase credentials to native layer so it can send
  /// status updates independently of the Dart VM.
  static Future<void> saveCredentials({
    required String supabaseUrl,
    required String supabaseKey,
    required String userId,
    required String accessToken,
  }) async {
    if (!Platform.isAndroid) return; // Only needed on Android

    try {
      await _channel.invokeMethod('saveCredentials', {
        'supabaseUrl': supabaseUrl,
        'supabaseKey': supabaseKey,
        'userId': userId,
        'accessToken': accessToken,
      });
      log('✅ [NativeLifecycle] Credentials saved to native layer');
    } catch (e) {
      log('⚠️ [NativeLifecycle] Failed to save credentials: $e');
    }
  }

  /// Clear credentials from native layer (on sign-out).
  static Future<void> clearCredentials() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('clearCredentials');
      log('✅ [NativeLifecycle] Credentials cleared from native layer');
    } catch (e) {
      log('⚠️ [NativeLifecycle] Failed to clear credentials: $e');
    }
  }
}
