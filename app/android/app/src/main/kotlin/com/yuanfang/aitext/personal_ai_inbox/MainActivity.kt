package com.yuanfang.aitext.personal_ai_inbox

import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "com.yuanfang.aitext.personal_ai_inbox/share"
    private var pendingSharedPayload: Map<String, Any?>? = null
    private var channel: MethodChannel? = null
    private var homeWidgetChannel: MethodChannel? = null
    private var homeWidgetChannelHandler: HomeWidgetChannelHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        captureSharedPayload(intent)
        super.onCreate(savedInstanceState)
    }

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine {
        return AitextApplication.from(context).getOrCreateFlutterEngine()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialPayload") {
                result.success(pendingSharedPayload)
                pendingSharedPayload = null
            } else if (call.method == "getAvailableSpaceBytes") {
                val path = call.argument<String>("path") ?: filesDir.absolutePath
                try {
                    result.success(StatFs(path).availableBytes)
                } catch (error: Exception) {
                    result.error("disk_space_unavailable", error.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
        HomeWidgetChannelHandler(this).also { handler ->
            homeWidgetChannelHandler = handler
            homeWidgetChannel =
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HomeWidgetChannelHandler.CHANNEL_NAME)
                    .also { widgetChannel ->
                        widgetChannel.setMethodCallHandler(handler::handle)
                        window.decorView.post {
                            handler.announceIfPending(widgetChannel)
                        }
                    }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        homeWidgetChannel?.setMethodCallHandler(null)
        homeWidgetChannel = null
        homeWidgetChannelHandler?.dispose()
        homeWidgetChannelHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        AitextApplication.from(this).backgroundController.attachActivity(this)
        homeWidgetChannel?.let { widgetChannel ->
            homeWidgetChannelHandler?.announceIfPending(widgetChannel)
        }
    }

    override fun onDestroy() {
        AitextApplication.from(this).backgroundController.detachActivity(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted =
            grantResults.isNotEmpty() &&
                grantResults.first() == PackageManager.PERMISSION_GRANTED
        AitextApplication.from(this)
            .backgroundController
            .onNotificationPermissionResult(requestCode, granted)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureSharedPayload(intent)
        pendingSharedPayload?.let { payload ->
            channel?.invokeMethod("sharedPayload", payload)
            pendingSharedPayload = null
        }
        homeWidgetChannel?.let { widgetChannel ->
            homeWidgetChannelHandler?.announceIfPending(widgetChannel)
        }
    }

    private fun captureSharedPayload(intent: Intent?) {
        if (intent == null) {
            return
        }
        val text = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            else -> null
        }
        val imageUris = when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri == null) emptyList() else listOf(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            }
            else -> emptyList()
        }
        val images = imageUris
            .take(4)
            .mapNotNull { copySharedImage(it) }
        if (text.isNullOrBlank() && images.isEmpty()) {
            return
        }
        pendingSharedPayload = buildMap {
            put("text", text.orEmpty())
            put("images", images)
        }
    }

    private fun copySharedImage(uri: Uri): Map<String, String>? {
        return try {
            val resolver = contentResolver
            val mimeType = resolver.getType(uri) ?: "image/jpeg"
            if (!mimeType.startsWith("image/")) {
                return null
            }
            val fileName = queryFileName(uri) ?: "shared-image"
            val extension = when (mimeType.lowercase()) {
                "image/png" -> ".png"
                "image/webp" -> ".webp"
                "image/gif" -> ".gif"
                else -> ".jpg"
            }
            val directory = File(cacheDir, "shared_images")
            if (!directory.exists()) {
                directory.mkdirs()
            }
            val target = File(directory, "${UUID.randomUUID()}$extension")
            resolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            buildMap {
                put("path", target.absolutePath)
                put("name", fileName)
                put("mime_type", mimeType)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun queryFileName(uri: Uri): String? {
        return contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) {
                return@use null
            }
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index < 0) null else cursor.getString(index)
        }
    }
}
