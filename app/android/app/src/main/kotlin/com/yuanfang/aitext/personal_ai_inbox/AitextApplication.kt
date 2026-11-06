package com.yuanfang.aitext.personal_ai_inbox

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class AitextApplication : Application() {
    companion object {
        const val ENGINE_ID = "aitext-main-engine"

        fun from(context: android.content.Context): AitextApplication {
            return context.applicationContext as AitextApplication
        }
    }

    private var flutterEngine: FlutterEngine? = null
    lateinit var backgroundController: AgentBackgroundController
        private set

    override fun onCreate() {
        super.onCreate()
        markInterruptedTaskPaused()
    }

    @Synchronized
    fun getOrCreateFlutterEngine(): FlutterEngine {
        return flutterEngine ?: FlutterEngine(this).also { engine ->
            flutterEngine = engine
            backgroundController = AgentBackgroundController(this, engine)
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        }
    }

    override fun onTerminate() {
        AgentBackgroundController.invokeDart(
            "serviceStopped",
            mapOf(
                "state" to "paused",
                "message" to "应用进程已结束。",
                "code" to "process_terminated",
            ),
        )
        if (::backgroundController.isInitialized) {
            backgroundController.dispose()
        }
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        flutterEngine?.destroy()
        flutterEngine = null
        super.onTerminate()
    }

    private fun markInterruptedTaskPaused() {
        val preferences = getSharedPreferences("agent_background_state", MODE_PRIVATE)
        if (preferences.getString("active_state", null) == "running") {
            preferences.edit()
                .putString("active_state", "paused")
                .apply()
        }
    }
}
