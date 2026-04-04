package com.familytracker.app

import android.app.Application
import android.content.SharedPreferences
import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import java.net.HttpURLConnection
import java.net.URL

/**
 * Custom Application class that uses ProcessLifecycleOwner to detect
 * when the app goes to background/is killed.
 *
 * Why native Android instead of Flutter?
 * When a user swipes to kill the app, Flutter's AppLifecycleState.detached fires
 * but the Dart VM is killed before the async HTTP request can complete.
 * ProcessLifecycleOwner.onStop() fires BEFORE the process is killed,
 * giving us a window to send a synchronous HTTP request.
 */
class FamilyTrackerApp : Application() {

    companion object {
        private const val TAG = "FamilyTrackerApp"
        private const val PREFS_NAME = "family_tracker_prefs"
        private const val KEY_SUPABASE_URL = "supabase_url"
        private const val KEY_SUPABASE_KEY = "supabase_anon_key"
        private const val KEY_USER_ID = "current_user_id"
        private const val KEY_ACCESS_TOKEN = "access_token"
    }

    private lateinit var prefs: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {

            override fun onStart(owner: LifecycleOwner) {
                // HÀNH ĐỘNG 1: Mở app hoặc quay lại từ nền
                Log.d(TAG, "🟢 EVENT: App Foregrounded (Cả Home & Switcher -> Foreground)")
                updateStatusSync("online")
            }

            override fun onStop(owner: LifecycleOwner) {
                // HÀNH ĐỘNG 2: Nhấn Home hoặc Chuyển App (Task Switcher)
                // Lưu ý: ProcessLifecycleOwner sẽ gọi onStop khi app KHÔNG CÒN HIỆN DIỆN TRƯỚC MẶT.
                Log.d(TAG, "🟠 EVENT: App Backgrounded (Home / App Switcher)")
                updateStatusSync("idle")
            }
        })
    }

    /**
     * Save credentials from Flutter side so that the native layer
     * can send status updates independently of the Dart VM.
     */
    fun saveCredentials(supabaseUrl: String, supabaseKey: String, userId: String, accessToken: String) {
        prefs.edit()
            .putString(KEY_SUPABASE_URL, supabaseUrl)
            .putString(KEY_SUPABASE_KEY, supabaseKey)
            .putString(KEY_USER_ID, userId)
            .putString(KEY_ACCESS_TOKEN, accessToken)
            .apply()
        Log.d(TAG, "✅ Credentials saved for native status updates (userId: $userId)")
    }

    fun clearCredentials() {
        prefs.edit().clear().apply()
        Log.d(TAG, "🗑️ Credentials cleared")
    }

    /**
     * Send a SYNCHRONOUS HTTP request to update user status.
     * This runs on the calling thread (ProcessLifecycleOwner callback).
     * Android gives us a few seconds in onStop() before killing the process.
     */
    fun updateStatusSync(status: String) {
        val supabaseUrl = prefs.getString(KEY_SUPABASE_URL, null)
        val supabaseKey = prefs.getString(KEY_SUPABASE_KEY, null)
        val userId = prefs.getString(KEY_USER_ID, null)
        val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)

        if (supabaseUrl == null || supabaseKey == null || userId == null || accessToken == null) {
            Log.w(TAG, "⚠️ Missing credentials, cannot update status to: $status")
            return
        }

        // Run on a background thread but block until complete (sync-ish)
        Thread {
            try {
                val url = URL("$supabaseUrl/rest/v1/profiles?user_id=eq.$userId")
                val conn = url.openConnection() as HttpURLConnection

                conn.requestMethod = "PATCH"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("apikey", supabaseKey)
                conn.setRequestProperty("Authorization", "Bearer $accessToken")
                conn.setRequestProperty("Prefer", "return=minimal")
                conn.connectTimeout = 3000 // 3 seconds max
                conn.readTimeout = 3000
                conn.doOutput = true

                val body = """{"status":"$status"}"""
                conn.outputStream.use { it.write(body.toByteArray()) }

                val responseCode = conn.responseCode
                Log.d(TAG, "✅ Status update to '$status' completed: HTTP $responseCode")

                conn.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to update status to '$status': ${e.message}")
            }
        }.apply {
            start()
            try {
                join(4000) // Wait max 4 seconds for the request to complete
            } catch (e: InterruptedException) {
                Log.w(TAG, "⚠️ Status update thread interrupted")
            }
        }
    }
}
