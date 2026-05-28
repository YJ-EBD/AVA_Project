package com.ava.ava_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.media.MediaScannerConnection
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val androidUpdateChannel = "ava/android_update"
    private val azoomVoiceChannel = "ava/azoom_voice"
    private val mobileAudioChannel = "ava/mobile_audio"
    private val windowChannel = "ava/window"
    private val selfPushChannel = "ava/self_push"
    private var azoomVoiceMethodChannel: MethodChannel? = null
    private var windowMethodChannel: MethodChannel? = null
    private var windowCallbacksReady = false
    private var mobileAudioPlayer: MediaPlayer? = null

    companion object {
        private const val CHAT_CHANNEL_ID = "ava_mobile_chat_push_v2"
        private const val DOWNLOAD_CHANNEL_ID = "ava_attachment_downloads_v2"
        private const val CHAT_REPLY_KEY = "ava_chat_reply_text"
        private const val ACTION_CHAT_OPEN = "com.ava.ava_flutter.CHAT_OPEN"
        private const val ACTION_CHAT_REPLY = "com.ava.ava_flutter.CHAT_REPLY"
        private const val EXTRA_ROOM_ID = "roomId"
        private const val EXTRA_NOTIFICATION_ID = "notificationId"

        private val pendingWindowActions = mutableListOf<Pair<String, Map<String, Any?>>>()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        pruneOversizedFlutterSharedPreferences()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, androidUpdateChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateDownloadDirectory" -> updateDownloadDirectory(result)
                "saveApkToDownloads" -> saveApkToDownloads(
                    call.argument<String>("path"),
                    call.argument<String>("fileName"),
                    result
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, selfPushChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(startSelfHostedPush(call.arguments as? Map<*, *>))
                "stop" -> {
                    stopService(Intent(this, AvaSelfPushForegroundService::class.java).apply {
                        action = AvaSelfPushForegroundService.ACTION_STOP
                    })
                    result.success(null)
                }
                "status" -> result.success(
                    mapOf(
                        "running" to AvaSelfPushForegroundService.isRunning,
                        "lastConnectedAtMillis" to AvaSelfPushForegroundService.lastConnectedAtMillis,
                        "lastEventAtMillis" to AvaSelfPushForegroundService.lastEventAtMillis,
                        "lastNotificationAtMillis" to AvaSelfPushForegroundService.lastNotificationAtMillis,
                        "lastSuppressedNotificationAtMillis" to AvaSelfPushForegroundService.lastSuppressedNotificationAtMillis,
                        "activeChatRoomId" to AvaSelfPushForegroundService.activeChatRoomId,
                        "appInForeground" to AvaSelfPushForegroundService.appInForeground,
                    )
                )
                "setActiveChatRoom" -> {
                    setActiveChatRoom(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mobileAudioChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> playMobileAudio(call.argument<String>("path"), result)
                "stop" -> {
                    stopMobileAudio()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val windowChannelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, windowChannel)
        windowMethodChannel = windowChannelInstance
        windowChannelInstance.setMethodCallHandler { call, result ->
            when (call.method) {
                "windowReady" -> {
                    windowCallbacksReady = true
                    drainPendingWindowActions()
                    result.success(null)
                }
                "showChatNotification" -> {
                    result.success(showChatNotification(call.arguments as? Map<*, *>))
                }
                "saveAttachmentToMediaStore" -> saveAttachmentToMediaStore(
                    call.argument<String>("sourcePath"),
                    call.argument<String>("fileName"),
                    call.argument<String>("mimeType"),
                    call.argument<Boolean>("notify") ?: false,
                    result
                )
                "isAvaForeground" -> {
                    result.success(hasWindowFocus())
                }
                else -> result.notImplemented()
            }
        }
        val voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, azoomVoiceChannel)
        azoomVoiceMethodChannel = voiceChannel
        AzoomVoiceForegroundService.methodChannel = voiceChannel
        voiceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSession" -> {
                    startAzoomVoiceService("start", call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "updateSession" -> {
                    startAzoomVoiceService("update", call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "stopSession" -> {
                    startAzoomVoiceService("stop", null)
                    result.success(null)
                }
                "areNotificationsEnabled" -> {
                    result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                }
                "areVoiceNotificationsEnabled" -> {
                    result.success(areVoiceNotificationsEnabled())
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "openVoiceNotificationSettings" -> {
                    openVoiceNotificationSettings()
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        AzoomVoiceForegroundService.drainPendingActions()
        deliverAzoomActionFromIntent(intent)
        deliverWindowActionFromIntent(intent)
        handleDebugNotificationIntent(intent)
        handleDebugVoiceServiceIntent(intent)
    }

    private fun pruneOversizedFlutterSharedPreferences() {
        try {
            val prefsFile = File(applicationInfo.dataDir, "shared_prefs/FlutterSharedPreferences.xml")
            if (!prefsFile.isFile || prefsFile.length() <= 8L * 1024L * 1024L) {
                return
            }
            val backup = File(
                prefsFile.parentFile,
                "FlutterSharedPreferences.oversized-${System.currentTimeMillis()}.xml"
            )
            if (!prefsFile.renameTo(backup)) {
                prefsFile.delete()
            }
        } catch (_: Exception) {
            // Flutter can rebuild preferences; startup must not fail because of stale cache cleanup.
        }
    }

    override fun onResume() {
        super.onResume()
        AvaSelfPushForegroundService.appInForeground = true
    }

    override fun onPause() {
        AvaSelfPushForegroundService.appInForeground = false
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverAzoomActionFromIntent(intent)
        deliverWindowActionFromIntent(intent)
        handleDebugNotificationIntent(intent)
        handleDebugVoiceServiceIntent(intent)
    }

    override fun onDestroy() {
        if (isFinishing) {
            AzoomVoiceForegroundService.methodChannel = null
            windowMethodChannel = null
            windowCallbacksReady = false
            AvaSelfPushForegroundService.activeChatRoomId = ""
            AvaSelfPushForegroundService.appInForeground = false
            stopMobileAudio()
        }
        super.onDestroy()
    }

    private fun playMobileAudio(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_PATH", "Audio path is empty.", null)
            return
        }
        val sourceFile = File(path)
        if (!sourceFile.isFile) {
            result.error("AUDIO_NOT_FOUND", "Audio file was not found.", null)
            return
        }
        try {
            stopMobileAudio()
            val player = MediaPlayer()
            player.setDataSource(sourceFile.absolutePath)
            player.setOnCompletionListener {
                stopMobileAudio()
            }
            player.prepare()
            val durationMs = player.duration.coerceAtLeast(0)
            mobileAudioPlayer = player
            player.start()
            result.success(durationMs)
        } catch (exception: Exception) {
            stopMobileAudio()
            result.error(
                "AUDIO_PLAY_FAILED",
                exception.message ?: "Failed to play audio.",
                null
            )
        }
    }

    private fun stopMobileAudio() {
        val player = mobileAudioPlayer
        mobileAudioPlayer = null
        try {
            if (player?.isPlaying == true) {
                player.stop()
            }
        } catch (_: Exception) {
            // Ignore playback teardown failures.
        }
        try {
            player?.release()
        } catch (_: Exception) {
            // Ignore playback teardown failures.
        }
    }

    private fun setActiveChatRoom(arguments: Map<*, *>?) {
        val roomId = (arguments?.get("roomId") as? String)?.trim().orEmpty()
        AvaSelfPushForegroundService.activeChatRoomId = roomId
    }

    private fun startAzoomVoiceService(command: String, arguments: Map<*, *>?) {
        val intent = Intent(this, AzoomVoiceForegroundService::class.java).apply {
            action = "com.ava.ava_flutter.AZOOM_VOICE_${command.uppercase()}"
            putExtra("command", command)
            arguments?.forEach { (key, value) ->
                val name = key as? String ?: return@forEach
                when (value) {
                    is String -> putExtra(name, value)
                    is Boolean -> putExtra(name, value)
                    is Int -> putExtra(name, value)
                    is Long -> putExtra(name, value)
                    is Double -> putExtra(name, value)
                }
            }
        }
        if (command == "stop") {
            stopService(intent)
            return
        }
        ContextCompat.startForegroundService(this, intent)
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName")
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        }.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun areVoiceNotificationsEnabled(): Boolean {
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }
        ensureVoiceNotificationChannel()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel(AzoomVoiceForegroundService.CHANNEL_ID)
            ?: return true
        return channel.importance >= NotificationManager.IMPORTANCE_LOW
    }

    private fun openVoiceNotificationSettings() {
        ensureVoiceNotificationChannel()
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, AzoomVoiceForegroundService.CHANNEL_ID)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        }.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun ensureVoiceNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            AzoomVoiceForegroundService.CHANNEL_ID,
            AzoomVoiceForegroundService.CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = AzoomVoiceForegroundService.CHANNEL_DESCRIPTION
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun deliverAzoomActionFromIntent(intent: Intent?) {
        val action = intent?.getStringExtra("azoomVoiceAction") ?: return
        AzoomVoiceForegroundService.emitFlutterAction(action)
    }

    private fun showChatNotification(arguments: Map<*, *>?): Boolean {
        if (arguments == null) {
            return false
        }
        createChatNotificationChannel()
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            return false
        }

        val roomId = stringArg(arguments, "roomId")
        val roomTitle = stringArg(arguments, "roomTitle").ifBlank { "AVA" }
        val senderName = stringArg(arguments, "senderName")
        val senderNickname = stringArg(arguments, "senderNickname")
        val body = stringArg(arguments, "body")
        if (roomId.isBlank() || body.isBlank()) {
            return false
        }

        val senderTitle = senderNickname.ifBlank { senderName }.ifBlank { roomTitle }
        val notificationId = 5200 + abs(roomId.hashCode() % 90000)
        val appIconBitmap = appIconBitmap()
        val sender = Person.Builder()
            .setName(senderTitle)
            .setIcon(IconCompat.createWithBitmap(appIconBitmap))
            .setImportant(true)
            .build()

        val openIntent = mainLaunchIntent().apply {
            action = ACTION_CHAT_OPEN
            putExtra(EXTRA_ROOM_ID, roomId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val replyIntent = mainLaunchIntent().apply {
            action = ACTION_CHAT_REPLY
            putExtra(EXTRA_ROOM_ID, roomId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            openIntent,
            pendingFlags()
        )
        val replyPendingIntent = PendingIntent.getActivity(
            this,
            notificationId + 1,
            replyIntent,
            pendingMutableFlags()
        )
        val remoteInput = RemoteInput.Builder(CHAT_REPLY_KEY)
            .setLabel("\uB2F5\uC7A5")
            .build()
        val replyAction = NotificationCompat.Action.Builder(
            R.drawable.ava_notification_small,
            "\uB2F5\uC7A5",
            replyPendingIntent
        )
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .build()

        val style = NotificationCompat.MessagingStyle(sender)
            .setConversationTitle(roomTitle)
            .addMessage(body, System.currentTimeMillis(), sender)

        val notification = NotificationCompat.Builder(this, CHAT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ava_notification_small)
            .setLargeIcon(appIconBitmap)
            .setContentTitle(senderTitle)
            .setContentText(body)
            .setSubText(roomTitle)
            .setStyle(style)
            .setContentIntent(openPendingIntent)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setColor(Color.rgb(35, 135, 242))
            .setDefaults(Notification.DEFAULT_ALL)
            .addAction(replyAction)
            .addAction(R.drawable.ava_notification_small, "\uC5F4\uAE30", openPendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
        return true
    }

    private fun deliverWindowActionFromIntent(intent: Intent?) {
        val action = intent?.action ?: return
        if (action != ACTION_CHAT_OPEN && action != ACTION_CHAT_REPLY) {
            return
        }
        val roomId = intent.getStringExtra(EXTRA_ROOM_ID).orEmpty()
        if (roomId.isBlank()) {
            return
        }
        intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
            .takeIf { it > 0 }
            ?.let { id ->
                NotificationManagerCompat.from(this).cancel(id)
            }
        if (action == ACTION_CHAT_REPLY) {
            val reply = RemoteInput.getResultsFromIntent(intent)
                ?.getCharSequence(CHAT_REPLY_KEY)
                ?.toString()
                ?.trim()
                .orEmpty()
            if (reply.isNotBlank()) {
                queueOrEmitWindowAction(
                    "notificationReply",
                    mapOf("roomId" to roomId, "content" to reply)
                )
            }
            return
        }
        queueOrEmitWindowAction(
            "floatingAction",
            mapOf("action" to "openRoom", "roomId" to roomId)
        )
    }

    private fun handleDebugNotificationIntent(intent: Intent?) {
        if (!isDebuggable() || intent?.getBooleanExtra("debugShowChatNotification", false) != true) {
            return
        }
        showChatNotification(
            mapOf(
                "roomId" to "debug-azoom-notification",
                "roomTitle" to "\uC804\uC9C1\uC6D0 \uD68C\uC758",
                "senderName" to "AZOOM",
                "senderNickname" to "AZOOM",
                "body" to "\uC804\uC9C1\uC6D0 \uD68C\uC758 \uC74C\uC131\uCC44\uB110 \uD68C\uC758\uAC00 \uC2DC\uC791\uB418\uC5C8\uC2B5\uB2C8\uB2E4."
            )
        )
    }

    private fun handleDebugVoiceServiceIntent(intent: Intent?) {
        if (!isDebuggable() || intent?.getBooleanExtra("debugStartAzoomVoiceService", false) != true) {
            return
        }
        startAzoomVoiceService(
            "start",
            mapOf(
                "apiBaseUrl" to "",
                "accessToken" to "",
                "channelId" to "debug-azoom-voice",
                "channelName" to "\uC804\uC9C1\uC6D0 \uD68C\uC758",
                "participantName" to "AZOOM",
                "avatarColor" to "#2387F2",
                "avatarImageUrl" to "",
                "muted" to false,
                "deafened" to false,
                "cameraEnabled" to false,
                "screenSharing" to false
            )
        )
    }

    private fun isDebuggable(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun queueOrEmitWindowAction(method: String, arguments: Map<String, Any?>) {
        if (windowCallbacksReady) {
            windowMethodChannel?.invokeMethod(method, arguments)
            return
        }
        synchronized(pendingWindowActions) {
            pendingWindowActions.add(method to arguments)
        }
    }

    private fun drainPendingWindowActions() {
        val actions = synchronized(pendingWindowActions) {
            val copy = pendingWindowActions.toList()
            pendingWindowActions.clear()
            copy
        }
        for ((method, arguments) in actions) {
            windowMethodChannel?.invokeMethod(method, arguments)
        }
    }

    private fun startSelfHostedPush(arguments: Map<*, *>?): Boolean {
        if (arguments == null) {
            return false
        }
        val intent = Intent(this, AvaSelfPushForegroundService::class.java).apply {
            action = AvaSelfPushForegroundService.ACTION_START
            putExtra(AvaSelfPushForegroundService.EXTRA_API_BASE_URL, arguments["apiBaseUrl"] as? String ?: "")
            putExtra(AvaSelfPushForegroundService.EXTRA_WEBSOCKET_URL, arguments["websocketUrl"] as? String ?: "")
            putExtra(AvaSelfPushForegroundService.EXTRA_ACCESS_TOKEN, arguments["accessToken"] as? String ?: "")
            putExtra(AvaSelfPushForegroundService.EXTRA_REFRESH_TOKEN, arguments["refreshToken"] as? String ?: "")
            putExtra(AvaSelfPushForegroundService.EXTRA_USER_ID, arguments["userId"] as? String ?: "")
            putExtra(AvaSelfPushForegroundService.EXTRA_DEVICE_ID, arguments["deviceId"] as? String ?: "")
        }
        ContextCompat.startForegroundService(this, intent)
        return true
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

    private fun createDownloadNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            DOWNLOAD_CHANNEL_ID,
            "AVA downloads",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "AVA attachment download notifications"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            enableVibration(true)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun showAttachmentDownloadNotification(
        fileName: String,
        mimeType: String,
        uri: Uri
    ) {
        createDownloadNotificationChannel()
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            return
        }
        val notificationId = 7600 + abs("$fileName:${uri}".hashCode() % 90000)
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            clipData = ClipData.newUri(contentResolver, fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            viewIntent,
            pendingFlags()
        )
        val notification = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(R.drawable.ava_notification_small)
            .setLargeIcon(appIconBitmap())
            .setContentTitle("\uB2E4\uC6B4\uB85C\uB4DC \uC644\uB8CC")
            .setContentText(fileName)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setColor(Color.rgb(35, 135, 242))
            .setDefaults(Notification.DEFAULT_ALL)
            .build()
        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun appIconBitmap(): Bitmap {
        return BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
            ?: createAvatarBitmap("AVA", "#2387F2")
    }

    private fun createAvatarBitmap(name: String, colorText: String): Bitmap {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = parseColor(colorText)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        val initial = name.trim().take(1).ifBlank { "A" }
        paint.color = Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 42f
        val metrics = paint.fontMetrics
        val y = size / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(initial, size / 2f, y, paint)
        return bitmap
    }

    private fun parseColor(value: String): Int {
        return try {
            Color.parseColor(value.ifBlank { "#2387F2" })
        } catch (_: Exception) {
            Color.rgb(35, 135, 242)
        }
    }

    private fun mainLaunchIntent(): Intent {
        return (packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
    }

    private fun stringArg(arguments: Map<*, *>, key: String): String {
        return (arguments[key] as? String).orEmpty()
    }

    private fun pendingFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }

    private fun pendingMutableFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
    }

    private fun updateDownloadDirectory(result: MethodChannel.Result) {
        val directory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: cacheDir
        if (!directory.exists()) {
            directory.mkdirs()
        }
        result.success(directory.absolutePath)
    }

    private fun saveApkToDownloads(path: String?, fileName: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_PATH", "APK path is empty.", null)
            return
        }

        val apkFile = File(path)
        if (!apkFile.isFile) {
            result.error("PACKAGE_NOT_FOUND", "APK file was not found.", null)
            return
        }

        val safeFileName = sanitizeApkFileName(fileName ?: apkFile.name)
        try {
            val visibleLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveApkWithMediaStore(apkFile, safeFileName)
            } else {
                saveApkInPublicDownloads(apkFile, safeFileName)
            }
            result.success(visibleLocation)
        } catch (exception: Exception) {
            result.error(
                "DOWNLOAD_SAVE_FAILED",
                exception.message ?: "Failed to save APK to Downloads.",
                null
            )
        }
    }

    private fun sanitizeApkFileName(value: String): String {
        val sanitized = value.replace(Regex("[\\\\/:*?\"<>|]+"), "_").trim()
        val withName = sanitized.ifBlank { "ava-update.apk" }
        return if (withName.endsWith(".apk", ignoreCase = true)) withName else "$withName.apk"
    }

    private fun saveApkWithMediaStore(apkFile: File, fileName: String): String {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, "application/vnd.android.package-archive")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/AVA")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create Downloads entry.")
        try {
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(apkFile).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Could not open Downloads output stream.")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Downloads/AVA/$fileName"
        } catch (exception: Exception) {
            resolver.delete(uri, null, null)
            throw exception
        }
    }

    private fun saveApkInPublicDownloads(apkFile: File, fileName: String): String {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "AVA"
        )
        if (!directory.exists()) {
            directory.mkdirs()
        }
        val target = File(directory, fileName)
        FileInputStream(apkFile).use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
            }
        }
        return target.absolutePath
    }

    private fun saveAttachmentToMediaStore(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        notify: Boolean,
        result: MethodChannel.Result
    ) {
        if (sourcePath.isNullOrBlank()) {
            result.error("INVALID_PATH", "Attachment path is empty.", null)
            return
        }

        val sourceFile = File(sourcePath)
        if (!sourceFile.isFile) {
            result.error("ATTACHMENT_NOT_FOUND", "Attachment file was not found.", null)
            return
        }

        val safeFileName = sanitizeAttachmentFileName(fileName ?: sourceFile.name)
        val normalizedMimeType = normalizedMimeType(safeFileName, mimeType)
        try {
            val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveAttachmentWithMediaStore(sourceFile, safeFileName, normalizedMimeType)
            } else {
                saveAttachmentInPublicDirectory(sourceFile, safeFileName, normalizedMimeType)
            }
            if (notify) {
                showAttachmentDownloadNotification(
                    safeFileName,
                    normalizedMimeType,
                    saved.uri
                )
            }
            result.success(saved.visibleLocation)
        } catch (exception: Exception) {
            result.error(
                "ATTACHMENT_SAVE_FAILED",
                exception.message ?: "Failed to save attachment.",
                null
            )
        }
    }

    private data class SavedAttachment(
        val visibleLocation: String,
        val uri: Uri
    )

    private fun sanitizeAttachmentFileName(value: String): String {
        val sanitized = value.replace(Regex("[\\\\/:*?\"<>|]+"), "_").trim()
        return sanitized.ifBlank { "ava-attachment" }
    }

    private fun normalizedMimeType(fileName: String, value: String?): String {
        val provided = value?.trim().orEmpty()
        if (provided.contains("/") && provided != "application/octet-stream") {
            return provided
        }
        val extension = fileName.substringAfterLast('.', "").lowercase()
        if (extension.isNotBlank()) {
            val guessed = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            if (!guessed.isNullOrBlank()) {
                return guessed
            }
        }
        return "application/octet-stream"
    }

    private fun mediaDirectoryForMime(mimeType: String): String {
        return when {
            mimeType.startsWith("image/") -> Environment.DIRECTORY_PICTURES
            mimeType.startsWith("video/") -> Environment.DIRECTORY_MOVIES
            else -> Environment.DIRECTORY_DOWNLOADS
        }
    }

    private fun mediaCollectionForMime(mimeType: String): Uri {
        return when {
            mimeType.startsWith("image/") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            mimeType.startsWith("video/") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
            else -> MediaStore.Files.getContentUri("external")
        }
    }

    private fun saveAttachmentWithMediaStore(
        sourceFile: File,
        fileName: String,
        mimeType: String
    ): SavedAttachment {
        val resolver = applicationContext.contentResolver
        val publicDirectory = mediaDirectoryForMime(mimeType)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$publicDirectory/AVA")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(mediaCollectionForMime(mimeType), values)
            ?: throw IllegalStateException("Could not create MediaStore entry.")
        try {
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Could not open MediaStore output stream.")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            val visibleFile = File(
                Environment.getExternalStoragePublicDirectory(publicDirectory),
                "AVA/$fileName"
            )
            return SavedAttachment(visibleFile.absolutePath, uri)
        } catch (exception: Exception) {
            resolver.delete(uri, null, null)
            throw exception
        }
    }

    private fun saveAttachmentInPublicDirectory(
        sourceFile: File,
        fileName: String,
        mimeType: String
    ): SavedAttachment {
        val publicDirectory = mediaDirectoryForMime(mimeType)
        val directory = File(
            Environment.getExternalStoragePublicDirectory(publicDirectory),
            "AVA"
        )
        if (!directory.exists()) {
            directory.mkdirs()
        }
        val target = uniqueFile(directory, fileName)
        FileInputStream(sourceFile).use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
            }
        }
        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(target.absolutePath),
            arrayOf(mimeType),
            null
        )
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            target
        )
        return SavedAttachment(target.absolutePath, uri)
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        val dotIndex = fileName.lastIndexOf('.')
        val stem = if (dotIndex <= 0) fileName else fileName.substring(0, dotIndex)
        val extension = if (dotIndex <= 0) "" else fileName.substring(dotIndex)
        var candidate = File(directory, fileName)
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, "$stem ($index)$extension")
            index += 1
        }
        return candidate
    }
}
