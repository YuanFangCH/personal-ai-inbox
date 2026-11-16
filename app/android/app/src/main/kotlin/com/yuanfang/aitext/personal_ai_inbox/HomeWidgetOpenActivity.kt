package com.yuanfang.aitext.personal_ai_inbox

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.os.Bundle
import android.widget.Toast

class HomeWidgetOpenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val target = HomeWidgetNavigation.fromOpenActivityIntent(intent)
        if (target == null || !HomeWidgetNavigation.validate(this, target)) {
            Toast.makeText(this, R.string.home_widget_row_expired, Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        if (target.kind == "page") {
            val cardId = target.cardId
            val revision = target.cardRevision
            val generatedAt = target.generatedAtMs
            val pageIndex = target.pageIndex
            val shown = cardId != null && revision != null && generatedAt != null &&
                pageIndex != null &&
                HomeWidgetRenderer.showPage(
                    this,
                    AppWidgetManager.getInstance(this),
                    HomeWidgetPageRequest(
                        target.widgetId,
                        cardId,
                        revision,
                        generatedAt,
                        pageIndex,
                    ),
                )
            if (!shown) {
                Toast.makeText(this, R.string.home_widget_row_expired, Toast.LENGTH_SHORT).show()
            }
            finish()
            return
        }
        HomeWidgetOpenQueue.offer(target)
        startActivity(HomeWidgetNavigation.mainActivityIntent(this))
        finish()
    }
}
