package com.yuanfang.aitext.personal_ai_inbox

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class HomeWidgetConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        setContentView(buildContent())
    }

    private fun buildContent(): ScrollView {
        val density = resources.displayMetrics.density
        val padding = (24 * density).toInt()
        val gap = (10 * density).toInt()
        val cards = HomeWidgetSnapshotStore.load(this)
            ?.cards
            ?.filter { it.state == "ready" || it.state == "empty" }
            .orEmpty()
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        content.addView(
            TextView(this).apply {
                text = getString(R.string.home_widget_choose_card)
                textSize = 20f
                setTypeface(typeface, Typeface.BOLD)
            },
        )
        if (cards.isEmpty()) {
            content.addView(
                TextView(this).apply {
                    text = getString(R.string.home_widget_no_cards)
                    setPadding(0, gap, 0, gap)
                },
            )
        } else {
            cards.forEach { card ->
                content.addView(
                    Button(this).apply {
                        text = card.title
                        isAllCaps = false
                        gravity = Gravity.START or Gravity.CENTER_VERTICAL
                        setOnClickListener { choose(card.cardId) }
                    },
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        topMargin = gap
                    },
                )
            }
        }
        content.addView(
            Button(this).apply {
                text = getString(R.string.home_widget_cancel)
                isAllCaps = false
                setOnClickListener { finish() }
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = gap
            },
        )
        return ScrollView(this).apply { addView(content) }
    }

    private fun choose(cardId: String) {
        if (!HomeWidgetProvider.bind(this, widgetId, cardId)) {
            return
        }
        HomeWidgetProvider.render(this, widgetId)
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId),
        )
        finish()
    }
}
