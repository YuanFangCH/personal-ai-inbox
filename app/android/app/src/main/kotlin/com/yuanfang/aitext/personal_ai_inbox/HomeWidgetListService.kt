package com.yuanfang.aitext.personal_ai_inbox

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class HomeWidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        HomeWidgetListFactory(
            applicationContext,
            intent.getIntExtra(EXTRA_WIDGET_ID, -1),
        )

    companion object {
        const val EXTRA_WIDGET_ID =
            "com.yuanfang.aitext.personal_ai_inbox.extra.HOME_WIDGET_ID"
    }
}

private class HomeWidgetListFactory(
    private val context: Context,
    private val widgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private var card: HomeWidgetCard? = null
    private var rows: List<HomeWidgetRow> = emptyList()

    override fun onCreate() {
        reload()
    }

    override fun onDataSetChanged() {
        reload()
    }

    override fun onDestroy() {
        card = null
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val currentCard = card
        val row = rows.getOrNull(position)
        if (currentCard == null || row == null) {
            return RemoteViews(
                context.packageName,
                R.layout.home_widget_entry_item,
            )
        }
        return HomeWidgetRenderer.entryItem(
            context,
            widgetId,
            currentCard,
            row,
        )
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long {
        val currentCard = card ?: return 0L
        val row = rows.getOrNull(position) ?: return 0L
        return HomeWidgetRenderer.itemId(widgetId, currentCard, row)
    }

    override fun hasStableIds(): Boolean = true

    private fun reload() {
        if (widgetId <= 0) {
            card = null
            rows = emptyList()
            return
        }
        val cardId = HomeWidgetSnapshotStore.boundCardId(context, widgetId)
        card = HomeWidgetSnapshotStore.load(context)?.card(cardId)
        rows = card?.rows
            ?.filter { it.kind == "entry" }
            .orEmpty()
    }
}
