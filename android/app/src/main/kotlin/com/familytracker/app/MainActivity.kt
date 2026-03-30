package com.familytracker.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity with a MethodChannel to receive credentials from Flutter
 * and pass them to the native FamilyTrackerApp for lifecycle-based status updates.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.familytracker.app/lifecycle"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 1. Pre-create Notification Channel for background tracking to avoid "Bad notification" crash on Android 14
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channelId = "my_foreground"
            val channelName = "Location Tracking"
            val channel = android.app.NotificationChannel(
                channelId, channelName, android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        // 2. Kích hoạt LifecycleService để giám sát việc vuốt thoát (Swipe)
        val serviceIntent = android.content.Intent(this, LifecycleService::class.java)
        startService(serviceIntent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveCredentials" -> {
                        val supabaseUrl = call.argument<String>("supabaseUrl")
                        val supabaseKey = call.argument<String>("supabaseKey")
                        val userId = call.argument<String>("userId")
                        val accessToken = call.argument<String>("accessToken")

                        if (supabaseUrl != null && supabaseKey != null && userId != null && accessToken != null) {
                            (application as? FamilyTrackerApp)?.saveCredentials(
                                supabaseUrl, supabaseKey, userId, accessToken
                            )
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "Missing required arguments", null)
                        }
                    }
                    "clearCredentials" -> {
                        (application as? FamilyTrackerApp)?.clearCredentials()
                        // Dừng LifecycleService ngay lập tức khi đăng xuất
                        val serviceIntent = android.content.Intent(this, LifecycleService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
