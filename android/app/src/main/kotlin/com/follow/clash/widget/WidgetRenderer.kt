package com.follow.clash.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import com.follow.clash.R
import com.follow.clash.RunState
import com.follow.clash.common.Components
import com.follow.clash.common.QuickAction
import com.follow.clash.common.intent
import com.follow.clash.common.quickIntent
import com.follow.clash.models.WidgetPendingAction
import com.follow.clash.models.WidgetSnapshot
import com.follow.clash.service.models.Traffic
import java.util.Locale

internal enum class WidgetKind(val layoutId: Int) {
    COMPACT_2X2(R.layout.widget_layout_2x2),
    WIDE_4X2(R.layout.widget_layout_4x2),
    BAR_4X1(R.layout.widget_layout_4x1),
}

internal enum class WidgetVisualStatus {
    NO_PROFILE,
    STOPPED,
    STARTING,
    STARTED,
    STOPPING,
    SUSPENDED,
}

internal data class WidgetDisplayModel(
    val status: WidgetVisualStatus,
    val statusLabel: String,
    val modeKey: String,
    val modeLabel: String,
    val groupLabel: String,
    val nodeLabel: String,
    val canSelectProxy: Boolean,
    val showTunBadge: Boolean,
    val primaryLine: String,
    val secondaryLine: String,
)

internal object WidgetDisplayReducer {
    fun deriveStatus(
        runState: RunState,
        snapshot: WidgetSnapshot,
    ): WidgetVisualStatus = when (runState) {
        RunState.STARTING -> WidgetVisualStatus.STARTING
        RunState.STOPPING -> WidgetVisualStatus.STOPPING
        RunState.STARTED -> WidgetVisualStatus.STARTED
        RunState.STOPPED -> when {
            snapshot.suspended -> WidgetVisualStatus.SUSPENDED
            !snapshot.hasProfile -> WidgetVisualStatus.NO_PROFILE
            else -> WidgetVisualStatus.STOPPED
        }
    }

    fun formatSpeed(bytesPerSecond: Long): String {
        val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s", "TB/s")
        var value = bytesPerSecond.coerceAtLeast(0L).toDouble()
        var unit = 0
        while (value >= 1024.0 && unit < units.lastIndex) {
            value /= 1024.0
            unit++
        }
        return if (unit == 0) {
            "${value.toLong()} ${units[unit]}"
        } else {
            String.format(Locale.ROOT, "%.1f %s", value, units[unit])
        }
    }

    fun reduce(
        kind: WidgetKind,
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        fallbackLabel: (String) -> String,
    ): WidgetDisplayModel {
        val status = deriveStatus(runState, snapshot)
        fun label(key: String): String =
            snapshot.labels[key]?.takeIf { it.isNotBlank() } ?: fallbackLabel(key)

        val statusLabel = when (status) {
            WidgetVisualStatus.STARTED -> label("running")
            WidgetVisualStatus.STARTING -> label("connecting")
            WidgetVisualStatus.STOPPING -> label("stopping")
            WidgetVisualStatus.SUSPENDED -> label("suspended")
            WidgetVisualStatus.NO_PROFILE -> label("noProfile")
            WidgetVisualStatus.STOPPED -> label("notRunning")
        }

        val modeKey = when (snapshot.mode.lowercase(Locale.ROOT)) {
            "global" -> "global"
            "direct" -> "direct"
            else -> "rule"
        }
        val modeLabel = when (modeKey) {
            "global" -> label("modeGlobal")
            "direct" -> label("modeDirect")
            else -> label("modeRule")
        }

        val canSelect = status != WidgetVisualStatus.NO_PROFILE &&
            modeKey != "direct" &&
            snapshot.canSelectProxy &&
            snapshot.proxyNames.isNotEmpty()

        val nodeLabel = when {
            status == WidgetVisualStatus.NO_PROFILE -> label("noProfile")
            modeKey == "direct" -> label("direct")
            snapshot.nodeName.isNotBlank() -> snapshot.nodeName
            snapshot.profileName.isNotBlank() -> snapshot.profileName
            else -> modeLabel
        }

        val groupLabel = when {
            status == WidgetVisualStatus.NO_PROFILE -> label("openApp")
            modeKey == "direct" -> modeLabel
            snapshot.groupName.isNotBlank() -> snapshot.groupName
            else -> modeLabel
        }

        val primaryLine: String
        val secondaryLine: String
        if (status == WidgetVisualStatus.STARTED) {
            val down = "↓ ${formatSpeed(traffic.down)}"
            val up = "↑ ${formatSpeed(traffic.up)}"
            primaryLine = if (kind == WidgetKind.BAR_4X1) "$down  $up" else down
            secondaryLine = up
        } else {
            val profile = snapshot.profileName.trim()
            primaryLine = when (status) {
                WidgetVisualStatus.NO_PROFILE -> label("noProfile")
                WidgetVisualStatus.STARTING -> label("connecting")
                WidgetVisualStatus.STOPPING -> label("stopping")
                WidgetVisualStatus.SUSPENDED -> label("suspended")
                WidgetVisualStatus.STOPPED -> profile.ifBlank { label("tapToStart") }
                WidgetVisualStatus.STARTED -> ""
            }
            secondaryLine = when (status) {
                WidgetVisualStatus.NO_PROFILE -> label("openApp")
                WidgetVisualStatus.STOPPED -> if (profile.isNotBlank()) label("tapToStart") else ""
                else -> profile
            }
        }

        return WidgetDisplayModel(
            status = status,
            statusLabel = statusLabel,
            modeKey = modeKey,
            modeLabel = modeLabel,
            groupLabel = groupLabel,
            nodeLabel = nodeLabel,
            canSelectProxy = canSelect,
            showTunBadge = status == WidgetVisualStatus.STARTED && snapshot.tunEnabled,
            primaryLine = primaryLine,
            secondaryLine = secondaryLine,
        )
    }
}

