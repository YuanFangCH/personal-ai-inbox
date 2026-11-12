package com.yuanfang.aitext.personal_ai_inbox

internal data class HomeWidgetPage(val index: Int, val rows: List<HomeWidgetRow>)

internal data class HomeWidgetPageRequest(
    val widgetId: Int,
    val cardId: String,
    val revision: Long,
    val generatedAtMs: Long,
    val pageIndex: Int,
)

internal object HomeWidgetPager {
    fun paginate(rows: List<HomeWidgetRow>, rowsPerPage: Int): List<HomeWidgetPage> {
        require(rowsPerPage > 0) { "rowsPerPage must be positive" }
        val entries = rows.filter { it.kind == "entry" }
        return entries.chunked(rowsPerPage).mapIndexed { index, chunk ->
            HomeWidgetPage(index, chunk)
        }
    }

    fun rowsPerPage(heightDp: Int, fontScale: Float): Int =
        ((heightDp - 64).coerceAtLeast(48) / (44 * fontScale.coerceAtLeast(1f)))
            .toInt().coerceAtLeast(1)
}
