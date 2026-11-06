package com.yuanfang.aitext.personal_ai_inbox

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class AgentBackgroundController(
    private val context: Context,
    private val engine: FlutterEngine,
) {
    companion object {
        const val CHANNEL_NAME =
            "com.yuanfang.aitext.personal_ai_inbox/background_agent"
        private const val REQUEST_NOTIFICATIONS = 4307
        private const val PREFS = "agent_background_state"
        private const val ACTIVE_TASK_ID = "active_task_id"
        private const val ACTIVE_STATE = "active_state"
        private const val ACTIVE_FAILURE_CODE = "active_failure_code"
        private const val TERMINAL_PREFIX = "terminal_"
        private const val TAG = "AgentBackgroundCallback"

        fun invokeDart(
            method: String,
            arguments: Map<String, Any?>,
            onReply: ((Any?) -> Unit)? = null,
        ): Boolean {
            val cachedEngine =
                FlutterEngineCache.getInstance()
                    .get(AitextApplication.ENGINE_ID)
            if (cachedEngine == null) {
                Log.w(TAG, "dispatch method=$method engineCached=false")
                return false
            }
            Log.i(TAG, "dispatch method=$method engineCached=true")
            MethodChannel(cachedEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                .invokeMethod(method, arguments, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val acknowledgement = result as? Map<*, *>
                        Log.i(
                            TAG,
                            "reply method=$method ackReceived=${acknowledgement != null} " +
                                "eventTaskIdPresent=${acknowledgement?.get("eventTaskId") != null} " +
                                "currentTaskIdPresent=${acknowledgement?.get("currentTaskId") != null} " +
                                "taskIdMatched=${acknowledgement?.get("taskIdMatched") == true}",
                        )
                        onReply?.invoke(result)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.e(TAG, "reply method=$method callback=error code=$code")
                        onReply?.invoke(null)
                    }

                    override fun notImplemented() {
                        Log.e(TAG, "reply method=$method notImplemented")
                        onReply?.invoke(null)
                    }
                })
            return true
        }
    }

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private var activityReference = WeakReference<Activity>(null)
    private var pendingNotificationResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    fun attachActivity(activity: Activity) {
        activityReference = WeakReference(activity)
    }

    fun detachActivity(activity: Activity) {
        if (activityReference.get() === activity) {
            activityReference.clear()
            pendingNotificationResult?.success(
                mapOf(
                    "state" to "activity_unavailable",
                    "message" to "Activity 已关闭，通知权限结果未取得。",
                    "notificationPermissionGranted" to false,
                    "failureCode" to "activity_unavailable",
                ),
            )
            pendingNotificationResult = null
        }
    }

    internal fun recreateAttachedActivity(): Boolean {
        val activity = activityReference.get() ?: return false
        if (activity.isFinishing || activity.isDestroyed) return false
        activity.runOnUiThread {
            if (!activity.isFinishing && !activity.isDestroyed) {
                activity.recreate()
            }
        }
        return true
    }

    fun onNotificationPermissionResult(requestCode: Int, granted: Boolean) {
        if (requestCode != REQUEST_NOTIFICATIONS) {
            return
        }
        val result = pendingNotificationResult ?: return
        pendingNotificationResult = null
        val effectiveGrant = granted && notificationPermissionGranted()
        result.success(
            mapOf(
                "state" to
                    if (effectiveGrant) {
                        "idle"
                    } else {
                        "notification_permission_denied"
                    },
                "message" to
                    if (effectiveGrant) {
                        "通知权限已允许。"
                    } else {
                        "通知权限被拒绝，前台 Agent 无法显示进度或暂停/取消操作。"
                    },
                "notificationPermissionGranted" to effectiveGrant,
                "failureCode" to
                    if (effectiveGrant) {
                        null
                    } else {
                        "notification_permission_denied"
                    },
            ),
        )
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        activityReference.clear()
        pendingNotificationResult?.error(
            "activity_unavailable",
            "Activity 已关闭，无法请求通知权限。",
            null,
        )
        pendingNotificationResult = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> startTask(call, result)
            "update" -> dispatchServiceAction(
                DataSyncForegroundService.ACTION_UPDATE,
                call,
                result,
            )
            "pause" -> dispatchServiceAction(
                DataSyncForegroundService.ACTION_PAUSE,
                call,
                result,
            )
            "complete" -> dispatchServiceAction(
                DataSyncForegroundService.ACTION_COMPLETE,
                call,
                result,
            )
            "cancel" -> cancelTask(call, result)
            "getStatus" -> result.success(currentStatus())
            "requestNotificationPermission" -> requestNotificationPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun startTask(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")?.trim().orEmpty()
        if (taskId.isEmpty()) {
            result.error("task_missing", "后台任务缺少稳定 ID。", null)
            return
        }
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (preferences.getBoolean("$TERMINAL_PREFIX$taskId", false)) {
            result.success(
                mapOf(
                    "state" to "cancelled",
                    "taskId" to taskId,
                    "message" to "该任务已由用户主动结束，不会自动恢复。",
                    "failureCode" to "terminal_task",
                ),
            )
            return
        }
        val currentTaskId = preferences.getString(ACTIVE_TASK_ID, null)
        val currentState = preferences.getString(ACTIVE_STATE, null)
        if (!currentTaskId.isNullOrEmpty() &&
            currentTaskId != taskId &&
            currentState == "running"
        ) {
            result.success(
                mapOf(
                    "state" to "busy",
                    "taskId" to currentTaskId,
                    "message" to "已有另一个 Agent 任务正在使用唯一写入运行时。",
                    "failureCode" to "writer_busy",
                ),
            )
            return
        }
        if (!notificationPermissionGranted()) {
            result.success(
                mapOf(
                    "state" to "notification_permission_denied",
                    "taskId" to taskId,
                    "message" to "通知权限被拒绝，前台 Agent 无法可靠运行。",
                    "notificationPermissionGranted" to false,
                    "failureCode" to "notification_permission_denied",
                ),
            )
            return
        }
        val intent = serviceIntent(DataSyncForegroundService.ACTION_START, call)
        try {
            startForegroundService(intent)
            preferences.edit()
                .putString(ACTIVE_TASK_ID, taskId)
                .putString(ACTIVE_STATE, "running")
                .remove(ACTIVE_FAILURE_CODE)
                .apply()
            result.success(
                mapOf(
                    "state" to "running",
                    "taskId" to taskId,
                    "message" to "前台 Agent 已启动。",
                    "notificationPermissionGranted" to true,
                ),
            )
        } catch (error: SecurityException) {
            result.success(serviceRestricted(taskId, error.message))
        } catch (error: Exception) {
            if (error.javaClass.name ==
                "android.app.ForegroundServiceStartNotAllowedException"
            ) {
                result.success(serviceRestricted(taskId, error.message))
            } else {
                result.error("foreground_service_failed", error.message, null)
            }
        }
    }

    private fun dispatchServiceAction(
        action: String,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val taskId = call.argument<String>("taskId")?.trim().orEmpty()
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (taskId.isEmpty() ||
            preferences.getString(ACTIVE_TASK_ID, null) != taskId
        ) {
            result.error("task_mismatch", "后台任务 ID 与当前服务不一致。", null)
            return
        }
        try {
            context.startService(
                serviceIntent(action, call),
            )
            val state = when (action) {
                DataSyncForegroundService.ACTION_PAUSE -> "paused"
                DataSyncForegroundService.ACTION_COMPLETE -> "completed"
                else -> "running"
            }
            preferences.edit()
                .putString(ACTIVE_STATE, state)
                .remove(ACTIVE_FAILURE_CODE)
                .apply()
            result.success(
                mapOf<String, Any?>(
                    "state" to state,
                    "taskId" to taskId,
                    "message" to (
                        call.argument<String>("message")
                            ?: call.argument<String>("reason")
                            ?: "后台任务状态已更新。"
                    ),
                ),
            )
        } catch (error: Exception) {
            result.error("foreground_service_failed", error.message, null)
        }
    }

    private fun cancelTask(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")?.trim().orEmpty()
        if (taskId.isEmpty()) {
            result.error("task_missing", "后台任务缺少稳定 ID。", null)
            return
        }
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        preferences.edit()
            .putBoolean("$TERMINAL_PREFIX$taskId", true)
            .putString(ACTIVE_TASK_ID, taskId)
            .putString(ACTIVE_STATE, "cancelled")
            .apply()
        try {
            context.startService(
                serviceIntent(DataSyncForegroundService.ACTION_CANCEL, call),
            )
        } catch (_: Exception) {
            preferences.edit()
                .remove(ACTIVE_TASK_ID)
                .remove(ACTIVE_STATE)
                .apply()
        }
        result.success(
            mapOf(
                "state" to "cancelled",
                "taskId" to taskId,
                "message" to (call.argument<String>("reason")
                    ?: "用户取消了后台任务。"),
                "failureCode" to "user_cancelled",
            ),
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            postNotificationPermissionGranted()
        ) {
            val enabled = notificationPermissionGranted()
            result.success(
                mapOf(
                    "state" to
                        if (enabled) {
                            "idle"
                        } else {
                            "notification_permission_denied"
                        },
                    "message" to
                        if (enabled) {
                            "通知权限已允许。"
                        } else {
                            "系统通知已关闭，前台 Agent 无法可靠运行。"
                        },
                    "notificationPermissionGranted" to enabled,
                    "failureCode" to
                        if (enabled) null else "notification_permission_denied",
                ),
            )
            return
        }
        val activity = activityReference.get()
        if (activity == null) {
            result.success(
                mapOf(
                    "state" to "activity_unavailable",
                    "message" to "请回到应用界面后允许通知权限。",
                    "notificationPermissionGranted" to false,
                    "failureCode" to "activity_unavailable",
                ),
            )
            return
        }
        if (pendingNotificationResult != null) {
            result.success(
                mapOf(
                    "state" to "busy",
                    "message" to "通知权限请求正在进行。",
                    "failureCode" to "permission_request_busy",
                ),
            )
            return
        }
        pendingNotificationResult = result
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATIONS,
            )
        } catch (error: Exception) {
            pendingNotificationResult = null
            result.success(
                mapOf(
                    "state" to "activity_unavailable",
                    "message" to (error.message ?: "当前无法请求通知权限。"),
                    "notificationPermissionGranted" to false,
                    "failureCode" to "activity_unavailable",
                ),
            )
        }
    }

    private fun notificationPermissionGranted(): Boolean {
        if (!postNotificationPermissionGranted()) {
            return false
        }
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        if (!notificationManager.areNotificationsEnabled()) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                notificationManager.getNotificationChannel(
                    DataSyncForegroundService.NOTIFICATION_CHANNEL_ID,
                )
            if (channel != null &&
                channel.importance == NotificationManager.IMPORTANCE_NONE
            ) {
                return false
            }
        }
        return true
    }

    private fun postNotificationPermissionGranted(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun currentStatus(): Map<String, Any?> {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val state = preferences.getString(ACTIVE_STATE, "idle") ?: "idle"
        val taskId = preferences.getString(ACTIVE_TASK_ID, null)
        return mapOf(
            "state" to state,
            "taskId" to taskId,
            "message" to when (state) {
                "running" -> "前台 Agent 正在运行。"
                "paused" -> "前台 Agent 已暂停。"
                "completed" -> "前台 Agent 已完成。"
                "cancelled" -> "前台 Agent 已取消。"
                "service_start_restricted" ->
                    "系统限制前台服务启动；任务已保存为暂停。请回到前台后继续。"
                else -> null
            },
            "failureCode" to preferences.getString(ACTIVE_FAILURE_CODE, null),
            "notificationPermissionGranted" to notificationPermissionGranted(),
            "activityAttached" to (activityReference.get() != null),
        )
    }

    private fun serviceRestricted(
        taskId: String,
        detail: String?,
    ): Map<String, Any?> {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(ACTIVE_STATE, "service_start_restricted")
            .putString(ACTIVE_FAILURE_CODE, "foreground_service_start_not_allowed")
            .remove(ACTIVE_TASK_ID)
            .apply()
        return mapOf(
            "state" to "service_start_restricted",
            "taskId" to taskId,
            "message" to
                (detail ?: "系统限制从当前状态启动前台 dataSync 服务。请保持应用在前台后重试。"),
            "failureCode" to "foreground_service_start_not_allowed",
        )
    }

    private fun serviceIntent(action: String, call: MethodCall): Intent {
        return Intent(context, DataSyncForegroundService::class.java).apply {
            this.action = action
            putExtra("taskId", call.argument<String>("taskId"))
            putExtra("title", call.argument<String>("title"))
            putExtra("text", call.argument<String>("text"))
            putExtra("message", call.argument<String>("message"))
            putExtra("reason", call.argument<String>("reason"))
            putExtra("progress", call.argument<Double>("progress"))
        }
    }

    private fun startForegroundService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
}
