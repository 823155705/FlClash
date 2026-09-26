package com.follow.clash

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.widget.RemoteViews
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.QuickAction
import com.follow.clash.common.intent
import com.follow.clash.common.quickIntent
import com.google.gson.Gson
import kotlinx.coroutines.launch
import java.util.Locale

data class WidgetState(
    val isStart: Boolean = false,
    val mode: String = "rule",
    val groupName: String = "",
    val nodeName: String = "",
    val upSpeed: Number = 0,
    val downSpeed: Number = 0,
    val proxyNames: String = "",
)

object WidgetDataStore {
    private const val PREFS_NAME = "widget_prefs"
    private const val KEY_STATE = "widget_state"
    private const val KEY_LAST_UPDATE = "widget_last_update"
    private const val STALE_TIMEOUT_MS = 300_000L
    private val gson = Gson()

    fun getState(context: Context): WidgetState {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lastUpdate = prefs.getLong(KEY_LAST_UPDATE, 0)
        if (System.currentTimeMillis() - lastUpdate > STALE_TIMEOUT_MS) {
            return WidgetState()
        }
        val json = prefs.getString(KEY_STATE, null) ?: return WidgetState()
        return try {
            gson.fromJson(json, WidgetState::class.java)
        } catch (_: Exception) {
            WidgetState()
        }
    }

    fun saveState(context: Context, state: WidgetState) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_STATE, gson.toJson(state))
            .putLong(KEY_LAST_UPDATE, System.currentTimeMillis())
            .apply()
    }

    fun saveStateAsync(context: Context, state: WidgetState) {
        GlobalState.launch {
            saveState(context, state)
        }
    }
}

object WidgetRefresher {
    fun updateRunning(context: Context, isStart: Boolean) {
        val current = WidgetDataStore.getState(context)
        if (current.isStart == isStart) return
        WidgetDataStore.saveState(context, current.copy(isStart = isStart))
        refreshAll(context)
    }

    fun refreshAll(context: Context, chartBytes: ByteArray? = null) {
        // OEM-first: HyperOS/MIUI launcher channel, then standard AppWidgetManager.
        com.follow.clash.hyperos.HyperOsMiuiBridge.refreshWidgets(context, chartBytes)
        com.follow.clash.hyperos.HyperOsBootstrap.onWidgetStateChanged(context)
    }
}

class WidgetProvider : AppWidgetProvider() {

