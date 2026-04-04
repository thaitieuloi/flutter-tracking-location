package com.familytracker.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * Service đặc biệt để xử lý các sự kiện vòng đời Native không thể làm từ Flutter.
 * Đặc biệt là sự kiện onTaskRemoved() khi người dùng vuốt thoát app (Swipe Close).
 */
class LifecycleService : Service() {

    companion object {
        private const val TAG = "LifecycleService"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🚀 LifecycleService started (START_STICKY)")
        // START_STICKY giúp service tự khởi động lại nếu bị OS kill vô cớ
        return START_STICKY
    }

    /**
     * SỰ KIỆN QUAN TRỌNG: Gọi khi người dùng vuốt app ra khỏi danh sách đa nhiệm.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "🎯 EVENT: App Swiped Away (Swipe thoát app)")
        
        // Gọi updateStatusSync("offline") vì BackgroundService không còn quản lý status nữa.
        // Status do Lifecycle thuần kiểm soát để tính toán thời gian chính xác.
        (application as? FamilyTrackerApp)?.updateStatusSync("offline")
        
        super.onTaskRemoved(rootIntent)
        
        // Dừng service sau khi đã xử lý xong
        stopSelf()
    }

    override fun onDestroy() {
        Log.d(TAG, "🛑 LifecycleService destroyed")
        super.onDestroy()
    }
}
