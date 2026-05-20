package com.ava.ava_flutter

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val androidUpdateChannel = "ava/android_update"

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
}
