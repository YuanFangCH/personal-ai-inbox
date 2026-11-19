package com.yuanfang.aitext.personal_ai_inbox

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.view.View
import android.widget.RemoteViews

internal object HomeWidgetRenderer {
    private data class Palette(
        val background: Int,
        val header: Int,
        val textPrimary: Int,
        val textSecondary: Int,
        val accent: Int,
    )

    @Suppress("DEPRECATION")
    fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
    ): Boolean {
        val binding = HomeWidgetSnapshotStore.boundCardId(context, widgetId)
        val snapshot = HomeWidgetSnapshotStore.load(context)
        if (binding != null && snapshot != null && snapshot.card(binding) == null) {
            HomeWidgetSnapshotStore.removeBinding(context, widgetId)
            return renderPlaceholder(
                context,
                manager,
                widgetId,
                null,
                context.getString(R.string.home_widget_card_unavailable),
            )
        }
        val card = snapshot?.card(binding)
        if (binding == null || card == null) {
            return renderPlaceholder(
                context,
                manager,
                widgetId,
                card,
                if (snapshot == null) {
                    context.getString(R.string.home_widget_not_synced)
                } else {
                    context.getString(R.string.home_widget_not_configured)
                },
            )
        }
        if (card.state == "archived") {
            return renderPlaceholder(
                context,
                manager,
                widgetId,
                card,
                context.getString(R.string.home_widget_archived),
            )
        }
        if (card.state == "blocked" || card.state == "error") {
            return renderPlaceholder(
                context,
                manager,
                widgetId,
                card,
                context.getString(
                    if (card.state == "blocked") {
                        R.string.home_widget_blocked
                    } else {
                        R.string.home_widget_error
                    },
                ),
            )
        }

        val views = timelineViews(
            context,
            widgetId,
            card,
            palette(context, card.theme),
        )
        manager.updateAppWidget(widgetId, views)
        manager.notifyAppWidgetViewDataChanged(widgetId, R.id.widget_list)
        return true
    }

    fun entryItem(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
    ): RemoteViews {
        val colors = palette(context, card.theme)
        return RemoteViews(
            context.packageName,
            R.layout.home_widget_entry_item,
        ).apply {
            setTextViewText(R.id.entry_title, row.title)
            setTextColor(
                R.id.entry_title,
                context.getColor(colors.textPrimary),
            )
            val detail = row.detail.orEmpty()
            setTextViewText(R.id.entry_detail, detail)
            setTextColor(
                R.id.entry_detail,
                context.getColor(colors.textSecondary),
            )
            setViewVisibility(
                R.id.entry_detail,
                if (detail.isBlank()) View.GONE else View.VISIBLE,
            )
            setOnClickFillInIntent(
                R.id.entry_card,
                HomeWidgetNavigation.fillInIntent(
                    context,
                    HomeWidgetOpenTarget(
                        kind = "entry",
                        widgetId = widgetId,
                        cardId = card.cardId,
                        cardRevision = card.revision,
                        tableId = row.tableId,
                        entryId = row.entryId,
                        rowHash = card.rowHash(row),
                    ),
                ),
            )
        }
    }

    fun itemId(
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
    ): Long {
        val key = listOf(
            widgetId.toString(),
            card.cardId,
            card.revision.toString(),
            row.tableId,
            row.entryId.orEmpty(),
        ).joinToString("|")
        var hash = 1125899906842597L
        key.forEach { character ->
            hash = 31L * hash + character.code
        }
        return hash
    }

    @Suppress("DEPRECATION")
    private fun timelineViews(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        colors: Palette,
    ): RemoteViews {
        val views = RemoteViews(
            context.packageName,
            R.layout.home_widget_scroll,
        )
        bindHeader(context, views, widgetId, card, colors)
        views.setRemoteAdapter(
            R.id.widget_list,
            Intent(context, HomeWidgetListService::class.java).putExtra(
                HomeWidgetListService.EXTRA_WIDGET_ID,
                widgetId,
            ),
        )
        views.setPendingIntentTemplate(
            R.id.widget_list,
            HomeWidgetNavigation.pendingIntentTemplate(context, widgetId),
        )
        views.setEmptyView(R.id.widget_list, R.id.widget_list_empty)
        views.setTextViewText(
            R.id.widget_list_empty,
            context.getString(R.string.home_widget_empty),
        )
        views.setTextColor(
            R.id.widget_list_empty,
            context.getColor(colors.textSecondary),
        )
        val hasDate = card.dataDay.isNotBlank()
        views.setTextViewText(
            R.id.scroll_data_date,
            if (hasDate) {
                context.getString(
                    R.string.home_widget_data_date,
                    card.dataDay,
                )
            } else {
                ""
            },
        )
        views.setTextColor(
            R.id.scroll_data_date,
            context.getColor(colors.textSecondary),
        )
        views.setViewVisibility(
            R.id.scroll_data_date,
            if (hasDate) View.VISIBLE else View.GONE,
        )
        return views
    }

    private fun bindHeader(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        card: HomeWidgetCard,
        colors: Palette,
    ) {
        views.setInt(R.id.widget_root, "setBackgroundResource", colors.background)
        views.setInt(R.id.widget_header, "setBackgroundResource", colors.header)
        views.setTextViewText(R.id.widget_title, card.title)
        views.setTextColor(
            R.id.widget_title,
            context.getColor(colors.textPrimary),
        )
        views.setViewVisibility(R.id.widget_title, View.VISIBLE)
        val hasDate = card.dataDay.isNotBlank()
        views.setTextViewText(
            R.id.widget_date,
            if (hasDate) {
                context.getString(
                    R.string.home_widget_data_date,
                    card.dataDay,
                )
            } else {
                ""
            },
        )
        views.setTextColor(
            R.id.widget_date,
            context.getColor(colors.textSecondary),
        )
        views.setViewVisibility(
            R.id.widget_date,
            if (hasDate) View.VISIBLE else View.GONE,
        )
        views.setOnClickPendingIntent(
            R.id.widget_header,
            HomeWidgetNavigation.pendingIntent(
                context,
                HomeWidgetOpenTarget(kind = "settings", widgetId = widgetId),
            ),
        )
    }

    private fun renderPlaceholder(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        card: HomeWidgetCard?,
        message: String,
    ): Boolean {
        val colors = palette(context, card?.theme ?: "system")
        val views = RemoteViews(
            context.packageName,
            R.layout.home_widget_placeholder,
        )
        views.setInt(
            R.id.widget_root,
            "setBackgroundResource",
            colors.background,
        )
        views.setTextViewText(
            R.id.widget_title,
            card?.title ?: context.getString(R.string.home_widget_title),
        )
        views.setTextColor(
            R.id.widget_title,
            context.getColor(colors.textPrimary),
        )
        views.setTextViewText(
            R.id.widget_date,
            if (card?.dataDay.isNullOrBlank()) {
                context.getString(R.string.home_widget_no_data_date)
            } else {
                context.getString(
                    R.string.home_widget_data_date,
                    card.dataDay,
                )
            },
        )
        views.setTextColor(
            R.id.widget_date,
            context.getColor(colors.textSecondary),
        )
        views.setTextViewText(R.id.widget_placeholder, message)
        views.setTextColor(
            R.id.widget_placeholder,
            context.getColor(colors.textSecondary),
        )
        views.setOnClickPendingIntent(
            R.id.widget_placeholder_action,
            HomeWidgetNavigation.pendingIntent(
                context,
                HomeWidgetOpenTarget(kind = "settings", widgetId = widgetId),
            ),
        )
        views.setTextViewText(
            R.id.widget_placeholder_action,
            context.getString(R.string.home_widget_open_settings),
        )
        views.setTextColor(
            R.id.widget_placeholder_action,
            context.getColor(colors.accent),
        )
        manager.updateAppWidget(widgetId, views)
        return true
    }

    private fun palette(context: Context, theme: String): Palette {
        val dark = when (theme) {
            "dark" -> true
            "light" -> false
            else -> {
                context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK ==
                    Configuration.UI_MODE_NIGHT_YES
            }
        }
        return if (dark) {
            Palette(
                background = R.drawable.home_widget_background_dark,
                header = R.drawable.home_widget_section_dark,
                textPrimary = R.color.home_widget_text_primary_dark,
                textSecondary = R.color.home_widget_text_secondary_dark,
                accent = R.color.home_widget_accent_dark,
            )
        } else {
            Palette(
                background = R.drawable.home_widget_background_light,
                header = R.drawable.home_widget_section_light,
                textPrimary = R.color.home_widget_text_primary_light,
                textSecondary = R.color.home_widget_text_secondary_light,
                accent = R.color.home_widget_accent_light,
            )
        }
    }
}
