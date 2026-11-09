package com.yuanfang.aitext.personal_ai_inbox

import android.content.Context
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets

internal data class HomeWidgetRow(
    val kind: String,
    val tableId: String,
    val entryId: String?,
    val title: String,
    val detail: String?,
    val count: Int,
)

internal data class HomeWidgetCard(
    val cardId: String,
    val revision: Long,
    val title: String,
    val theme: String,
    val state: String,
    val generatedAtMs: Long,
    val dataDay: String,
    val rows: List<HomeWidgetRow>,
    val hasMore: Boolean,
) {
    fun rowHash(row: HomeWidgetRow): String {
        val key = listOf(
            cardId,
            revision.toString(),
            row.kind,
            row.tableId,
            row.entryId.orEmpty(),
        ).joinToString("|")
        return Integer.toHexString(key.hashCode())
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("card_id", cardId)
        put("revision", revision)
        put("title", title)
        put("theme", theme)
        put("state", state)
        put("generated_at_ms", generatedAtMs)
        put("data_day", dataDay)
        put("has_more", hasMore)
        put(
            "rows",
            JSONArray().apply {
                rows.forEach { row ->
                    put(
                        JSONObject().apply {
                            put("kind", row.kind)
                            put("table_id", row.tableId)
                            if (row.entryId != null) {
                                put("entry_id", row.entryId)
                            }
                            put("title", row.title)
                            if (row.detail != null) {
                                put("detail", row.detail)
                            }
                            if (row.kind == "section") {
                                put("count", row.count)
                            }
                        },
                    )
                }
            },
        )
    }
}

internal data class HomeWidgetSnapshot(
    val cards: List<HomeWidgetCard>,
) {
    fun card(cardId: String?): HomeWidgetCard? =
        cardId?.let { id -> cards.firstOrNull { it.cardId == id } }

    fun toJson(): JSONObject = JSONObject().apply {
        put("schema_version", 1)
        put(
            "cards",
            JSONArray().apply {
                cards.forEach { put(it.toJson()) }
            },
        )
    }
}

internal data class HomeWidgetPublishResult(
    val cardCount: Int,
)

internal object HomeWidgetSnapshotStore {
    private const val SNAPSHOT_FILE = "snapshot.json"
    private const val BINDINGS_FILE = "bindings.json"
    private const val MAX_PACKAGE_BYTES = 512 * 1024
    private const val MAX_ROWS_PER_CARD = 48
    private const val MAX_ID_LENGTH = 512
    private const val MAX_TITLE_LENGTH = 160
    private const val MAX_DETAIL_LENGTH = 240
    private const val MAX_DATE_LENGTH = 32
    private val themes = setOf("system", "light", "dark")
    private val states = setOf("ready", "empty", "blocked", "error", "archived")

    private val lock = Any()

    fun directory(context: Context): File =
        File(context.noBackupFilesDir, "home_widgets").apply { mkdirs() }

    fun publish(context: Context, snapshotJson: String): HomeWidgetPublishResult =
        synchronized(lock) {
            val snapshot = parseSnapshot(snapshotJson)
            atomicWrite(
                AtomicFile(File(directory(context), SNAPSHOT_FILE)),
                snapshot.toJson().toString(),
            )
            HomeWidgetPublishResult(snapshot.cards.size)
        }

