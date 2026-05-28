package com.ava.ava_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.app.FlutterApplication

class AvaApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        createChatNotificationChannel()
    }

    private fun createChatNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHAT_CHANNEL_ID,
            "AVA chat messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "AVA mobile chat notifications"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHAT_CHANNEL_ID = "ava_mobile_chat_push_v2"
    }
}
