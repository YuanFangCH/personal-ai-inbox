package com.yuanfang.aitext.personal_ai_inbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Debug-only fault entrypoint used by the isolated emulator fault-injection scripts.
 *
 * This class lives in the debug source set and is not packaged in release builds.
 */
class DebugAgentBackgroundFaultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra(EXTRA_ACTION).orEmpty()
        val application = AitextApplication.from(context)
        when (action) {
            ACTION_RECREATE_ACTIVITY -> {
                val accepted = application.backgroundController.recreateAttachedActivity()
                Log.i(TAG, "$ACTION_RECREATE_ACTIVITY accepted=$accepted")
            }
            ACTION_PAUSE -> forwardServiceAction(context, DataSyncForegroundService.ACTION_PAUSE)
            ACTION_CANCEL -> forwardServiceAction(context, DataSyncForegroundService.ACTION_CANCEL)
            ACTION_TIMEOUT -> forwardServiceAction(context, DataSyncForegroundService.ACTION_DEBUG_TIMEOUT)
            ACTION_STOP_SERVICE -> stopServiceAndAwaitDartAck(context)
            else -> Log.w(TAG, "Unknown debug background action: $action")
        }
    }

    private fun stopServiceAndAwaitDartAck(context: Context) {
        val pending = goAsync()
        val taskId = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(ACTIVE_TASK_ID, null)
            .orEmpty()
        val finished = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        lateinit var ackReceiver: BroadcastReceiver

        fun finish(outcome: String) {
            if (!finished.compareAndSet(false, true)) return
            handler.removeCallbacksAndMessages(null)
            try {
                context.unregisterReceiver(ackReceiver)
            } catch (_: IllegalArgumentException) {
                // The receiver may not have been registered if registration failed.
            }
            Log.i(TAG, "$ACTION_STOP_SERVICE outcome=$outcome taskId=$taskId")
            pending.finish()
        }

        ackReceiver = object : BroadcastReceiver() {
            override fun onReceive(ackContext: Context, ackIntent: Intent) {
                val dartAckReceived = ackIntent.getBooleanExtra("dartAckReceived", false)
                val eventTaskId = ackIntent.getStringExtra("eventTaskId").orEmpty()
                val currentTaskId = ackIntent.getStringExtra("currentTaskId").orEmpty()
                val taskIdMatched = ackIntent.getBooleanExtra("taskIdMatched", false)
                val matched = dartAckReceived &&
                    eventTaskId == taskId &&
                    currentTaskId == taskId &&
                    taskIdMatched
                Log.i(
                    TAG,
                    "$ACTION_STOP_SERVICE dartAck=$dartAckReceived eventTaskId=$eventTaskId " +
                        "currentTaskId=$currentTaskId taskIdMatched=$taskIdMatched",
                )
                finish(if (matched) "dart_ack_matched" else "dart_ack_mismatch")
            }
        }

        try {
            context.registerReceiver(
                ackReceiver,
                IntentFilter(DataSyncForegroundService.ACTION_DEBUG_STOP_ACK),
                Context.RECEIVER_NOT_EXPORTED,
            )
        } catch (error: Exception) {
            Log.e(TAG, "$ACTION_STOP_SERVICE ack receiver registration failed", error)
            finish("ack_receiver_registration_failed")
            return
        }

        val stopped = context.stopService(
            Intent(context, DataSyncForegroundService::class.java),
        )
        Log.i(TAG, "$ACTION_STOP_SERVICE stopped=$stopped taskId=$taskId")
        if (!stopped) {
            finish("stop_not_accepted")
            return
        }
        handler.postDelayed({ finish("dart_ack_timeout") }, ACK_TIMEOUT_MS)
    }

    private fun forwardServiceAction(context: Context, action: String) {
        context.startService(
            Intent(context, DataSyncForegroundService::class.java).apply {
                this.action = action
            },
        )
        Log.i(TAG, "Forwarded debug service action=$action")
    }

    companion object {
        const val ACTION = "com.yuanfang.aitext.personal_ai_inbox.DEBUG_BACKGROUND_FAULT"
        const val EXTRA_ACTION = "fault_action"
        const val ACTION_RECREATE_ACTIVITY = "recreate_activity"
        const val ACTION_PAUSE = "pause"
        const val ACTION_CANCEL = "cancel"
        const val ACTION_TIMEOUT = "timeout"
        const val ACTION_STOP_SERVICE = "stop_service"
        private const val PREFS = "agent_background_state"
        private const val ACTIVE_TASK_ID = "active_task_id"
        private const val ACK_TIMEOUT_MS = 8_000L
        private const val TAG = "AgentBackgroundFault"
    }
}