internal object WidgetRenderer {
    private const val REQUEST_OPEN_APP = 100
    private const val REQUEST_TOGGLE = 101
    private const val REQUEST_CYCLE_MODE = 102
    private const val REQUEST_SELECT_PROXY = 103

    fun bind(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
        kind: WidgetKind,
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
    ) {
        if (widgetIds.isEmpty()) return
        val isDark = isDarkMode(context)
        val model = WidgetDisplayReducer.reduce(
            kind = kind,
            runState = runState,
            snapshot = snapshot,
            traffic = traffic,
        ) { key -> fallbackString(context, key) }

        val customPrimary = if (isDark) snapshot.primaryColorDark else snapshot.primaryColorLight
        val effectivePrimary = if (customPrimary != 0) {
            customPrimary
        } else {
            ContextCompat.getColor(context, R.color.widget_primary)
        }
        val chartBitmap = if (kind == WidgetKind.WIDE_4X2 && model.status == WidgetVisualStatus.STARTED) {
            val downColor = if (customPrimary != 0) {
                customPrimary
            } else {
                ContextCompat.getColor(context, R.color.widget_chart_down)
            }
            val upColor = ContextCompat.getColor(context, R.color.widget_chart_up)
            WidgetChartRenderer.render(history, downColor, upColor, isDark)
        } else {
            null
        }

        try {
            val views = buildRemoteViews(
                context = context,
                kind = kind,
                snapshot = snapshot,
                model = model,
                isDark = isDark,
                customPrimary = customPrimary,
                effectivePrimary = effectivePrimary,
                chartBitmap = chartBitmap,
            )
            for (id in widgetIds) {
                manager.updateAppWidget(id, views)
            }
        } finally {
            chartBitmap?.recycle()
        }
    }

