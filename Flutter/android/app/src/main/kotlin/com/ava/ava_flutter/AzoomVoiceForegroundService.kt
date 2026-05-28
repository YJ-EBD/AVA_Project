package com.ava.ava_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min

class AzoomVoiceForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "ava_azoom_voice_call_v6"
        const val CHANNEL_NAME = "AZOOM voice call"
        const val CHANNEL_DESCRIPTION = "Ongoing AZOOM voice channel controls"
        private const val NOTIFICATION_ID = 4208
        private const val HEARTBEAT_INTERVAL_MS = 3_000L
        private const val ACTION_TOGGLE_MIC = "com.ava.ava_flutter.AZOOM_TOGGLE_MIC"
        private const val ACTION_TOGGLE_DEAFEN = "com.ava.ava_flutter.AZOOM_TOGGLE_DEAFEN"
        private const val ACTION_LEAVE = "com.ava.ava_flutter.AZOOM_LEAVE"
        private const val ACTION_OPEN = "com.ava.ava_flutter.AZOOM_OPEN"
        private const val ACTION_FULLSCREEN = "com.ava.ava_flutter.AZOOM_FULLSCREEN"
        private const val NOTIFICATION_TITLE = "\uC74C\uC131 \uC5F0\uACB0\uB428 \u2014 \uD0ED\uD558\uC5EC \uD1B5\uD654\uB85C \uB3CC\uC544\uAC00\uAE30"
        private const val ACTION_LABEL_LEAVE = "\uC5F0\uACB0 \uB04A\uAE30"
        private const val ACTION_LABEL_MUTE = "\uC74C\uC18C\uAC70"
        private const val ACTION_LABEL_UNMUTE = "\uC74C\uC18C\uAC70 \uD574\uC81C"
        private const val ACTION_LABEL_DEAFEN = "\uD5E4\uB4DC\uC14B \uC74C\uC18C\uAC70"
        private const val ACTION_LABEL_UNDEAFEN = "\uD5E4\uB4DC\uC14B \uCF1C\uAE30"

        var methodChannel: MethodChannel? = null
        private val mainHandler = Handler(Looper.getMainLooper())
        private val pendingActions = mutableListOf<String>()

        fun emitFlutterAction(action: String) {
            mainHandler.post {
                val channel = methodChannel
                if (channel == null) {
                    pendingActions.add(action)
                } else {
                    channel.invokeMethod("azoomVoiceAction", mapOf("action" to action))
                }
            }
        }

        fun drainPendingActions() {
            mainHandler.post {
                val channel = methodChannel ?: return@post
                val copy = pendingActions.toList()
                pendingActions.clear()
                copy.forEach { action ->
                    channel.invokeMethod("azoomVoiceAction", mapOf("action" to action))
                }
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var overlayExpanded = false
    private var heartbeatRunnable: Runnable? = null

    private var apiBaseUrl = ""
    private var accessToken = ""
    private var channelId = ""
    private var channelName = "AZOOM"
    private var participantName = ""
    private var avatarColor = "#5865F2"
    private var avatarImageUrl = ""
    private var muted = false
    private var deafened = false
    private var cameraEnabled = false
    private var screenSharing = false
    private var overlayEnabled = true
    private var notificationStartedAt = 0L
    private var leaveRequested = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            return START_NOT_STICKY
        }
        when (intent?.action) {
            ACTION_TOGGLE_MIC -> {
                muted = !muted
                updateSurfaces()
                heartbeatOnce()
                emitFlutterAction("toggleMic")
            }
            ACTION_TOGGLE_DEAFEN -> {
                deafened = !deafened
                muted = deafened
                updateSurfaces()
                heartbeatOnce()
                emitFlutterAction("toggleDeafen")
            }
            ACTION_LEAVE -> {
                leaveOnce(waitForCompletion = true)
                emitFlutterAction("leave")
                stopSelf()
            }
            ACTION_OPEN -> {
                launchMain("open")
                emitFlutterAction("open")
            }
            ACTION_FULLSCREEN -> {
                launchMain("fullscreen")
                emitFlutterAction("fullscreen")
            }
            else -> {
                val command = intent?.getStringExtra("command") ?: "start"
                if (command == "stop") {
                    leaveOnce(waitForCompletion = true)
                    stopSelf()
                    return START_NOT_STICKY
                }
                leaveRequested = false
                val wasRunning = notificationStartedAt != 0L
                val changed = applyExtras(intent)
                if (!wasRunning) {
                    notificationStartedAt = System.currentTimeMillis()
                    startForegroundCompat(buildReliableVoiceNotification())
                    scheduleNotificationRefresh()
                    updateOverlaySurface()
                    startHeartbeat()
                } else {
                    if (changed) {
                        updateSurfaces()
                    } else if (overlayEnabled && overlayView == null) {
                        ensureOverlay()
                    } else if (!overlayEnabled && overlayView != null) {
                        removeOverlay()
                    }
                    if (heartbeatRunnable == null) {
                        startHeartbeat()
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopHeartbeat()
        removeOverlay()
        leaveOnce(waitForCompletion = true)
        stopForegroundCompat()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        leaveOnce(waitForCompletion = true)
        stopForegroundCompat()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun applyExtras(intent: Intent?): Boolean {
        if (intent == null) return false
        val nextApiBaseUrl = intent.getStringExtra("apiBaseUrl") ?: apiBaseUrl
        val nextAccessToken = intent.getStringExtra("accessToken") ?: accessToken
        val nextChannelId = intent.getStringExtra("channelId") ?: channelId
        val nextChannelName = intent.getStringExtra("channelName") ?: channelName
        val nextParticipantName = intent.getStringExtra("participantName") ?: participantName
        val nextAvatarColor = intent.getStringExtra("avatarColor") ?: avatarColor
        val nextAvatarImageUrl = intent.getStringExtra("avatarImageUrl") ?: avatarImageUrl
        val nextMuted = intent.getBooleanExtra("muted", muted)
        val nextDeafened = intent.getBooleanExtra("deafened", deafened)
        val nextCameraEnabled = intent.getBooleanExtra("cameraEnabled", cameraEnabled)
        val nextScreenSharing = intent.getBooleanExtra("screenSharing", screenSharing)
        val nextOverlayEnabled = intent.getBooleanExtra("overlayEnabled", overlayEnabled)
        val changed = nextApiBaseUrl != apiBaseUrl ||
            nextAccessToken != accessToken ||
            nextChannelId != channelId ||
            nextChannelName != channelName ||
            nextParticipantName != participantName ||
            nextAvatarColor != avatarColor ||
            nextAvatarImageUrl != avatarImageUrl ||
            nextMuted != muted ||
            nextDeafened != deafened ||
            nextCameraEnabled != cameraEnabled ||
            nextScreenSharing != screenSharing ||
            nextOverlayEnabled != overlayEnabled
        apiBaseUrl = nextApiBaseUrl
        accessToken = nextAccessToken
        channelId = nextChannelId
        channelName = nextChannelName
        participantName = nextParticipantName
        avatarColor = nextAvatarColor
        avatarImageUrl = nextAvatarImageUrl
        muted = nextMuted
        deafened = nextDeafened
        cameraEnabled = nextCameraEnabled
        screenSharing = nextScreenSharing
        overlayEnabled = nextOverlayEnabled
        return changed
    }

    private fun updateSurfaces() {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildReliableVoiceNotification())
        updateOverlaySurface()
    }

    private fun updateOverlaySurface() {
        if (overlayEnabled) {
            if (overlayView == null) {
                ensureOverlay()
            } else {
                updateOverlay()
            }
        } else {
            removeOverlay()
        }
    }

    private fun scheduleNotificationRefresh() {
        handler.postDelayed({ notifyReliableVoiceNotification() }, 450)
        handler.postDelayed({ notifyReliableVoiceNotification() }, 1_800)
    }

    private fun notifyReliableVoiceNotification() {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildReliableVoiceNotification())
    }

    private fun buildReliableVoiceNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            21,
            mainActivityIntent("fullscreen"),
            pendingFlags()
        )
        val micIntent = PendingIntent.getService(
            this,
            22,
            Intent(this, AzoomVoiceForegroundService::class.java).setAction(ACTION_TOGGLE_MIC),
            pendingFlags()
        )
        val deafenIntent = PendingIntent.getService(
            this,
            23,
            Intent(this, AzoomVoiceForegroundService::class.java).setAction(ACTION_TOGGLE_DEAFEN),
            pendingFlags()
        )
        val leaveIntent = PendingIntent.getService(
            this,
            24,
            Intent(this, AzoomVoiceForegroundService::class.java).setAction(ACTION_LEAVE),
            pendingFlags()
        )
        val text = channelName.ifBlank { "AZOOM" }
        val startedAt = if (notificationStartedAt == 0L) {
            System.currentTimeMillis()
        } else {
            notificationStartedAt
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ava_notification_small)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher))
            .setContentTitle(NOTIFICATION_TITLE)
            .setContentText(text)
            .setSubText("AZOOM")
            .setOngoing(true)
            .setAutoCancel(false)
            .setLocalOnly(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(startedAt)
            .setUsesChronometer(false)
            .setContentIntent(openIntent)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(Color.rgb(35, 135, 242))
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(NOTIFICATION_TITLE)
                    .bigText(text)
            )
            .addAction(R.drawable.ava_notification_small, ACTION_LABEL_LEAVE, leaveIntent)
            .addAction(
                R.drawable.ava_notification_small,
                if (muted) ACTION_LABEL_UNMUTE else ACTION_LABEL_MUTE,
                micIntent
            )
            .addAction(
                R.drawable.ava_notification_small,
                if (deafened) ACTION_LABEL_UNDEAFEN else ACTION_LABEL_DEAFEN,
                deafenIntent
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build().apply {
            flags = flags or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR
        }
    }

    private fun ensureOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            removeOverlay()
            return
        }
        if (overlayView != null) {
            updateOverlay()
            return
        }
        val view = createOverlayView()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            dp(if (overlayExpanded) 178 else 112),
            dp(if (overlayExpanded) 174 else 112),
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - dp(128)
            y = dp(92)
        }
        overlayView = view
        overlayParams = params
        windowManager?.addView(view, params)
    }

    private fun updateOverlay() {
        val view = overlayView ?: return
        val params = overlayParams ?: return
        val newWidth = dp(if (overlayExpanded) 178 else 112)
        val newHeight = dp(if (overlayExpanded) 174 else 112)
        if (params.width != newWidth || params.height != newHeight) {
            params.width = newWidth
            params.height = newHeight
            windowManager?.updateViewLayout(view, params)
        }
        val container = view as? LinearLayout ?: return
        container.removeAllViews()
        populateOverlay(container)
    }

    private fun removeOverlay() {
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
        overlayView = null
        overlayParams = null
    }

    private fun createOverlayView(): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = rounded(Color.rgb(243, 230, 181), dp(22).toFloat())
        }
        populateOverlay(container)
        var startX = 0
        var startY = 0
        var downRawX = 0f
        var downRawY = 0f
        var moved = false
        container.setOnTouchListener { _, event ->
            val params = overlayParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    downRawX = event.rawX
                    downRawY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downRawX).toInt()
                    val dy = (event.rawY - downRawY).toInt()
                    if (kotlin.math.abs(dx) > 4 || kotlin.math.abs(dy) > 4) moved = true
                    params.x = clamp(startX + dx, 0, resources.displayMetrics.widthPixels - params.width)
                    params.y = clamp(startY + dy, 0, resources.displayMetrics.heightPixels - params.height)
                    windowManager?.updateViewLayout(container, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        overlayExpanded = !overlayExpanded
                        updateOverlay()
                    }
                    true
                }
                else -> false
            }
        }
        return container
    }

    private fun populateOverlay(container: LinearLayout) {
        if (overlayExpanded) {
            val top = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            top.addView(label(channelName.ifBlank { "AZOOM" }, 0, 12, true), LinearLayout.LayoutParams(0, dp(32), 1f))
            top.addView(button("[]") {
                launchMain("fullscreen")
                emitFlutterAction("fullscreen")
            })
            container.addView(top, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(34)))
        }
        container.addView(avatarView(), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        if (overlayExpanded) {
            val bottom = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }
            bottom.addView(button(if (muted) "M-" else "M") {
                muted = !muted
                updateSurfaces()
                heartbeatOnce()
                emitFlutterAction("toggleMic")
            })
            bottom.addView(button(if (deafened) "H-" else "H") {
                deafened = !deafened
                muted = deafened
                updateSurfaces()
                heartbeatOnce()
                emitFlutterAction("toggleDeafen")
            })
            bottom.addView(button("X", danger = true) {
                emitFlutterAction("leave")
                stopSelf()
            })
            container.addView(bottom, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)))
        }
    }

    private fun avatarView(): View {
        val initial = participantName.trim().take(1).ifBlank { "A" }
        return TextView(this).apply {
            text = initial
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = if (overlayExpanded) 24f else 28f
            typeface = Typeface.DEFAULT_BOLD
            background = rounded(parseColor(avatarColor), dp(42).toFloat())
        }
    }

    private fun button(textValue: String, danger: Boolean = false, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = rounded(if (danger) Color.rgb(218, 55, 60) else Color.rgb(58, 60, 67), dp(12).toFloat())
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(dp(42), dp(34)).apply {
                marginStart = dp(4)
                marginEnd = dp(4)
            }
        }
    }

    private fun label(value: String, color: Int, size: Int, bold: Boolean): TextView {
        return TextView(this).apply {
            text = value
            setTextColor(if (color == 0) Color.rgb(41, 43, 49) else color)
            textSize = size.toFloat()
            maxLines = 1
            if (bold) typeface = Typeface.DEFAULT_BOLD
        }
    }

    private fun startHeartbeat() {
        stopHeartbeat()
        heartbeatOnce()
        val runnable = object : Runnable {
            override fun run() {
                heartbeatOnce()
                handler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
            }
        }
        heartbeatRunnable = runnable
        handler.postDelayed(runnable, HEARTBEAT_INTERVAL_MS)
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let { handler.removeCallbacks(it) }
        heartbeatRunnable = null
    }

    private fun heartbeatOnce() {
        request("PUT", "status")
    }

    private fun leaveOnce(waitForCompletion: Boolean = false) {
        val base = apiBaseUrl.trim()
        val token = accessToken.trim()
        val id = channelId.trim()
        if (base.isEmpty() || token.isEmpty() || id.isEmpty()) {
            return
        }
        if (leaveRequested) {
            return
        }
        leaveRequested = true
        request("POST", "leave", waitForCompletion)
    }

    private fun request(
        method: String,
        endpoint: String,
        waitForCompletion: Boolean = false
    ) {
        val base = apiBaseUrl.trim().trimEnd('/')
        val token = accessToken.trim()
        val id = channelId.trim()
        if (base.isEmpty() || token.isEmpty() || id.isEmpty()) return
        val latch = CountDownLatch(1)
        thread(start = true) {
            try {
                val url = URL("$base/api/azoom/voice-channels/$id/$endpoint")
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    connectTimeout = 8_000
                    readTimeout = 8_000
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "application/json")
                    if (method == "PUT") {
                        doOutput = true
                    }
                }
                if (method == "PUT") {
                    val body = """{"muted":$muted,"deafened":$deafened,"cameraEnabled":$cameraEnabled,"screenSharing":$screenSharing}"""
                    connection.outputStream.use { output ->
                        output.write(body.toByteArray(Charsets.UTF_8))
                    }
                }
                val code = connection.responseCode
                if (code >= 400) {
                    connection.errorStream?.close()
                } else {
                    connection.inputStream?.close()
                }
                connection.disconnect()
            } catch (_: Exception) {
            } finally {
                latch.countDown()
            }
        }
        if (waitForCompletion) {
            try {
                latch.await(5, TimeUnit.SECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }

    private fun launchMain(action: String) {
        startActivity(mainActivityIntent(action))
    }

    private fun mainActivityIntent(action: String): Intent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        return intent.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("azoomVoiceAction", action)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        listOf(
            "ava_azoom_voice_call",
            "ava_azoom_voice_call_v2",
            "ava_azoom_voice_call_v3",
            "ava_azoom_voice_call_v4",
            "ava_azoom_voice_call_v5"
        ).forEach { oldChannelId ->
            manager.deleteNotificationChannel(oldChannelId)
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = CHANNEL_DESCRIPTION
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun pendingFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }

    private fun rounded(color: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
        }
    }

    private fun parseColor(value: String): Int {
        return try {
            Color.parseColor(value.ifBlank { "#5865F2" })
        } catch (_: Exception) {
            Color.rgb(88, 101, 242)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun clamp(value: Int, minValue: Int, maxValue: Int): Int {
        return max(minValue, min(value, maxValue))
    }
}
