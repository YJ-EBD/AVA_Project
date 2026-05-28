package com.ava.ava_flutter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.min

class AvaSelfPushForegroundService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder()
        .pingInterval(25, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private var socket: WebSocket? = null
    private var reconnectDelayMs = 1_500L
    private var heartbeatRunning = false

    private var apiBaseUrl = ""
    private var websocketUrl = ""
    private var accessToken = ""
    private var refreshToken = ""
    private var userId = ""
    private var deviceId = ""
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createServiceChannel()
        createChatChannel()
        loadState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelfPush()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                applyIntent(intent)
                if (accessToken.isBlank() || websocketUrl.isBlank()) {
                    stopSelfPush()
                    return START_NOT_STICKY
                }
                startInForeground()
                connect()
                return START_STICKY
            }
            else -> return START_STICKY
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "task removed; keeping self-hosted push service alive")
        if (accessToken.isNotBlank() && websocketUrl.isNotBlank()) {
            startInForeground()
            if (socket == null) {
                connect()
            }
            scheduleReconnect()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isRunning = false
        heartbeatRunning = false
        mainHandler.removeCallbacksAndMessages(null)
        socket?.cancel()
        socket = null
        releaseWakeLock()
        Log.i(TAG, "service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun applyIntent(intent: Intent?) {
        if (intent == null) {
            loadState()
            return
        }
        apiBaseUrl = intent.getStringExtra(EXTRA_API_BASE_URL)?.trim().orEmpty().ifBlank { apiBaseUrl }
        websocketUrl = intent.getStringExtra(EXTRA_WEBSOCKET_URL)?.trim().orEmpty().ifBlank { websocketUrl }
        accessToken = intent.getStringExtra(EXTRA_ACCESS_TOKEN)?.trim().orEmpty().ifBlank { accessToken }
        refreshToken = intent.getStringExtra(EXTRA_REFRESH_TOKEN)?.trim().orEmpty().ifBlank { refreshToken }
        userId = intent.getStringExtra(EXTRA_USER_ID)?.trim().orEmpty().ifBlank { userId }
        deviceId = intent.getStringExtra(EXTRA_DEVICE_ID)?.trim().orEmpty().ifBlank { deviceId }
        saveState()
    }

    private fun connect() {
        if (socket != null || websocketUrl.isBlank() || accessToken.isBlank()) {
            return
        }
        val request = Request.Builder()
            .url(websocketUrl)
            .addHeader("Authorization", "Bearer $accessToken")
            .build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                lastConnectedAtMillis = System.currentTimeMillis()
                Log.i(TAG, "websocket opened")
                reconnectDelayMs = 1_500L
                webSocket.send(
                    "CONNECT\naccept-version:1.2\nheart-beat:15000,15000\nAuthorization:Bearer $accessToken\n\n\u0000"
                )
                webSocket.send(
                    "SUBSCRIBE\nid:ava-self-push-0\ndestination:/user/queue/mobile-push\nack:auto\n\n\u0000"
                )
                startHeartbeat()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleStompText(text)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "websocket closed code=$code reason=$reason")
                socket = null
                heartbeatRunning = false
                scheduleReconnect()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w(TAG, "websocket failed code=${response?.code}", t)
                socket = null
                heartbeatRunning = false
                if (response?.code == 401 || response?.code == 403) {
                    refreshAccessToken()
                }
                scheduleReconnect()
            }
        })
    }

    private fun startHeartbeat() {
        if (heartbeatRunning) {
            return
        }
        heartbeatRunning = true
        mainHandler.post(object : Runnable {
            override fun run() {
                if (!heartbeatRunning) {
                    return
                }
                socket?.send("\n")
                mainHandler.postDelayed(this, 15_000L)
            }
        })
    }

    private fun scheduleReconnect() {
        mainHandler.removeCallbacksAndMessages(null)
        heartbeatRunning = false
        val delay = reconnectDelayMs
        reconnectDelayMs = min(reconnectDelayMs * 2, 30_000L)
        mainHandler.postDelayed({
            if (socket == null && accessToken.isNotBlank() && websocketUrl.isNotBlank()) {
                connect()
            }
        }, delay)
    }

    private fun refreshAccessToken() {
        if (apiBaseUrl.isBlank() || refreshToken.isBlank()) {
            return
        }
        try {
            val url = apiBaseUrl.trimEnd('/') + "/api/auth/refresh"
            val json = JSONObject().put("refreshToken", refreshToken).toString()
            val body = json.toRequestBody("application/json".toMediaType())
            val request = Request.Builder().url(url).post(body).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return
                }
                val payload = JSONObject(response.body?.string().orEmpty())
                accessToken = payload.optString("accessToken", accessToken)
                refreshToken = payload.optString("refreshToken", refreshToken)
                saveState()
            }
        } catch (_: Exception) {
            // Reconnect loop will retry later.
        }
    }

    private fun handleStompText(text: String) {
        val frames = text.split('\u0000')
        for (frame in frames) {
            val trimmed = frame.replace("\r\n", "\n").trim()
            if (!trimmed.startsWith("MESSAGE")) {
                continue
            }
            val separator = trimmed.indexOf("\n\n")
            if (separator < 0) {
                continue
            }
            val body = trimmed.substring(separator + 2).trim()
            if (body.isBlank()) {
                continue
            }
            showPush(JSONObject(body))
        }
    }

    private fun showPush(event: JSONObject) {
        lastEventAtMillis = System.currentTimeMillis()
        val type = event.optString("type")
        if (type != "chat_message" && type != "notification" && type != "azoom") {
            rememberEvent(event)
            return
        }
        rememberEvent(event)
        if (shouldSuppressActiveChatRoomPush(event)) {
            lastSuppressedNotificationAtMillis = System.currentTimeMillis()
            Log.i(
                TAG,
                "notification suppressed: active chat room=${event.optString("roomId", "")}"
            )
            return
        }
        if (!canPostNotifications()) {
            Log.w(TAG, "notification skipped: POST_NOTIFICATIONS is not granted")
            return
        }
        val eventId = event.optString("id", System.currentTimeMillis().toString())
        val title = event.optString("roomTitle").ifBlank { event.optString("title", "AVA") }
        val sender = event.optString("senderName").ifBlank { event.optString("title", "AVA") }
        val body = event.optString("body", "")
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("ava_push_event_id", eventId)
            putExtra("ava_push_room_id", pushRoomId(event))
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            eventId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, AvaApplication.CHAT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ava_notification_small)
            .setLargeIcon(appIconBitmap())
            .setContentTitle(title)
            .setContentText(if (sender.isBlank()) body else "$sender: $body")
            .setStyle(NotificationCompat.BigTextStyle().bigText(if (sender.isBlank()) body else "$sender: $body"))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setColor(ContextCompat.getColor(this, R.color.ava_notification_blue))
            .build()
        NotificationManagerCompat.from(this).notify(eventId.hashCode(), notification)
        lastNotificationAtMillis = System.currentTimeMillis()
        Log.i(TAG, "notification shown type=$type id=$eventId")
    }

    private fun shouldSuppressActiveChatRoomPush(event: JSONObject): Boolean {
        if (event.optString("type") != "chat_message" || !appInForeground) {
            return false
        }
        val activeRoom = activeChatRoomId.trim()
        if (activeRoom.isBlank()) {
            return false
        }
        val roomId = pushRoomId(event)
        return roomId.isNotBlank() && roomId == activeRoom
    }

    private fun pushRoomId(event: JSONObject): String {
        val data = event.optJSONObject("data")
        return event.optString("roomId")
            .ifBlank { data?.optString("roomCode").orEmpty() }
            .ifBlank { data?.optString("roomId").orEmpty() }
            .ifBlank { event.optString("sourceId", "") }
            .trim()
    }

    private fun rememberEvent(event: JSONObject) {
        val createdAt = event.optString("createdAt", "")
        if (createdAt.isBlank() || userId.isBlank()) {
            return
        }
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.ava.self_push.last_event_at.v1.$userId", createdAt)
            .apply()
    }

    private fun startInForeground() {
        acquireWakeLock()
        val notification = NotificationCompat.Builder(this, SERVICE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ava_notification_small)
            .setContentTitle("AVA realtime push connected")
            .setContentText("Receiving chat and AZOOM alerts in real time.")
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(ContextCompat.getColor(this, R.color.ava_notification_blue))
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                }
            }
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            )
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
    }

    private fun stopSelfPush() {
        socket?.close(1000, "stopped")
        socket = null
        heartbeatRunning = false
        mainHandler.removeCallbacksAndMessages(null)
        getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = (wakeLock ?: powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:AvaSelfPush"
        ).apply {
            setReferenceCounted(false)
        }).also { lock ->
            try {
                lock.acquire()
            } catch (_: Exception) {
            }
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {
        }
    }

    private fun createServiceChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            SERVICE_CHANNEL_ID,
            "AVA realtime push",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps AVA self-hosted push connected"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun createChatChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            AvaApplication.CHAT_CHANNEL_ID,
            "AVA chat messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "AVA mobile chat notifications"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            51_216,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun appIconBitmap(): Bitmap? {
        return BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
    }

    private fun saveState() {
        getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("apiBaseUrl", apiBaseUrl)
            .putString("websocketUrl", websocketUrl)
            .putString("accessToken", accessToken)
            .putString("refreshToken", refreshToken)
            .putString("userId", userId)
            .putString("deviceId", deviceId)
            .apply()
    }

    private fun loadState() {
        val prefs = getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
        apiBaseUrl = prefs.getString("apiBaseUrl", "").orEmpty()
        websocketUrl = prefs.getString("websocketUrl", "").orEmpty()
        accessToken = prefs.getString("accessToken", "").orEmpty()
        refreshToken = prefs.getString("refreshToken", "").orEmpty()
        userId = prefs.getString("userId", "").orEmpty()
        deviceId = prefs.getString("deviceId", "").orEmpty()
    }

    companion object {
        const val ACTION_START = "com.ava.ava_flutter.self_push.START"
        const val ACTION_STOP = "com.ava.ava_flutter.self_push.STOP"
        const val EXTRA_API_BASE_URL = "apiBaseUrl"
        const val EXTRA_WEBSOCKET_URL = "websocketUrl"
        const val EXTRA_ACCESS_TOKEN = "accessToken"
        const val EXTRA_REFRESH_TOKEN = "refreshToken"
        const val EXTRA_USER_ID = "userId"
        const val EXTRA_DEVICE_ID = "deviceId"

        private const val STATE_PREFS = "ava_self_push_state"
        private const val TAG = "AvaSelfPush"
        private const val SERVICE_CHANNEL_ID = "ava_self_push_service_v1"
        private const val SERVICE_NOTIFICATION_ID = 5216

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var lastConnectedAtMillis: Long = 0L

        @Volatile
        var lastEventAtMillis: Long = 0L

        @Volatile
        var lastNotificationAtMillis: Long = 0L

        @Volatile
        var lastSuppressedNotificationAtMillis: Long = 0L

        @Volatile
        var activeChatRoomId: String = ""

        @Volatile
        var appInForeground: Boolean = false
    }
}
