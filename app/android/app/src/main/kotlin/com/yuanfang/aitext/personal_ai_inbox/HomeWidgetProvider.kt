package com.yuanfang.aitext.personal_ai_inbox

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle

class HomeWidgetProvider : AppWidgetProvider() {
    companion object {
        const val EXTRA_PIN_CARD_ID =
            "com.yuanfang.aitext.personal_ai_inbox.extra.HOME_WIDGET_PIN_CARD_ID"

        fun bind(context: Context, widgetId: Int, cardId: String): Boolean {
            return validInstance(context, widgetId) &&
                HomeWidgetSnapshotStore.bind(context, widgetId, cardId)
        }

        fun render(context: Context, widgetId: Int): Boolean {
            if (!validInstance(context, widgetId)) {
                return false
            }
            val manager = AppWidgetManager.getInstance(context)
            return runCatching {
                HomeWidgetRenderer.render(context, manager, widgetId)
            }.getOrDefault(false)
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            component(context).let { provider ->
                manager.getAppWidgetIds(provider).forEach { widgetId ->
                    render(context, widgetId)
                }
            }
        }

        fun publishAndRender(context: Context): Pair<Int, Int> {
            val manager = AppWidgetManager.getInstance(context)
            var submitted = 0
            var failed = 0
            manager.getAppWidgetIds(component(context)).forEach { widgetId ->
                if (HomeWidgetSnapshotStore.boundCardId(context, widgetId) == null) {
                    return@forEach
                }
                if (render(context, widgetId)) {
                    submitted += 1
                } else {
                    failed += 1
                }
            }
            return submitted to failed
        }

        fun requestPin(context: Context, cardId: String): String {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return "unsupported"
            }
            val manager = AppWidgetManager.getInstance(context)
            if (!manager.isRequestPinAppWidgetSupported) {
                return "unsupported"
            }
            val card = HomeWidgetSnapshotStore.load(context)?.card(cardId)
            if (card == null || card.state == "archived") {
                return "failed"
            }
            val callbackIntent = Intent(context, HomeWidgetPinReceiver::class.java)
                .putExtra(EXTRA_PIN_CARD_ID, cardId)
            var callbackFlags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                callbackFlags = callbackFlags or PendingIntent.FLAG_MUTABLE
            }
            val callback = PendingIntent.getBroadcast(
                context,
                cardId.hashCode(),
                callbackIntent,
                callbackFlags,
            )
            return if (manager.requestPinAppWidget(component(context), null, callback)) {
                "requested"
            } else {
                "failed"
            }
        }

        private fun component(context: Context) =
            ComponentName(context, HomeWidgetProvider::class.java)

        private fun validInstance(context: Context, widgetId: Int): Boolean {
            if (widgetId <= 0) {
                return false
            }
            return AppWidgetManager.getInstance(context)
                .getAppWidgetInfo(widgetId)
                ?.provider == component(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            render(context, widgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetId)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        HomeWidgetSnapshotStore.removeBindings(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onRestored(
        context: Context,
        oldWidgetIds: IntArray,
        newWidgetIds: IntArray,
    ) {
        HomeWidgetSnapshotStore.removeBindings(context, newWidgetIds)
        newWidgetIds.forEach { widgetId ->
            render(context, widgetId)
        }
        super.onRestored(context, oldWidgetIds, newWidgetIds)
    }

    override fun onEnabled(context: Context) {
        refreshAll(context)
    }
}