    fun load(context: Context): HomeWidgetSnapshot? = synchronized(lock) {
        val file = AtomicFile(File(directory(context), SNAPSHOT_FILE))
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) {
            return@synchronized null
        }
        runCatching {
            parseSnapshot(String(file.readFully(), StandardCharsets.UTF_8))
        }.getOrNull()
    }

    fun clear(context: Context) {
        synchronized(lock) {
            AtomicFile(File(directory(context), SNAPSHOT_FILE)).delete()
        }
    }

    fun bindings(context: Context): Map<Int, String> = synchronized(lock) {
        readBindings(context)
    }

    fun boundCardId(context: Context, widgetId: Int): String? =
        bindings(context)[widgetId]

    fun bind(context: Context, widgetId: Int, cardId: String): Boolean =
        synchronized(lock) {
            val snapshot = load(context) ?: return@synchronized false
            if (snapshot.card(cardId) == null) {
                return@synchronized false
            }
            val next = readBindings(context).toMutableMap().apply {
                put(widgetId, cardId)
            }
            writeBindings(context, next)
            true
        }

    fun removeBindings(context: Context, widgetIds: IntArray) {
        synchronized(lock) {
            val next = readBindings(context).toMutableMap().apply {
                widgetIds.forEach { remove(it) }
            }
            writeBindings(context, next)
        }
    }

    fun removeBinding(context: Context, widgetId: Int) {
        removeBindings(context, intArrayOf(widgetId))
    }

    fun clearBindings(context: Context) {
        synchronized(lock) {
            AtomicFile(File(directory(context), BINDINGS_FILE)).delete()
        }
    }

    private fun parseSnapshot(raw: String): HomeWidgetSnapshot {
        val bytes = raw.toByteArray(StandardCharsets.UTF_8)
        require(bytes.size <= MAX_PACKAGE_BYTES) { "Snapshot package exceeds 512 KiB" }
        val root = JSONObject(raw)
        require(root.optInt("schema_version", -1) == 1) {
            "Unsupported widget snapshot schema"
        }
        val cardsJson = root.getJSONArray("cards")
        val cards = buildList {
            for (index in 0 until cardsJson.length()) {
                add(parseCard(cardsJson.getJSONObject(index)))
            }
        }
        require(cards.map { it.cardId }.toSet().size == cards.size) {
            "Duplicate widget card IDs"
        }
        return HomeWidgetSnapshot(cards)
    }

    private fun parseCard(value: JSONObject): HomeWidgetCard {
        val rowsJson = value.getJSONArray("rows")
        require(rowsJson.length() <= MAX_ROWS_PER_CARD) {
            "Widget card exceeds 48 rows"
        }
        val rows = buildList {
            for (index in 0 until rowsJson.length()) {
                add(parseRow(rowsJson.getJSONObject(index)))
            }
        }
        val theme = value.optString("theme", "system")
        require(theme in themes) { "Unknown widget theme" }
        val state = value.optString("state", "ready")
        require(state in states) { "Unknown widget state" }
        return HomeWidgetCard(
            cardId = requiredId(value, "card_id"),
            revision = value.optLong("revision", 0L).also {
                require(it >= 1L) { "Widget revision must be positive" }
            },
            title = displayText(value, "title", MAX_TITLE_LENGTH).ifBlank {
                "懒狗秘书"
            },
            theme = theme,
            state = state,
            generatedAtMs = value.optLong("generated_at_ms", 0L).coerceAtLeast(0L),
            dataDay = displayText(value, "data_day", MAX_DATE_LENGTH),
            rows = rows,
            hasMore = value.optBoolean("has_more", false),
        )
    }

    private fun parseRow(value: JSONObject): HomeWidgetRow {
        val kind = value.optString("kind")
        require(kind == "section" || kind == "entry") { "Unknown widget row kind" }
        val tableId = requiredId(value, "table_id")
        return when (kind) {
            "section" -> HomeWidgetRow(
                kind = kind,
                tableId = tableId,
                entryId = null,
                title = displayText(value, "title", MAX_TITLE_LENGTH).ifBlank { "未命名表" },
                detail = null,
                count = value.optInt("count", 0).coerceAtLeast(0),
            )

            else -> HomeWidgetRow(
                kind = kind,
                tableId = tableId,
                entryId = requiredId(value, "entry_id"),
                title = displayText(value, "title", MAX_TITLE_LENGTH).ifBlank { "未命名条目" },
                detail = displayText(value, "detail", MAX_DETAIL_LENGTH).ifBlank { null },
                count = 0,
            )
        }
    }

    private fun requiredId(value: JSONObject, key: String): String {
        val result = value.optString(key).trim()
        require(result.isNotEmpty() && result.length <= MAX_ID_LENGTH) {
            "Invalid widget id: $key"
        }
        return result
    }

    private fun displayText(value: JSONObject, key: String, maxLength: Int): String {
        return value.optString(key)
            .replace(Regex("[\\u0000-\\u001F\\u007F]"), " ")
            .trim()
            .take(maxLength)
    }

    private fun readBindings(context: Context): Map<Int, String> {
        val file = AtomicFile(File(directory(context), BINDINGS_FILE))
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) {
            return emptyMap()
        }
        return runCatching {
            val root = JSONObject(String(file.readFully(), StandardCharsets.UTF_8))
            if (root.optInt("schema_version", 0) != 1) {
                return@runCatching emptyMap()
            }
            val values = root.optJSONObject("bindings") ?: return@runCatching emptyMap()
            buildMap {
                val keys = values.keys()
                while (keys.hasNext()) {
                    val widgetId = keys.next().toIntOrNull() ?: continue
                    val cardId = values.optString(widgetId.toString()).trim()
                    if (widgetId > 0 && cardId.isNotEmpty()) {
                        put(widgetId, cardId)
                    }
                }
            }
        }.getOrDefault(emptyMap())
    }

    private fun writeBindings(context: Context, values: Map<Int, String>) {
        val bindings = JSONObject()
        values.toSortedMap().forEach { (widgetId, cardId) ->
            bindings.put(widgetId.toString(), cardId)
        }
        val root = JSONObject().apply {
            put("schema_version", 1)
            put("bindings", bindings)
        }
        atomicWrite(AtomicFile(File(directory(context), BINDINGS_FILE)), root.toString())
    }

    private fun atomicWrite(file: AtomicFile, value: String) {
        val output = file.startWrite()
        try {
            output.write(value.toByteArray(StandardCharsets.UTF_8))
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }
}
