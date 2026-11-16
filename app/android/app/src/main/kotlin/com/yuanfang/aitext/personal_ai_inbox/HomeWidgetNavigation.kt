package com.yuanfang.aitext.personal_ai_inbox

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log

internal data class HomeWidgetOpenTarget(
    val kind: String,
    val widgetId: Int,
    val cardId: String? = null,
    val cardRevision: Long? = null,
    val tableId: String? = null,
    val entryId: String? = null,
    val rowHash: String? = null,
    val generatedAtMs: Long? = null,
    val pageIndex: Int? = null,
) {
    fun toMap(): Map<String, Any> = buildMap {
        put("kind", kind)
        tableId?.let { put("table_id", it) }
        entryId?.let { put("entry_id", it) }
    }
}

internal object HomeWidgetOpenQueue {
    private val lock = Any()
    private val pending = ArrayDeque<HomeWidgetOpenTarget>()

    fun offer(target: HomeWidgetOpenTarget) {
        synchronized(lock) {
            pending.addLast(target)
        }
    }

    fun take(): HomeWidgetOpenTarget? = synchronized(lock) {
        if (pending.isEmpty()) null else pending.removeFirst()
    }

    fun hasPending(): Boolean = synchronized(lock) {
        pending.isNotEmpty()
    }
}

internal object HomeWidgetNavigation {
    const val ACTION_OPEN_TARGET =
        "com.yuanfang.aitext.personal_ai_inbox.action.OPEN_HOME_WIDGET_TARGET"

    private const val EXTRA_KIND = "home_widget_kind"
    private const val EXTRA_WIDGET_ID = "home_widget_widget_id"
    private const val EXTRA_CARD_ID = "home_widget_card_id"
    private const val EXTRA_CARD_REVISION = "home_widget_card_revision"
    private const val EXTRA_TABLE_ID = "home_widget_table_id"
    private const val EXTRA_ENTRY_ID = "home_widget_entry_id"
    private const val EXTRA_ROW_HASH = "home_widget_row_hash"
    private const val EXTRA_GENERATED_AT = "home_widget_generated_at"
    private const val EXTRA_PAGE_INDEX = "home_widget_page_index"

    fun targetIntent(context: Context, target: HomeWidgetOpenTarget): Intent {
        val data = Uri.Builder()
            .scheme("aitext-widget")
            .authority(target.kind)
            .appendQueryParameter("widget_id", target.widgetId.toString())
            .appendQueryParameter("card_id", target.cardId.orEmpty())
            .appendQueryParameter("revision", target.cardRevision?.toString().orEmpty())
            .appendQueryParameter("table_id", target.tableId.orEmpty())
            .appendQueryParameter("entry_id", target.entryId.orEmpty())
            .appendQueryParameter("row_hash", target.rowHash.orEmpty())
            .appendQueryParameter("generated_at", target.generatedAtMs?.toString().orEmpty())
            .appendQueryParameter("page_index", target.pageIndex?.toString().orEmpty())
            .build()
        return Intent(context, HomeWidgetOpenActivity::class.java)
            .setAction(ACTION_OPEN_TARGET)
            .setData(data)
            .putExtra(EXTRA_KIND, target.kind)
            .putExtra(EXTRA_WIDGET_ID, target.widgetId)
            .apply {
                target.cardId?.let { putExtra(EXTRA_CARD_ID, it) }
                target.cardRevision?.let { putExtra(EXTRA_CARD_REVISION, it) }
                target.tableId?.let { putExtra(EXTRA_TABLE_ID, it) }
                target.entryId?.let { putExtra(EXTRA_ENTRY_ID, it) }
                target.rowHash?.let { putExtra(EXTRA_ROW_HASH, it) }
                target.generatedAtMs?.let { putExtra(EXTRA_GENERATED_AT, it) }
                target.pageIndex?.let { putExtra(EXTRA_PAGE_INDEX, it) }
            }
    }

