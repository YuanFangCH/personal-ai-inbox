package com.yuanfang.aitext.personal_ai_inbox

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

class HomeWidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        val cardId = intent.getStringExtra(HomeWidgetProvider.EXTRA_PIN_CARD_ID)
        if (widgetId <= 0 || cardId.isNullOrBlank()) {
            return
        }
        if (HomeWidgetProvider.bind(context, widgetId, cardId)) {
            HomeWidgetProvider.render(context, widgetId)
            Toast.makeText(context, R.string.home_widget_pinned, Toast.LENGTH_SHORT).show()
        }
    }
}
