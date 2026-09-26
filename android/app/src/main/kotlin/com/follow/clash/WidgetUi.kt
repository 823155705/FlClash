package com.follow.clash

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.widget.RemoteViews
import com.follow.clash.common.QuickAction
import com.follow.clash.common.quickIntent
import com.follow.clash.hyperos.HyperOsStyle
import java.util.Locale

/**
 * Shared RemoteViews binder for 2×2 and 4×2 widgets.
 * Layout ids differ, view ids are kept aligned across both templates.
 */
internal object WidgetUi {
    fun bind(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        layoutId: Int,
        chartBytes: ByteArray? = null,
    ) {
        val state = WidgetDataStore.getState(context)
        val views = RemoteViews(context.packageName, layoutId)
        val cn = Locale.getDefault().language == "zh"
        val isDarkMode = HyperOsStyle.isDark(context)

        if (isDarkMode) {
            views.setInt(android.R.id.background, "setBackgroundResource", R.drawable.widget_bg_dark)
            views.setInt(R.id.status_row, "setBackgroundResource", R.drawable.widget_ripple_dark)
            views.setInt(R.id.mode_row, "setBackgroundResource", R.drawable.widget_ripple_dark)
            views.setInt(R.id.node_row, "setBackgroundResource", R.drawable.widget_ripple_dark)
            views.setTextColor(R.id.status_text, Color.parseColor(HyperOsStyle.TEXT_PRIMARY_DARK))
            views.setTextColor(R.id.mode_text, Color.parseColor(HyperOsStyle.TEXT_PRIMARY_DARK))
            views.setTextColor(R.id.node_text, Color.parseColor(HyperOsStyle.TEXT_PRIMARY_DARK))
            views.setTextColor(R.id.mode_title, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_DARK))
            views.setTextColor(R.id.node_title, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_DARK))
            views.setTextColor(R.id.traffic_text, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_DARK))
            views.setTextColor(R.id.mode_chevron, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_DARK))
            views.setTextColor(R.id.node_chevron, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_DARK))
            views.setInt(R.id.divider1, "setBackgroundColor", Color.parseColor(HyperOsStyle.DIVIDER_DARK))
            views.setInt(R.id.divider2, "setBackgroundColor", Color.parseColor(HyperOsStyle.DIVIDER_DARK))
        } else {
            views.setTextColor(R.id.status_text, Color.parseColor(HyperOsStyle.TEXT_PRIMARY_LIGHT))
            views.setTextColor(R.id.mode_text, Color.parseColor(HyperOsStyle.TEXT_PRIMARY_LIGHT))
            views.setTextColor(R.id.node_text, Color.parseColor(HyperOsStyle.TEXT_PRIMARY_LIGHT))
            views.setTextColor(R.id.mode_title, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_LIGHT))
            views.setTextColor(R.id.node_title, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_LIGHT))
            views.setTextColor(R.id.traffic_text, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_LIGHT))
            views.setTextColor(R.id.mode_chevron, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_LIGHT))
            views.setTextColor(R.id.node_chevron, Color.parseColor(HyperOsStyle.TEXT_SECONDARY_LIGHT))
            views.setInt(R.id.divider1, "setBackgroundColor", Color.parseColor(HyperOsStyle.DIVIDER_LIGHT))
            views.setInt(R.id.divider2, "setBackgroundColor", Color.parseColor(HyperOsStyle.DIVIDER_LIGHT))
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
        views.setTextViewText(R.id.mode_title, if (cn) "模式" else "Mode")
        views.setTextViewText(R.id.mode_text, modeLabel)

        views.setTextViewText(R.id.node_title, if (cn) "节点" else "Node")
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
        val togglePendingIntent = android.app.PendingIntent.getActivity(
            context,
            0,
            toggleIntent,
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(R.id.status_row, togglePendingIntent)
        views.setOnClickPendingIntent(R.id.toggle_button, togglePendingIntent)

        val modeIntent = android.content.Intent(context, WidgetProvider::class.java).apply {
            action = WidgetProvider.actionCycleMode(context)
        }
        val modePendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            1,
            modeIntent,
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(R.id.mode_row, modePendingIntent)

        val nodeIntent = QuickAction.SELECT_PROXY.quickIntent
        val nodePendingIntent = android.app.PendingIntent.getActivity(
            context,
            3,
            nodeIntent,
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(R.id.node_row, nodePendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun formatSpeed(bytes: Number): String {
        val b = bytes.toDouble()
        return when {
            b >= 1_000_000 -> String.format("%.1f MB/s", b / 1_000_000)
            b >= 1_000 -> String.format("%.1f KB/s", b / 1_000)
            else -> String.format("%.0f B/s", b)
        }
    }

    fun providerComponents(context: Context): List<ComponentName> = listOf(
        ComponentName(context, WidgetProvider::class.java),
        ComponentName(context, WidgetProviderWide::class.java),
    )
}
