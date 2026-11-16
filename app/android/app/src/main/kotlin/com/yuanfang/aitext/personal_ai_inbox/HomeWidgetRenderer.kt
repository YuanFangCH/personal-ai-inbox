package com.yuanfang.aitext.personal_ai_inbox

import android.annotation.TargetApi
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.content.pm.ApplicationInfo
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RemoteViews

internal object HomeWidgetRenderer {
    private const val DEFAULT_WIDTH_DP = 300
    private const val DEFAULT_HEIGHT_DP = 260
    private const val FIXED_ROW_COUNT = 6

    private data class Palette(
        val background: Int,
        val surface: Int,
        val section: Int,
        val textPrimary: Int,
        val textSecondary: Int,
        val accent: Int,
    )

    fun render(context: Context, manager: AppWidgetManager, widgetId: Int): Boolean {
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

        val palette = palette(context, card.theme)
        val options = manager.getAppWidgetOptions(widgetId)
        val width = options.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
            DEFAULT_WIDTH_DP,
        ).coerceAtLeast(1)
        val height = options.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
            DEFAULT_HEIGHT_DP,
        ).coerceAtLeast(1)
        if (
            context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        ) {
            Log.d("HomeWidgetRenderer", "widget=$widgetId width=$width height=$height")
        }
        val views = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                scrollViews(context, manager, widgetId, card, palette)

            else -> fixedViews(
                context,
                widgetId,
                card,
                palette,
                rowsPerPage(height, context.resources.configuration.fontScale, Build.VERSION.SDK_INT),
                HomeWidgetSnapshotStore.pageIndex(context, widgetId),
            )
        }
        manager.updateAppWidget(widgetId, views)
        return true
    }

    private fun compactViews(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        palette: Palette,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.home_widget_compact)
        bindHeader(context, views, widgetId, card, palette)
        val sections = card.rows.filter { it.kind == "section" }.take(2)
        val slots = listOf(
            Triple(R.id.compact_primary, R.id.compact_primary_title, R.id.compact_primary_count),
            Triple(R.id.compact_secondary, R.id.compact_secondary_title, R.id.compact_secondary_count),
        )
        slots.forEachIndexed { index, (containerId, titleId, countId) ->
            val section = sections.getOrNull(index)
            if (section == null) {
                views.setViewVisibility(containerId, View.GONE)
            } else {
                views.setViewVisibility(containerId, View.VISIBLE)
                views.setInt(containerId, "setBackgroundResource", palette.surface)
                views.setTextViewText(titleId, section.title)
                views.setTextViewText(
                    countId,
                    context.getString(R.string.home_widget_table_count, section.count),
                )
                views.setTextColor(titleId, context.getColor(palette.textPrimary))
                views.setTextColor(countId, context.getColor(palette.textSecondary))
                views.setOnClickPendingIntent(
                    containerId,
                    tablePendingIntent(context, widgetId, card, section),
                )
            }
        }
        if (card.rows.isEmpty() || sections.isEmpty()) {
            views.setTextViewText(
                R.id.compact_empty,
                context.getString(R.string.home_widget_empty),
            )
            views.setTextColor(R.id.compact_empty, context.getColor(palette.textSecondary))
            views.setViewVisibility(R.id.compact_empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.compact_empty, View.GONE)
        }
        return views
    }

    @TargetApi(Build.VERSION_CODES.S)
    private fun scrollViews(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        card: HomeWidgetCard,
        palette: Palette,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.home_widget_scroll)
        bindHeader(context, views, widgetId, card, palette)
        views.setViewVisibility(R.id.widget_header, View.GONE)
        views.setTextViewText(
            R.id.scroll_data_date,
            if (card.dataDay.isBlank()) "" else context.getString(R.string.home_widget_data_date, card.dataDay),
        )
        views.setTextColor(R.id.scroll_data_date, context.getColor(palette.textSecondary))
        views.setViewVisibility(
            R.id.scroll_data_date,
            if (card.dataDay.isBlank()) View.GONE else View.VISIBLE,
        )
        val pages = HomeWidgetPager.paginate(
            card.rows,
            HomeWidgetPager.rowsPerPage(
                manager.getAppWidgetOptions(widgetId).getInt(
                    AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
                    DEFAULT_HEIGHT_DP,
                ),
                context.resources.configuration.fontScale,
            ),
        )
        val items = RemoteViews.RemoteCollectionItems.Builder()
            .setHasStableIds(true)
            .setViewTypeCount(1)
        val wide = manager.getAppWidgetOptions(widgetId).getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
            180,
        ) >= 220
        pages.forEach { page ->
            items.addItem(page.index.toLong(), pageItem(context, widgetId, card, page, pages.size, palette, wide))
        }
        views.setPendingIntentTemplate(
            R.id.widget_list,
            HomeWidgetNavigation.pendingIntentTemplate(context, widgetId),
        )
        views.setRemoteAdapter(R.id.widget_list, items.build())
        views.setEmptyView(R.id.widget_list, R.id.widget_list_empty)
        views.setTextViewText(R.id.widget_list_empty, context.getString(R.string.home_widget_empty))
        views.setTextColor(R.id.widget_list_empty, context.getColor(palette.textSecondary))
        views.setViewVisibility(R.id.scroll_hint, View.GONE)
        views.setViewVisibility(R.id.scroll_more, View.GONE)
        return views
    }

    private fun pageItem(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        page: HomeWidgetPage,
        pageCount: Int,
        palette: Palette,
        wide: Boolean,
    ): RemoteViews {
        val pageViews = RemoteViews(context.packageName, R.layout.home_widget_page)
        pageViews.setInt(R.id.widget_page_root, "setBackgroundResource", palette.background)
        page.rows.forEach { row -> pageViews.addView(R.id.widget_page_rows, entryItem(context, widgetId, card, row, palette, wide)) }
        pageViews.setTextViewText(R.id.widget_page_counter, "${page.index + 1} / $pageCount")
        pageViews.setTextColor(R.id.widget_page_counter, context.getColor(palette.accent))
        pageViews.setTextColor(R.id.widget_page_previous, context.getColor(palette.accent))
        pageViews.setTextColor(R.id.widget_page_next, context.getColor(palette.accent))
        val previous = page.index - 1
        val next = page.index + 1
        pageViews.setViewVisibility(
            R.id.widget_page_footer,
            if (pageCount > 1) View.VISIBLE else View.GONE,
        )
        if (pageCount > 1) {
            pageViews.setOnClickFillInIntent(
                R.id.widget_page_previous,
                HomeWidgetNavigation.fillInIntent(context, pageTarget(widgetId, card, previous)),
            )
            pageViews.setOnClickFillInIntent(
                R.id.widget_page_next,
                HomeWidgetNavigation.fillInIntent(context, pageTarget(widgetId, card, next)),
            )
        }
        pageViews.setViewVisibility(
            R.id.widget_page_previous,
            if (previous >= 0) View.VISIBLE else View.INVISIBLE,
        )
        pageViews.setViewVisibility(
            R.id.widget_page_next,
            if (next < pageCount) View.VISIBLE else View.INVISIBLE,
        )
        return pageViews
    }

    private fun pageTarget(widgetId: Int, card: HomeWidgetCard, pageIndex: Int) =
        HomeWidgetOpenTarget(
            kind = "page", widgetId = widgetId, cardId = card.cardId,
            cardRevision = card.revision, generatedAtMs = card.generatedAtMs,
            pageIndex = pageIndex,
        )

    fun rowsPerPage(heightDp: Int, fontScale: Float, apiLevel: Int): Int {
        val capacity = HomeWidgetPager.rowsPerPage(heightDp, fontScale)
        return if (apiLevel < Build.VERSION_CODES.S) capacity.coerceAtMost(FIXED_ROW_COUNT) else capacity
    }

    fun showPage(context: Context, manager: AppWidgetManager, request: HomeWidgetPageRequest): Boolean {
        if (manager.getAppWidgetInfo(request.widgetId)?.provider !=
            android.content.ComponentName(context, HomeWidgetProvider::class.java)) return false
        val card = HomeWidgetSnapshotStore.load(context)?.card(request.cardId) ?: return false
        if (card.revision != request.revision || card.generatedAtMs != request.generatedAtMs ||
            HomeWidgetSnapshotStore.boundCardId(context, request.widgetId) != request.cardId) return false
        val height = manager.getAppWidgetOptions(request.widgetId).getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, DEFAULT_HEIGHT_DP,
        )
        val pages = HomeWidgetPager.paginate(
            card.rows,
            rowsPerPage(height, context.resources.configuration.fontScale, Build.VERSION.SDK_INT),
        )
        if (request.pageIndex !in pages.indices) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            HomeWidgetSnapshotStore.setPageIndex(context, request.widgetId, request.pageIndex)
            return render(context, manager, request.widgetId)
        }
        return runCatching {
            manager.partiallyUpdateAppWidget(
                request.widgetId,
                RemoteViews(context.packageName, R.layout.home_widget_scroll).apply {
                    setDisplayedChild(R.id.widget_list, request.pageIndex)
                },
            )
            true
        }.getOrDefault(false)
    }

    private fun fixedViews(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        palette: Palette,
        rowLimit: Int,
        pageIndex: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.home_widget_fixed)
        bindHeader(context, views, widgetId, card, palette)
        val rowIds = listOf(
            arrayOf(R.id.fixed_row_0, R.id.fixed_row_0_title, R.id.fixed_row_0_detail),
            arrayOf(R.id.fixed_row_1, R.id.fixed_row_1_title, R.id.fixed_row_1_detail),
            arrayOf(R.id.fixed_row_2, R.id.fixed_row_2_title, R.id.fixed_row_2_detail),
            arrayOf(R.id.fixed_row_3, R.id.fixed_row_3_title, R.id.fixed_row_3_detail),
            arrayOf(R.id.fixed_row_4, R.id.fixed_row_4_title, R.id.fixed_row_4_detail),
            arrayOf(R.id.fixed_row_5, R.id.fixed_row_5_title, R.id.fixed_row_5_detail),
        )
        val pages = HomeWidgetPager.paginate(card.rows, rowLimit)
        val page = pages.getOrNull(pageIndex) ?: pages.firstOrNull()
        rowIds.forEachIndexed { index, ids ->
            val row = page?.rows?.getOrNull(index)
            if (row == null) {
                views.setViewVisibility(ids[0], View.GONE)
            } else {
                views.setViewVisibility(ids[0], View.VISIBLE)
                views.setInt(
                    ids[0],
                    "setBackgroundResource",
                    if (row.kind == "section") palette.section else palette.surface,
                )
                views.setTextViewText(ids[1], row.title)
                views.setTextColor(ids[1], context.getColor(palette.textPrimary))
                views.setTextViewText(ids[2], fixedDetail(context, row))
                views.setTextColor(ids[2], context.getColor(palette.textSecondary))
                views.setOnClickPendingIntent(
                    ids[0],
                    if (row.kind == "section") {
                        tablePendingIntent(context, widgetId, card, row)
                    } else {
                        entryPendingIntent(context, widgetId, card, row)
                    },
                )
            }
        }
        val empty = card.rows.isEmpty()
        views.setViewVisibility(R.id.fixed_empty, if (empty) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.fixed_empty, context.getString(R.string.home_widget_empty))
        views.setTextColor(R.id.fixed_empty, context.getColor(palette.textSecondary))
        val showMore = pages.size > 1
        views.setViewVisibility(R.id.fixed_more, if (showMore) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.fixed_more, "${(page?.index ?: 0) + 1} / ${pages.size}")
        views.setTextColor(R.id.fixed_more, context.getColor(palette.accent))
        views.setOnClickPendingIntent(
            R.id.fixed_more,
            HomeWidgetNavigation.pagePendingIntent(context, pageTarget(widgetId, card,
                if (pageIndex + 1 < pages.size) pageIndex + 1 else 0)),
        )
        return views
    }

    private fun bindHeader(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        card: HomeWidgetCard,
        palette: Palette,
    ) {
        views.setInt(R.id.widget_root, "setBackgroundResource", palette.background)
        views.setInt(R.id.widget_header, "setBackgroundResource", palette.background)
        views.setTextViewText(R.id.widget_title, card.title)
        views.setViewVisibility(R.id.widget_title, View.GONE)
        views.setTextColor(R.id.widget_title, context.getColor(palette.textPrimary))
        views.setViewVisibility(R.id.widget_date, if (card.dataDay.isBlank()) View.GONE else View.VISIBLE)
        views.setTextViewText(
            R.id.widget_date,
            context.getString(R.string.home_widget_data_date, card.dataDay),
        )
        views.setTextColor(R.id.widget_date, context.getColor(palette.textSecondary))
        views.setOnClickPendingIntent(
            R.id.widget_header,
            HomeWidgetNavigation.pendingIntent(
                context,
                HomeWidgetOpenTarget(kind = "settings", widgetId = widgetId),
            ),
        )
    }

    private fun sectionItem(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
        palette: Palette,
        wide: Boolean = false,
    ): RemoteViews {
        val target =
            HomeWidgetOpenTarget(
                kind = "table",
                widgetId = widgetId,
                cardId = card.cardId,
                cardRevision = card.revision,
                tableId = row.tableId,
                rowHash = card.rowHash(row),
            )
        return RemoteViews(context.packageName, R.layout.home_widget_section_item).apply {
            setInt(R.id.section_card, "setBackgroundResource", palette.section)
            setTextViewText(R.id.section_title, row.title)
            setTextViewText(
                R.id.section_count,
                context.getString(R.string.home_widget_table_count, row.count),
            )
            setTextColor(R.id.section_title, context.getColor(palette.textPrimary))
            setTextColor(R.id.section_count, context.getColor(palette.textSecondary))
            setOnClickFillInIntent(
                R.id.section_card,
                HomeWidgetNavigation.fillInIntent(
                    context,
                    target,
                ),
            )
        }
    }

    private fun entryItem(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
        palette: Palette,
        wide: Boolean = false,
    ): RemoteViews {
        return RemoteViews(
            context.packageName,
            if (wide && row.detail != null) R.layout.home_widget_entry_item_wide
            else R.layout.home_widget_entry_item,
        ).apply {
            setInt(R.id.entry_card, "setBackgroundResource", palette.surface)
            setTextViewText(R.id.entry_title, row.title)
            setTextViewText(R.id.entry_detail, row.detail.orEmpty())
            setTextColor(R.id.entry_title, context.getColor(palette.textPrimary))
            setTextColor(R.id.entry_detail, context.getColor(palette.textSecondary))
            setViewVisibility(R.id.entry_badge, View.GONE)
            setOnClickFillInIntent(
                R.id.entry_card,
                HomeWidgetNavigation.fillInIntent(context, entryTarget(widgetId, card, row)),
            )
        }
    }

    private fun entryTarget(widgetId: Int, card: HomeWidgetCard, row: HomeWidgetRow) =
        HomeWidgetOpenTarget(
            kind = "entry",
            widgetId = widgetId,
            cardId = card.cardId,
            cardRevision = card.revision,
            tableId = row.tableId,
            entryId = row.entryId,
            rowHash = card.rowHash(row),
        )

    private fun renderPlaceholder(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        card: HomeWidgetCard?,
        message: String,
    ): Boolean {
        val palette = palette(context, card?.theme ?: "system")
        val views = RemoteViews(context.packageName, R.layout.home_widget_placeholder)
        views.setInt(R.id.widget_root, "setBackgroundResource", palette.background)
        views.setTextViewText(R.id.widget_title, card?.title ?: context.getString(R.string.home_widget_title))
        views.setTextColor(R.id.widget_title, context.getColor(palette.textPrimary))
        views.setTextViewText(
            R.id.widget_date,
            if (card?.dataDay.isNullOrBlank()) {
                context.getString(R.string.home_widget_no_data_date)
            } else {
                context.getString(R.string.home_widget_data_date, card.dataDay)
            },
        )
        views.setTextColor(R.id.widget_date, context.getColor(palette.textSecondary))
        views.setTextViewText(R.id.widget_placeholder, message)
        views.setTextColor(R.id.widget_placeholder, context.getColor(palette.textSecondary))
        val settings = HomeWidgetNavigation.pendingIntent(
            context,
            HomeWidgetOpenTarget(kind = "settings", widgetId = widgetId),
        )
        views.setOnClickPendingIntent(R.id.widget_placeholder_action, settings)
        views.setTextViewText(
            R.id.widget_placeholder_action,
            context.getString(R.string.home_widget_open_settings),
        )
        views.setTextColor(
            R.id.widget_placeholder_action,
            context.getColor(palette.accent),
        )
        manager.updateAppWidget(widgetId, views)
        return true
    }

    private fun fixedDetail(context: Context, row: HomeWidgetRow): String {
        if (row.kind == "section") {
            return context.getString(R.string.home_widget_table_count, row.count)
        }
        return row.detail.orEmpty()
    }

    private fun settingsPendingIntent(context: Context, widgetId: Int) =
        HomeWidgetNavigation.pendingIntent(
            context,
            HomeWidgetOpenTarget(kind = "settings", widgetId = widgetId),
        )

    private fun tablePendingIntent(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
    ) = HomeWidgetNavigation.pendingIntent(
        context,
        HomeWidgetOpenTarget(
            kind = "table",
            widgetId = widgetId,
            cardId = card.cardId,
            cardRevision = card.revision,
            tableId = row.tableId,
            rowHash = card.rowHash(row),
        ),
    )

    private fun entryPendingIntent(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
    ) = HomeWidgetNavigation.pendingIntent(
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
    )

    private fun stableRowId(
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
    ): Long {
        val key = listOf(
            widgetId.toString(),
            card.cardId,
            card.revision.toString(),
            row.kind,
            row.tableId,
            row.entryId.orEmpty(),
        ).joinToString("|")
        var hash = 1125899906842597L
        key.forEach { character ->
            hash = 31L * hash + character.code
        }
        return hash
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
                surface = R.drawable.home_widget_surface_dark,
                section = R.drawable.home_widget_section_dark,
                textPrimary = R.color.home_widget_text_primary_dark,
                textSecondary = R.color.home_widget_text_secondary_dark,
                accent = R.color.home_widget_accent_dark,
            )
        } else {
            Palette(
                background = R.drawable.home_widget_background_light,
                surface = R.drawable.home_widget_surface_light,
                section = R.drawable.home_widget_section_light,
                textPrimary = R.color.home_widget_text_primary_light,
                textSecondary = R.color.home_widget_text_secondary_light,
                accent = R.color.home_widget_accent_light,
            )
        }
    }
}
