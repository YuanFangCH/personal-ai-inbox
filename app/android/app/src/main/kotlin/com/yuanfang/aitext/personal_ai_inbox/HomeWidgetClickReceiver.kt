package com.yuanfang.aitext.personal_ai_inbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class HomeWidgetClickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        HomeWidgetNavigation.handleCollectionClick(context, intent)
    }
}
