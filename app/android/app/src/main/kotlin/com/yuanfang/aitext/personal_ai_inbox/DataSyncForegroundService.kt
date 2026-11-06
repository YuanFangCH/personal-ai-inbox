package com.yuanfang.aitext.personal_ai_inbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.annotation.RequiresApi

class DataSyncForegroundService : Service() {
    companion object {
        const val ACTION_START = "com.yuanfang.aitext.personal_ai_inbox.agent.START"
        const val ACTION_UPDATE = "com.yuanfang.aitext.personal_ai_inbox.agent.UPDATE"
        const val ACTION_PAUSE = "com.yuanfang.aitext.personal_ai_inbox.agent.PAUSE"
        const val ACTION_COMPLETE = "com.yuanfang.aitext.personal_ai_inbox.agent.COMPLETE"
        const val ACTION_CANCEL = "com.yuanfang.aitext.personal_ai_inbox.agent.CANCEL"
        const val ACTION_DEBUG_TIMEOUT =
            "com.yuanfang.aitext.personal_ai_inbox.agent.DEBUG_TIMEOUT"
        const val ACTION_DEBUG_STOP_ACK =
            "com.yuanfang.aitext.personal_ai_inbox.agent.DEBUG_STOP_ACK"

        private const val PREFS = "agent_background_state"
        private const val ACTIVE_TASK_ID = "active_task_id"
        private const val ACTIVE_STATE = "active_state"
        private const val ACTIVE_FAILURE_CODE = "active_failure_code"
        private const val TERMINAL_PREFIX = "terminal_"
        const val NOTIFICATION_CHANNEL_ID = "agent_data_sync"
        private const val NOTIFICATION_ID = 4307
        private const val WAKELOCK_TIMEOUT_MS = 2 * 60 * 60 * 1000L
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var activeTaskId: String? = null
    private var activeTitle = "懒狗秘书正在处理任务"
    private var activeText = "Agent 正在后台运行。"
    private var progress: Double? = null
    private var terminatingByCommand = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY
        return try {
            when (action) {
                ACTION_START, ACTION_UPDATE -> startOrUpdate(intent)
                ACTION_PAUSE -> {
                    finishFromUser("pause")
                    START_NOT_STICKY
                }
                ACTION_COMPLETE -> {
                    finishQuietly("completed", "后台 Agent 已完成。")
                    START_NOT_STICKY
                }
                ACTION_CANCEL -> {
                    finishFromUser("cancel")
                    START_NOT_STICKY
                }
                ACTION_DEBUG_TIMEOUT -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                        throw UnsupportedOperationException(
                            "dataSync timeout callback is available on Android 15 and later.",
                        )
                    }
                    onTimeout(startId, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                    START_NOT_STICKY
                }
                else -> START_NOT_STICKY
            }
        } catch (error: Exception) {
            terminatingByCommand = true
            val serviceStartRestricted = isServiceStartRestricted(error)
            val state = if (serviceStartRestricted) {
                "service_start_restricted"
            } else {
                "failed"
            }
            val failureCode = if (serviceStartRestricted) {
                "foreground_service_start_not_allowed"
            } else {
                "foreground_service_failed"
            }
            val message = if (serviceStartRestricted) {
                "系统限制前台服务启动；任务已保存为暂停。请回到前台后继续。"
            } else {
                "前台 dataSync 服务启动失败。"
            }
            AgentBackgroundController.invokeDart(
                "serviceStopped",
                mapOf(
                    "state" to state,
                    "taskId" to activeTaskId,
                    "message" to message,
                    "code" to failureCode,
                    "detail" to error.message,
                ),
            )
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (_: Exception) {
                // A rejected start may not have entered foreground yet.
            }
            clearActiveTask(state, failureCode)
            stopSelf()
            START_NOT_STICKY
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    override fun onTimeout(startId: Int, fgsType: Int) {
        terminatingByCommand = true
        val taskId = activeTaskId ?: currentActiveTaskId()
        Log.i(
            "AgentBackgroundService",
            "dataSync timeout startId=$startId fgsType=$fgsType " +
                "taskIdPresent=${!taskId.isNullOrEmpty()}",
        )
        if (!taskId.isNullOrEmpty()) {
            getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putString(ACTIVE_STATE, "paused")
                .apply()
            AgentBackgroundController.invokeDart(
                "serviceStopped",
                mapOf(
                    "state" to "paused",
                    "taskId" to taskId,
                    "message" to "dataSync 前台服务达到系统时限，任务已暂停。",
                    "code" to "data_sync_timeout",
                ),
            )
        }
        clearActiveTask("paused")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    override fun onDestroy() {
        val taskId = activeTaskId
        val persistedTaskId = currentActiveTaskId()
        val shouldReportInterruption = !terminatingByCommand && taskId != null
        Log.i(
            "AgentBackgroundService",
            "onDestroy taskIdPresent=${taskId != null} " +
                "persistedTaskIdPresent=${persistedTaskId != null} " +
                "taskIdsMatch=${taskId != null && taskId == persistedTaskId} " +
                "terminatingByCommand=$terminatingByCommand " +
                "reportInterruption=$shouldReportInterruption",
        )
        if (shouldReportInterruption) {
            val interruptedTaskId = taskId
            getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putString(ACTIVE_STATE, "paused")
                .apply()
            val dispatchAccepted = AgentBackgroundController.invokeDart(
                "serviceStopped",
                mapOf(
                    "state" to "paused",
                    "taskId" to interruptedTaskId,
                    "message" to "前台 dataSync 服务被系统中止，任务已保存为暂停。",
                    "code" to "service_interrupted",
                ),
            ) { reply ->
                if (
                    (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                ) {
                    sendDebugStopAcknowledgement(interruptedTaskId, reply)
                }
            }
            Log.i(
                "AgentBackgroundService",
                "onDestroy interruptionDispatchAccepted=$dispatchAccepted",
            )
        } else {
            Log.i(
                "AgentBackgroundService",
                "onDestroy interruptionSkipped taskIdPresent=${taskId != null} " +
                    "terminatingByCommand=$terminatingByCommand",
            )
        }
        releaseWakeLock()
        super.onDestroy()
    }

    private fun sendDebugStopAcknowledgement(taskId: String, reply: Any?) {
        val ack = reply as? Map<*, *>
        sendBroadcast(
            Intent(ACTION_DEBUG_STOP_ACK)
                .setPackage(packageName)
                .putExtra("taskId", taskId)
                .putExtra("dartAckReceived", ack != null)
                .putExtra("eventTaskId", ack?.get("eventTaskId")?.toString())
                .putExtra("currentTaskId", ack?.get("currentTaskId")?.toString())
                .putExtra("taskIdMatched", ack?.get("taskIdMatched") as? Boolean ?: false),
        )
    }

    private fun startOrUpdate(intent: Intent): Int {
        val taskId = intent.getStringExtra("taskId")?.trim().orEmpty()
        if (taskId.isEmpty()) {
            return START_NOT_STICKY
        }
        val preferences = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (preferences.getBoolean("$TERMINAL_PREFIX$taskId", false)) {
            stopSelf()
            return START_NOT_STICKY
        }
        activeTaskId = taskId
        activeTitle = intent.getStringExtra("title") ?: activeTitle
        activeText = intent.getStringExtra("text") ?: activeText
        progress = if (intent.hasExtra("progress")) {
            intent.getDoubleExtra("progress", -1.0).takeIf { it >= 0.0 }
        } else {
            progress
        }
        preferences.edit()
            .putString(ACTIVE_TASK_ID, taskId)
            .putString(ACTIVE_STATE, "running")
            .apply()
        startForegroundCompat(buildNotification())
        acquireWakeLock()
        return START_NOT_STICKY
    }

    private fun finishFromUser(action: String) {
        terminatingByCommand = true
        val taskId = activeTaskId ?: currentActiveTaskId().orEmpty()
        if (taskId.isNotEmpty()) {
            if (action == "cancel") {
                getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit()
                    .putBoolean("$TERMINAL_PREFIX$taskId", true)
                    .apply()
            }
            AgentBackgroundController.invokeDart(
                if (action == "cancel") "cancelRequested" else "pauseRequested",
                mapOf(
                    "taskId" to taskId,
                    "reason" to
                        if (action == "cancel") {
                            "用户从通知取消了后台任务。"
                        } else {
                            "用户从通知暂停了后台任务。"
                        },
                ),
            )
            clearActiveTask(if (action == "cancel") "cancelled" else "paused")
        }
        stopSelf()
    }

    private fun finishQuietly(state: String, message: String) {
        terminatingByCommand = true
        val taskId = activeTaskId ?: currentActiveTaskId()
        if (!taskId.isNullOrEmpty()) {
            AgentBackgroundController.invokeDart(
                "serviceStopped",
                mapOf(
                    "state" to state,
                    "taskId" to taskId,
                    "message" to message,
                ),
            )
            clearActiveTask(state)
        }
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val launchIntent =
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("openAgentTaskId", activeTaskId)
            }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val pauseIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, DataSyncForegroundService::class.java).apply {
                action = ACTION_PAUSE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cancelIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, DataSyncForegroundService::class.java).apply {
                action = ACTION_CANCEL
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder =
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            })
                .setContentTitle(activeTitle)
                .setContentText(activeText)
                .setSmallIcon(
                    if (applicationInfo.icon != 0) {
                        applicationInfo.icon
                    } else {
                        R.mipmap.ic_launcher
                    },
                )
                .setContentIntent(contentIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setShowWhen(false)
                .addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(this, android.R.drawable.ic_media_pause),
                        "暂停",
                        pauseIntent,
                    ).build(),
                )
                .addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(
                            this,
                            android.R.drawable.ic_menu_close_clear_cancel,
                        ),
                        "取消",
                        cancelIntent,
                    ).build(),
                )
        val currentProgress = progress
        if (currentProgress != null) {
            builder.setProgress(100, (currentProgress.coerceIn(0.0, 1.0) * 100).toInt(), false)
        }
        return builder.build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "后台秘书任务",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "显示 Agent 进度，并提供暂停和取消操作。"
                setShowBadge(false)
            }
        manager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock =
            powerManager
                .newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "懒狗秘书:AgentTask",
                )
                .apply {
                    setReferenceCounted(false)
                    acquire(WAKELOCK_TIMEOUT_MS)
                }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    private fun currentActiveTaskId(): String? {
        return getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(ACTIVE_TASK_ID, null)
    }

    private fun clearActiveTask(state: String, failureCode: String? = null) {
        val taskId = activeTaskId ?: currentActiveTaskId()
        val editor = getSharedPreferences(PREFS, MODE_PRIVATE).edit()
        if (!taskId.isNullOrEmpty()) {
            editor.putString(ACTIVE_STATE, state)
        }
        if (failureCode == null) {
            editor.remove(ACTIVE_FAILURE_CODE)
        } else {
            editor.putString(ACTIVE_FAILURE_CODE, failureCode)
        }
        editor.remove(ACTIVE_TASK_ID).apply()
        activeTaskId = null
        releaseWakeLock()
    }

    private fun isServiceStartRestricted(error: Exception): Boolean =
        error is SecurityException ||
            error.javaClass.name ==
            "android.app.ForegroundServiceStartNotAllowedException"
}