    companion object {
        fun actionCycleMode(context: Context): String =
            "${context.packageName}.action.CYCLE_MODE"

        fun actionCycleNode(context: Context): String =
            "${context.packageName}.action.CYCLE_NODE"

        fun actionSelectProxy(context: Context): String =
            "${context.packageName}.action.SELECT_PROXY"

        private fun isChinese(): Boolean {
            return Locale.getDefault().language == "zh"
        }

        private fun formatSpeed(bytes: Number): String {
            val b = bytes.toDouble()
            return when {
                b >= 1_000_000 -> String.format("%.1f MB/s", b / 1_000_000)
                b >= 1_000 -> String.format("%.1f KB/s", b / 1_000)
                else -> String.format("%.0f B/s", b)
            }
        }

        fun buildModeIntent(context: Context): Intent {
            val intent = Intent(context, WidgetProvider::class.java)
            intent.action = actionCycleMode(context)
            return intent
        }

        fun buildNodeIntent(context: Context): Intent {
            return QuickAction.SELECT_PROXY.quickIntent
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            chartBytes: ByteArray? = null,
        ) {
            val state = WidgetDataStore.getState(context)
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            val cn = isChinese()

            val isDarkMode = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            if (isDarkMode) {
                views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_bg_dark)
                views.setInt(R.id.status_row, "setBackgroundResource", R.drawable.widget_ripple_dark)
                views.setInt(R.id.mode_row, "setBackgroundResource", R.drawable.widget_ripple_dark)
                views.setInt(R.id.node_row, "setBackgroundResource", R.drawable.widget_ripple_dark)
                views.setTextColor(R.id.status_text, Color.parseColor("#FFE0E0E0"))
                views.setTextColor(R.id.mode_text, Color.parseColor("#FFE0E0E0"))
                views.setTextColor(R.id.node_text, Color.parseColor("#FFE0E0E0"))
                views.setTextColor(R.id.mode_title, Color.parseColor("#8AFFFFFF"))
                views.setTextColor(R.id.node_title, Color.parseColor("#8AFFFFFF"))
                views.setTextColor(R.id.traffic_text, Color.parseColor("#8AFFFFFF"))
                views.setTextColor(R.id.mode_chevron, Color.parseColor("#8AFFFFFF"))
                views.setTextColor(R.id.node_chevron, Color.parseColor("#8AFFFFFF"))
                views.setInt(R.id.divider1, "setBackgroundColor", Color.parseColor("#1AFFFFFF"))
                views.setInt(R.id.divider2, "setBackgroundColor", Color.parseColor("#1AFFFFFF"))
            } else {
                views.setTextColor(R.id.status_text, Color.BLACK)
                views.setTextColor(R.id.mode_text, Color.BLACK)
                views.setTextColor(R.id.node_text, Color.BLACK)
                views.setTextColor(R.id.mode_title, Color.parseColor("#8A000000"))
                views.setTextColor(R.id.node_title, Color.parseColor("#8A000000"))
                views.setTextColor(R.id.traffic_text, Color.parseColor("#8A000000"))
                views.setTextColor(R.id.mode_chevron, Color.parseColor("#8A000000"))
                views.setTextColor(R.id.node_chevron, Color.parseColor("#8A000000"))
                views.setInt(R.id.divider1, "setBackgroundColor", Color.parseColor("#1A000000"))
                views.setInt(R.id.divider2, "setBackgroundColor", Color.parseColor("#1A000000"))
            }

            val statusText = if (state.isStart) {
                if (cn) "运行中" else "Running"
            } else {
                if (cn) "已停止" else "Stopped"
            }
            views.setTextViewText(R.id.status_text, statusText)
            views.setInt(
                R.id.status_icon,
                "setBackgroundResource",
                if (state.isStart) R.drawable.status_dot else R.drawable.status_dot_stopped,
            )

            val powerIcon =
                if (state.isStart) R.drawable.ic_power_active else R.drawable.ic_power_inactive
            views.setImageViewResource(R.id.toggle_button, powerIcon)

            val downText = "↓ ${formatSpeed(state.downSpeed)}"
            val upText = "↑ ${formatSpeed(state.upSpeed)}"
            views.setTextViewText(R.id.traffic_text, "$downText  $upText")
            if (chartBytes != null) {
                val bitmap = BitmapFactory.decodeByteArray(chartBytes, 0, chartBytes.size)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.traffic_chart, bitmap)
                }
            }

            val modeLabel = when (state.mode.lowercase(Locale.ROOT)) {
                "rule" -> if (cn) "规则" else "Rule"
                "global" -> if (cn) "全局" else "Global"
                "direct" -> if (cn) "直连" else "Direct"
                else -> state.mode.replaceFirstChar { it.uppercase() }
            }
            val modeTitle = if (cn) "模式" else "Mode"
            views.setTextViewText(R.id.mode_title, modeTitle)
            views.setTextViewText(R.id.mode_text, modeLabel)

            val nodeTitle = if (cn) "节点" else "Node"
            views.setTextViewText(R.id.node_title, nodeTitle)
            val nodeLabel = if (state.nodeName.isNotEmpty()) {
                state.nodeName
            } else {
                if (cn) "自动" else "Auto"
            }
            views.setTextViewText(R.id.node_text, nodeLabel)

            val toggleIntent = if (state.isStart) {
                QuickAction.STOP.quickIntent
            } else {
                QuickAction.START.quickIntent
            }
            val togglePendingIntent = PendingIntent.getActivity(
                context,
                0,
                toggleIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.status_row, togglePendingIntent)
            views.setOnClickPendingIntent(R.id.toggle_button, togglePendingIntent)

            val modeIntent = buildModeIntent(context)
            val modePendingIntent = PendingIntent.getBroadcast(
                context,
                1,
                modeIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.mode_row, modePendingIntent)

            val nodeIntent = buildNodeIntent(context)
            val nodePendingIntent = PendingIntent.getActivity(
                context,
                3,
                nodeIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.node_row, nodePendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        // HyperOS exposure refresh sends miui.appwidget.action.APPWIDGET_UPDATE
        if (action == "miui.appwidget.action.APPWIDGET_UPDATE") {
            val am = AppWidgetManager.getInstance(context)
            val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                ?: am.getAppWidgetIds(ComponentName(context, WidgetProvider::class.java))
            onUpdate(context, am, ids)
            return
        }
        super.onReceive(context, intent)
        when (action) {
            actionCycleMode(context) -> handleCycleMode(context)
            actionCycleNode(context) -> handleCycleNode(context)
            actionSelectProxy(context) -> {
                val proxyName = intent.getStringExtra("selectedProxy") ?: return
                handleSelectProxy(context, proxyName)
            }
        }
    }

    private fun handleCycleMode(context: Context) {
        val plugin = ServiceState.widgetPlugin()
        if (plugin != null) {
            plugin.handleCycleMode()
        } else {
            openMain(context)
        }
    }

    private fun handleCycleNode(context: Context) {
        val plugin = ServiceState.widgetPlugin()
        if (plugin != null) {
            plugin.handleCycleNode()
        } else {
            openMain(context)
        }
    }

    private fun handleSelectProxy(context: Context, proxyName: String) {
        val plugin = ServiceState.widgetPlugin()
        if (plugin != null) {
            plugin.handleSelectProxy(proxyName)
        } else {
            openMain(context)
        }
    }

    private fun openMain(context: Context) {
        val intent = Components.mainActivity.intent.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(intent)
    }
}
