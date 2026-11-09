package com.yuanfang.aitext.personal_ai_inbox

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

internal class HomeWidgetChannelHandler(
    private val activity: Activity,
) {
    companion object {
        const val CHANNEL_NAME =
            "com.yuanfang.aitext.personal_ai_inbox/home_widgets"
    }

    private val storageExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "home-widget-native-storage").apply {
                isDaemon = true
            }
        }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStoreDirectory" -> {
                result.success(HomeWidgetSnapshotStore.directory(activity).absolutePath)
            }

            "publishSnapshots" -> publishSnapshots(call, result)
            "clearSnapshots" -> clearSnapshots(result)

            "requestPin" -> {
                val cardId = call.argument<String>("card_id")
                result.success(
                    if (cardId.isNullOrBlank()) {
                        "failed"
                    } else {
                        HomeWidgetProvider.requestPin(activity, cardId)
                    },
                )
            }

            "takeOpenTarget" -> {
                result.success(HomeWidgetOpenQueue.take()?.toMap())
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        storageExecutor.shutdown()
    }

    fun announceIfPending(channel: MethodChannel) {
        if (HomeWidgetOpenQueue.hasPending()) {
            channel.invokeMethod("openTargetAvailable", null)
        }
    }

    private fun publishSnapshots(call: MethodCall, result: MethodChannel.Result) {
        val snapshotJson = call.argument<String>("snapshot_json")
        if (snapshotJson == null) {
            result.error("invalid_argument", "snapshot_json is required", null)
            return
        }
        executeStorageTask(result) {
            HomeWidgetSnapshotStore.publish(activity, snapshotJson)
            val (submitted, failed) = HomeWidgetProvider.publishAndRender(activity)
            mapOf(
                "submitted_count" to submitted,
                "failed_count" to failed,
            )
        }
    }

    private fun clearSnapshots(result: MethodChannel.Result) {
        executeStorageTask(result) {
            HomeWidgetSnapshotStore.clear(activity)
            HomeWidgetProvider.refreshAll(activity)
            null
        }
    }

    private fun executeStorageTask(
        result: MethodChannel.Result,
        task: () -> Any?,
    ) {
        try {
            storageExecutor.execute {
                val outcome = runCatching(task)
                activity.runOnUiThread {
                    outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = { error ->
                            result.error(errorCode(error), error.message ?: error.javaClass.simpleName, null)
                        },
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("storage_error", "Home widget storage executor is unavailable", null)
        }
    }

    private fun errorCode(error: Throwable): String {
        return if (error is IllegalArgumentException || error is JSONException) {
            "invalid_argument"
        } else {
            "storage_error"
        }
    }
}