    private fun buildRemoteViews(
        context: Context,
        kind: WidgetKind,
        snapshot: WidgetSnapshot,
        model: WidgetDisplayModel,
        isDark: Boolean,
        customPrimary: Int,
        effectivePrimary: Int,
        chartBitmap: Bitmap?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, kind.layoutId)
        val textPrimary = ContextCompat.getColor(context, R.color.widget_text_primary)
        val okFg = ContextCompat.getColor(context, R.color.widget_status_ok_fg)
        val warnFg = ContextCompat.getColor(context, R.color.widget_status_warn_fg)
        val textSecondary = ContextCompat.getColor(context, R.color.widget_text_secondary)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val cardTint = if (isDark && snapshot.pureBlack) {
                ColorStateList.valueOf(Color.BLACK)
            } else {
                null
            }
            views.setColorStateList(android.R.id.background, "setBackgroundTintList", cardTint)
        }

        val glyphRes = when (model.status) {
            WidgetVisualStatus.STARTED, WidgetVisualStatus.STARTING -> R.drawable.ic_widget_glyph
            else -> R.drawable.ic_widget_glyph_idle
        }
        views.setImageViewResource(R.id.widget_glyph, glyphRes)

        val (statusBgRes, statusFg) = when (model.status) {
            WidgetVisualStatus.STARTED -> R.drawable.widget_bg_status_ok to okFg
            WidgetVisualStatus.STARTING,
            WidgetVisualStatus.STOPPING,
            WidgetVisualStatus.SUSPENDED,
            -> R.drawable.widget_bg_status_warn to warnFg
            WidgetVisualStatus.STOPPED,
            WidgetVisualStatus.NO_PROFILE,
            -> R.drawable.widget_bg_status_idle to textSecondary
        }
        if (kind == WidgetKind.BAR_4X1) {
            views.setImageViewResource(R.id.widget_status_dot, R.drawable.ic_widget_dot)
            views.setInt(R.id.widget_status_dot, "setColorFilter", statusFg)
            val barTitle = if (model.status == WidgetVisualStatus.STARTED && model.nodeLabel.isNotBlank()) {
                model.nodeLabel
            } else {
                model.statusLabel
            }
            views.setTextViewText(R.id.widget_status_text, barTitle)
            views.setTextColor(R.id.widget_status_text, textPrimary)
        } else {
            views.setInt(R.id.widget_status_badge, "setBackgroundResource", statusBgRes)
            views.setImageViewResource(R.id.widget_status_dot, R.drawable.ic_widget_dot)
            views.setInt(R.id.widget_status_dot, "setColorFilter", statusFg)
            views.setTextViewText(R.id.widget_status_text, model.statusLabel)
            views.setTextColor(R.id.widget_status_text, statusFg)
        }

        val toggleBgRes = when (model.status) {
            WidgetVisualStatus.STARTED -> R.drawable.widget_toggle_bg_active
            WidgetVisualStatus.STARTING,
            WidgetVisualStatus.STOPPING,
            WidgetVisualStatus.SUSPENDED,
            -> R.drawable.widget_toggle_bg_warn
            WidgetVisualStatus.STOPPED,
            WidgetVisualStatus.NO_PROFILE,
            -> R.drawable.widget_toggle_bg_idle
        }
        views.setInt(R.id.widget_toggle_button, "setBackgroundResource", toggleBgRes)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val toggleTint = if (model.status == WidgetVisualStatus.STARTED && customPrimary != 0) {
                ColorStateList.valueOf(effectivePrimary)
            } else {
                null
            }
            views.setColorStateList(R.id.widget_toggle_button, "setBackgroundTintList", toggleTint)
        }

        val isTransitioning = model.status == WidgetVisualStatus.STARTING ||
            model.status == WidgetVisualStatus.STOPPING
        if (isTransitioning) {
            views.setViewVisibility(R.id.widget_toggle_icon, View.GONE)
            views.setViewVisibility(R.id.widget_toggle_progress, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_toggle_progress, View.GONE)
            views.setViewVisibility(R.id.widget_toggle_icon, View.VISIBLE)
            if (model.status == WidgetVisualStatus.STARTED) {
                views.setImageViewResource(R.id.widget_toggle_icon, R.drawable.ic_widget_stop)
                val onPrimary = if (customPrimary != 0) {
                    readableForeground(effectivePrimary)
                } else {
                    ContextCompat.getColor(context, R.color.widget_on_primary)
                }
                views.setInt(R.id.widget_toggle_icon, "setColorFilter", onPrimary)
            } else {
                views.setImageViewResource(R.id.widget_toggle_icon, R.drawable.ic_widget_play)
                val iconColor = when (model.status) {
                    WidgetVisualStatus.SUSPENDED -> warnFg
                    WidgetVisualStatus.NO_PROFILE -> textSecondary
                    else -> textPrimary
                }
                views.setInt(R.id.widget_toggle_icon, "setColorFilter", iconColor)
            }
        }

        val modeIconRes = when (model.modeKey) {
            "global" -> R.drawable.ic_widget_mode_global
            "direct" -> R.drawable.ic_widget_mode_direct
            else -> R.drawable.ic_widget_mode_rule
        }
        views.setImageViewResource(R.id.widget_mode_icon, modeIconRes)
        views.setTextViewText(R.id.widget_mode_text, model.modeLabel)

        if (kind != WidgetKind.BAR_4X1) {
            views.setTextViewText(R.id.widget_node_text, model.nodeLabel)
            views.setViewVisibility(
                R.id.widget_node_chevron,
                if (model.canSelectProxy) View.VISIBLE else View.GONE,
            )
        }
        views.setTextViewText(R.id.widget_speed_primary, model.primaryLine)

        if (kind == WidgetKind.WIDE_4X2) {
            views.setViewVisibility(
                R.id.widget_tun_badge,
                if (model.showTunBadge) View.VISIBLE else View.GONE,
            )
            views.setTextViewText(R.id.widget_group_text, model.groupLabel)
            views.setTextViewText(R.id.widget_speed_secondary, model.secondaryLine)
            views.setViewVisibility(
                R.id.widget_speed_secondary,
                if (model.secondaryLine.isNotBlank()) View.VISIBLE else View.GONE,
            )
            if (chartBitmap != null) {
                views.setImageViewBitmap(R.id.widget_traffic_chart, chartBitmap)
                views.setViewVisibility(R.id.widget_traffic_chart, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_traffic_chart, View.GONE)
            }
        }

        val openAppIntent = openAppPendingIntent(context)
        views.setOnClickPendingIntent(R.id.widget_open_app, openAppIntent)
        if (kind == WidgetKind.WIDE_4X2) {
            views.setOnClickPendingIntent(R.id.widget_traffic_card, openAppIntent)
        }

        val toggleIntent = if (model.status == WidgetVisualStatus.NO_PROFILE) {
            openAppIntent
        } else {
            togglePendingIntent(context)
        }
        views.setOnClickPendingIntent(R.id.widget_toggle_button, toggleIntent)

        val modeIntent = if (model.status == WidgetVisualStatus.NO_PROFILE) {
            openAppIntent
        } else {
            actionPendingIntent(context, WidgetPendingAction.ACTION_CYCLE_MODE, REQUEST_CYCLE_MODE)
        }
        views.setOnClickPendingIntent(R.id.widget_mode_button, modeIntent)

        if (kind != WidgetKind.BAR_4X1) {
            val nodeIntent = if (model.canSelectProxy) {
                actionPendingIntent(context, WidgetPendingAction.ACTION_SELECT_PROXY, REQUEST_SELECT_PROXY)
            } else {
                openAppIntent
            }
            views.setOnClickPendingIntent(R.id.widget_node_button, nodeIntent)
        }

        return views
    }

    private fun openAppPendingIntent(context: Context): PendingIntent {
        val intent = Components.mainActivity.intent.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        return PendingIntent.getActivity(
            context,
            REQUEST_OPEN_APP,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun togglePendingIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            REQUEST_TOGGLE,
            QuickAction.TOGGLE.quickIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun actionPendingIntent(
        context: Context,
        actionKey: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, WidgetActionActivity::class.java).apply {
            action = "${context.packageName}.widget.$actionKey"
            putExtra(WidgetActionActivity.EXTRA_ACTION, actionKey)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun isDarkMode(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private fun readableForeground(backgroundColor: Int): Int {
        val luminance = (
            0.299 * Color.red(backgroundColor) +
                0.587 * Color.green(backgroundColor) +
                0.114 * Color.blue(backgroundColor)
            ) / 255.0
        return if (luminance > 0.62) Color.BLACK else Color.WHITE
    }

    private fun fallbackString(context: Context, key: String): String = when (key) {
        "running" -> context.getString(R.string.widget_status_running)
        "notRunning" -> context.getString(R.string.widget_status_not_running)
        "connecting" -> context.getString(R.string.widget_status_connecting)
        "stopping" -> context.getString(R.string.widget_status_stopping)
        "suspended" -> context.getString(R.string.widget_status_suspended)
        "noProfile" -> context.getString(R.string.widget_status_no_profile)
        "tapToStart" -> context.getString(R.string.widget_tap_to_start)
        "modeRule" -> context.getString(R.string.widget_mode_rule)
        "modeGlobal" -> context.getString(R.string.widget_mode_global)
        "modeDirect" -> context.getString(R.string.widget_mode_direct)
        "direct" -> context.getString(R.string.widget_mode_direct)
        "selectNodeTitle" -> context.getString(R.string.widget_select_node_title)
        "noNodesAvailable" -> context.getString(R.string.widget_no_nodes)
        "openApp" -> context.getString(com.follow.clash.common.R.string.app_name)
        else -> ""
    }
}