    fun mainActivityIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    fun pendingIntent(
        context: Context,
        target: HomeWidgetOpenTarget,
    ): PendingIntent {
        val intent = targetIntent(context, target)
        val requestCode = listOf(
            target.widgetId,
            target.kind,
            target.cardId.orEmpty(),
            target.cardRevision?.toString().orEmpty(),
            target.tableId.orEmpty(),
            target.entryId.orEmpty(),
            target.rowHash.orEmpty(),
        ).joinToString("|").hashCode()
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun pendingIntentTemplate(
        context: Context,
        widgetId: Int,
    ): PendingIntent {
        val intent = Intent(context, HomeWidgetOpenActivity::class.java)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getActivity(
            context,
            0x48470000 xor widgetId,
            intent,
            flags,
        )
    }

    fun pagePendingIntent(context: Context, target: HomeWidgetOpenTarget): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            target.widgetId xor (target.pageIndex ?: 0),
            Intent(context, HomeWidgetClickReceiver::class.java)
                .setAction(ACTION_OPEN_TARGET)
                .setData(targetIntent(context, target).data)
                .putExtras(fillInIntent(context, target)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun fillInIntent(
        context: Context,
        target: HomeWidgetOpenTarget,
    ): Intent =
        Intent()
            .setAction(ACTION_OPEN_TARGET)
            .setData(targetIntent(context, target).data)
            .apply {
                target.cardId?.let { putExtra(EXTRA_CARD_ID, it) }
                target.cardRevision?.let { putExtra(EXTRA_CARD_REVISION, it) }
                target.tableId?.let { putExtra(EXTRA_TABLE_ID, it) }
                target.entryId?.let { putExtra(EXTRA_ENTRY_ID, it) }
                target.rowHash?.let { putExtra(EXTRA_ROW_HASH, it) }
                putExtra(EXTRA_KIND, target.kind)
                putExtra(EXTRA_WIDGET_ID, target.widgetId)
                target.generatedAtMs?.let { putExtra(EXTRA_GENERATED_AT, it) }
                target.pageIndex?.let { putExtra(EXTRA_PAGE_INDEX, it) }
            }

    fun openQueuedTarget(context: Context, target: HomeWidgetOpenTarget) {
        HomeWidgetOpenQueue.offer(target)
        context.startActivity(
            mainActivityIntent(context)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun fromOpenActivityIntent(intent: Intent?): HomeWidgetOpenTarget? {
        if (intent?.action != ACTION_OPEN_TARGET) {
            return null
        }
        return readTarget(intent)
    }

    fun validate(context: Context, target: HomeWidgetOpenTarget): Boolean {
        if (target.widgetId <= 0 || target.kind !in setOf("settings", "table", "entry", "page")) {
            return false
        }
        val manager = AppWidgetManager.getInstance(context)
        val provider = ComponentName(context, HomeWidgetProvider::class.java)
        if (manager.getAppWidgetInfo(target.widgetId)?.provider != provider) {
            return false
        }
        if (target.kind == "settings") {
            return true
        }
        val cardId = target.cardId ?: return false
        val revision = target.cardRevision ?: return false
        if (HomeWidgetSnapshotStore.boundCardId(context, target.widgetId) != cardId) {
            return false
        }
        val card = HomeWidgetSnapshotStore.load(context)?.card(cardId) ?: return false
        if (card.revision != revision) {
            return false
        }
        if (target.kind == "page") {
            val generatedAt = target.generatedAtMs ?: return false
            val pageIndex = target.pageIndex ?: return false
            if (card.generatedAtMs != generatedAt) return false
            val options = manager.getAppWidgetOptions(target.widgetId)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 220)
            val pageCount = HomeWidgetPager.paginate(
                card.rows,
                HomeWidgetRenderer.rowsPerPage(
                    height,
                    context.resources.configuration.fontScale,
                    android.os.Build.VERSION.SDK_INT,
                ),
            ).size
            return pageIndex in 0 until pageCount
        }
        val tableId = target.tableId ?: return false
        val row = when (target.kind) {
            "table" -> card.rows.firstOrNull {
                it.kind == "section" && it.tableId == tableId
            }

            "entry" -> card.rows.firstOrNull {
                it.kind == "entry" &&
                    it.tableId == tableId &&
                    it.entryId == target.entryId
            }

            else -> null
        } ?: return false
        return target.rowHash == card.rowHash(row)
    }

    fun handleCollectionClick(context: Context, intent: Intent) {
        val target = fromOpenActivityIntent(intent)
        if (target?.kind == "page") {
            HomeWidgetRenderer.showPage(
                context,
                AppWidgetManager.getInstance(context),
                HomeWidgetPageRequest(
                    target.widgetId,
                    target.cardId ?: return,
                    target.cardRevision ?: return,
                    target.generatedAtMs ?: return,
                    target.pageIndex ?: return,
                ),
            )
            return
        }
        if (target == null || !validate(context, target)) {
            return
        }
        Log.d(
            "HomeWidgetNavigation",
            "Launching widget target ${target.kind} widget=${target.widgetId}",
        )
        openQueuedTarget(context, target)
    }

    private fun readTarget(intent: Intent): HomeWidgetOpenTarget? {
        val kind = intent.getStringExtra(EXTRA_KIND) ?: return null
        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, -1)
        if (widgetId <= 0) {
            return null
        }
        val revision = if (intent.hasExtra(EXTRA_CARD_REVISION)) {
            intent.getLongExtra(EXTRA_CARD_REVISION, 0L).takeIf { it > 0L }
        } else {
            null
        }
        return HomeWidgetOpenTarget(
            kind = kind,
            widgetId = widgetId,
            cardId = intent.getStringExtra(EXTRA_CARD_ID),
            cardRevision = revision,
            tableId = intent.getStringExtra(EXTRA_TABLE_ID),
            entryId = intent.getStringExtra(EXTRA_ENTRY_ID),
            rowHash = intent.getStringExtra(EXTRA_ROW_HASH),
            generatedAtMs = intent.takeIf { it.hasExtra(EXTRA_GENERATED_AT) }
                ?.getLongExtra(EXTRA_GENERATED_AT, 0L),
            pageIndex = intent.takeIf { it.hasExtra(EXTRA_PAGE_INDEX) }
                ?.getIntExtra(EXTRA_PAGE_INDEX, -1),
        )
    }
}
