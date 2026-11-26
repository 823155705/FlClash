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
import android.os.Bundle
import android.os.SystemClock
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
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
import kotlin.math.roundToInt

internal enum class WidgetKind(
    val layoutId: Int,
    val hasTrafficCard: Boolean,
) {
    COMPACT_2X2(R.layout.widget_layout_2x2, hasTrafficCard = true),
    WIDE_4X2(R.layout.widget_layout_4x2, hasTrafficCard = true),
    BAR_4X1(R.layout.widget_layout_4x1, hasTrafficCard = false),
}

internal enum class WidgetVisualStatus {
    NO_PROFILE,
    STOPPED,
    STARTING,
    STARTED,
    STOPPING,
    SUSPENDED,
}

internal data class SpeedParts(
    val value: String,
    val unit: String,
)

internal data class WideHeaderVisibility(
    val showChronometer: Boolean,
    val showTunBadge: Boolean,
)

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
    val downParts: SpeedParts,
    val upParts: SpeedParts,
)

internal object WidgetDisplayReducer {
    private const val EMPTY_PLACEHOLDER = "—"
    internal const val WIDE_CHRONO_MIN_WIDTH_DP = 275
    internal const val WIDE_TUN_MIN_WIDTH_DP = 310

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

    fun formatSpeedParts(bytesPerSecond: Long): SpeedParts {
        val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s", "TB/s")
        var value = bytesPerSecond.coerceAtLeast(0L).toDouble()
        var unit = 0
        while (value >= 1024.0 && unit < units.lastIndex) {
            value /= 1024.0
            unit++
        }
        val formatted = if (unit == 0) {
            value.toLong().toString()
        } else {
            String.format(Locale.ROOT, "%.1f", value)
        }
        return SpeedParts(value = formatted, unit = units[unit])
    }

    fun formatSpeedCompactParts(bytesPerSecond: Long): SpeedParts {
        val units = arrayOf("B", "K", "M", "G", "T")
        var value = bytesPerSecond.coerceAtLeast(0L).toDouble()
        var unit = 0
        while (value >= 1024.0 && unit < units.lastIndex) {
            value /= 1024.0
            unit++
        }
        val formatted = if (unit == 0) {
            value.toLong().toString()
        } else {
            String.format(Locale.ROOT, "%.1f", value)
        }
        return SpeedParts(value = formatted, unit = units[unit])
    }

    fun formatSpeed(bytesPerSecond: Long): String =
        formatSpeedParts(bytesPerSecond).let { "${it.value} ${it.unit}" }

    fun formatSpeedCompact(bytesPerSecond: Long): String =
        formatSpeedCompactParts(bytesPerSecond).let { "${it.value}${it.unit}" }

    fun computeChronometerBase(
        startedAtWallMillis: Long,
        nowWallMillis: Long,
        nowElapsedRealtimeMillis: Long,
    ): Long? {
        if (startedAtWallMillis <= 0L) return null
        val elapsedMillis = (nowWallMillis - startedAtWallMillis).coerceAtLeast(0L)
        return nowElapsedRealtimeMillis - elapsedMillis
    }

    fun resolveWideHeaderVisibility(
        isRunning: Boolean,
        hasChronometerBase: Boolean,
        tunEnabled: Boolean,
        widthDp: Int,
    ): WideHeaderVisibility {
        if (!isRunning) {
            return WideHeaderVisibility(showChronometer = false, showTunBadge = false)
        }
        val showChrono = hasChronometerBase && (widthDp <= 0 || widthDp >= WIDE_CHRONO_MIN_WIDTH_DP)
        val showTun = tunEnabled && (widthDp <= 0 || widthDp >= WIDE_TUN_MIN_WIDTH_DP)
        return WideHeaderVisibility(
            showChronometer = showChrono,
            showTunBadge = showTun,
        )
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
            status == WidgetVisualStatus.NO_PROFILE -> EMPTY_PLACEHOLDER
            modeKey == "direct" -> label("direct")
            snapshot.nodeName.isNotBlank() -> snapshot.nodeName
            snapshot.profileName.isNotBlank() -> snapshot.profileName
            else -> modeLabel
        }

        val groupLabel = when {
            status == WidgetVisualStatus.NO_PROFILE -> label("appName")
            modeKey == "direct" -> modeLabel
            snapshot.groupName.isNotBlank() -> snapshot.groupName
            else -> modeLabel
        }

        val downParts = if (kind.hasTrafficCard) {
            formatSpeedParts(traffic.down)
        } else {
            formatSpeedCompactParts(traffic.down)
        }
        val upParts = if (kind.hasTrafficCard) {
            formatSpeedParts(traffic.up)
        } else {
            formatSpeedCompactParts(traffic.up)
        }

        val primaryLine: String
        val secondaryLine: String
        if (status == WidgetVisualStatus.STARTED) {
            if (kind.hasTrafficCard) {
                primaryLine = "↓ ${downParts.value} ${downParts.unit}"
                secondaryLine = "↑ ${upParts.value} ${upParts.unit}"
            } else {
                val down = "↓${downParts.value}${downParts.unit}"
                val up = "↑${upParts.value}${upParts.unit}"
                primaryLine = "$down $up"
                secondaryLine = up
            }
        } else {
            val profile = snapshot.profileName.trim()
            primaryLine = when (status) {
                WidgetVisualStatus.NO_PROFILE -> label("openApp")
                WidgetVisualStatus.STARTING -> label("connecting")
                WidgetVisualStatus.STOPPING -> label("stopping")
                WidgetVisualStatus.SUSPENDED -> label("suspended")
                WidgetVisualStatus.STOPPED -> profile.ifBlank { label("tapToStart") }
                WidgetVisualStatus.STARTED -> ""
            }
            secondaryLine = when (status) {
                WidgetVisualStatus.NO_PROFILE -> label("appName")
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
            downParts = downParts,
            upParts = upParts,
        )
    }
}

private data class ChartCacheKey(
    val widthPx: Int,
    val heightPx: Int,
    val topPaddingPx: Int,
    val downStrokeTenths: Int,
)

internal object WidgetRenderer {
    private const val REQUEST_OPEN_APP = 100
    private const val REQUEST_TOGGLE = 101
    private const val REQUEST_CYCLE_MODE = 102
    private const val REQUEST_SELECT_PROXY = 103
    private const val PURE_BLACK_BLOCK_COLOR = 0xFF1C1C1E.toInt()

    fun extractOptionsSnapshot(options: Bundle?): WidgetOptionsSnapshot {
        if (options == null) return WidgetOptionsSnapshot()
        val explicitSizes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            extractExplicitSizes(options)
        } else {
            emptyList()
        }
        return WidgetOptionsSnapshot(
            explicitSizes = explicitSizes,
            minWidthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
            maxWidthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0),
            minHeightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0),
            maxHeightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0),
        )
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun extractExplicitSizes(options: Bundle): List<WidgetSizeDp> {
        val rawSizes: List<SizeF?>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            options.getParcelableArrayList(
                AppWidgetManager.OPTION_APPWIDGET_SIZES,
                SizeF::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES)
        }
        return rawSizes?.mapNotNull { size ->
            if (size != null && size.width > 0f && size.height > 0f) {
                WidgetSizeDp(widthDp = size.width, heightDp = size.height)
            } else {
                null
            }
        } ?: emptyList()
    }

    fun bind(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
        kind: WidgetKind,
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
        startedAtMillis: Long = 0L,
        optionsProvider: (Int) -> WidgetOptionsSnapshot = { id ->
            extractOptionsSnapshot(manager.getAppWidgetOptions(id))
        },
    ) {
        if (widgetIds.isEmpty()) return
        val isDark = isDarkMode(context)
        val density = context.resources.displayMetrics.density.takeIf { it.isFinite() && it > 0f } ?: 1f
        val fontScale = context.resources.configuration.fontScale.takeIf { it.isFinite() && it > 0f } ?: 1f
        val isLandscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val isRtl = context.resources.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL
        val supportsMultiSize = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        val systemOuterRadiusDp = resolveSystemOuterRadiusDp(context, density)

        val model = WidgetDisplayReducer.reduce(
            kind = kind,
            runState = runState,
            snapshot = snapshot,
            traffic = traffic,
        ) { key -> fallbackString(context, key) }

        val customPrimary = if (isDark) snapshot.primaryColorDark else snapshot.primaryColorLight
        val downColor = if (customPrimary != 0) {
            customPrimary
        } else {
            ContextCompat.getColor(context, R.color.widget_chart_down)
        }
        val upColor = ContextCompat.getColor(context, R.color.widget_chart_up)

        val sparkBarsBitmap = if (kind == WidgetKind.BAR_4X1 && model.status == WidgetVisualStatus.STARTED) {
            val (sparkW, sparkH) = WidgetChartRenderer.resolveSparkBarsSize(density)
            WidgetChartRenderer.renderSparkBars(
                samples = history,
                downColor = downColor,
                upColor = upColor,
                isDark = isDark,
                width = sparkW,
                height = sparkH,
            )
        } else {
            null
        }

        val chronometerBase = if (kind == WidgetKind.WIDE_4X2 && model.status == WidgetVisualStatus.STARTED) {
            WidgetDisplayReducer.computeChronometerBase(
                startedAtWallMillis = startedAtMillis,
                nowWallMillis = System.currentTimeMillis(),
                nowElapsedRealtimeMillis = SystemClock.elapsedRealtime(),
            )
        } else {
            null
        }

        val chartCache = HashMap<ChartCacheKey, Bitmap?>()
        fun chartFor(spec: WidgetLayoutSpec): Bitmap? {
            if (!kind.hasTrafficCard || !spec.showChart || model.status != WidgetVisualStatus.STARTED) {
                return null
            }
            val chartSpec = WidgetChartRenderer.resolveChartSpec(spec, density, fontScale) ?: return null
            val key = ChartCacheKey(
                widthPx = chartSpec.widthPx,
                heightPx = chartSpec.heightPx,
                topPaddingPx = chartSpec.topPaddingPx.roundToInt(),
                downStrokeTenths = (chartSpec.downStrokePx * 10f).roundToInt(),
            )
            return chartCache.getOrPut(key) {
                WidgetChartRenderer.render(
                    samples = history,
                    downColor = downColor,
                    upColor = upColor,
                    isDark = isDark,
                    spec = chartSpec,
                )
            }
        }

        try {
            for (id in widgetIds) {
                val options = optionsProvider(id)
                val sizes = WidgetSizingResolver.resolveSizes(
                    kind = kind,
                    options = options,
                    isLandscape = isLandscape,
                    supportsMultiSizeRemoteViews = supportsMultiSize,
                )
                val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && sizes.size > 1) {
                    buildResponsiveRemoteViews(
                        context = context,
                        kind = kind,
                        sizes = sizes,
                        snapshot = snapshot,
                        model = model,
                        isDark = isDark,
                        density = density,
                        isRtl = isRtl,
                        systemOuterRadiusDp = systemOuterRadiusDp,
                        chartFor = ::chartFor,
                        sparkBarsBitmap = sparkBarsBitmap,
                        chronometerBase = chronometerBase,
                    )
                } else {
                    val primarySize = sizes.first()
                    val spec = WidgetLayoutSpecResolver.resolve(
                        kind = kind,
                        size = primarySize,
                        supportsDynamicLayoutParams = supportsMultiSize,
                    )
                    buildRemoteViewsForSize(
                        context = context,
                        kind = kind,
                        size = primarySize,
                        snapshot = snapshot,
                        model = model,
                        isDark = isDark,
                        density = density,
                        isRtl = isRtl,
                        systemOuterRadiusDp = systemOuterRadiusDp,
                        chartBitmap = chartFor(spec),
                        sparkBarsBitmap = sparkBarsBitmap,
                        chronometerBase = chronometerBase,
                        resolvedSpec = spec,
                    )
                }
                manager.updateAppWidget(id, views)
            }
        } finally {
            chartCache.values.forEach { it?.recycle() }
            sparkBarsBitmap?.recycle()
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun buildResponsiveRemoteViews(
        context: Context,
        kind: WidgetKind,
        sizes: List<WidgetSizeDp>,
        snapshot: WidgetSnapshot,
        model: WidgetDisplayModel,
        isDark: Boolean,
        density: Float,
        isRtl: Boolean,
        systemOuterRadiusDp: Float,
        chartFor: (WidgetLayoutSpec) -> Bitmap?,
        sparkBarsBitmap: Bitmap?,
        chronometerBase: Long?,
    ): RemoteViews {
        val viewsBySize = LinkedHashMap<SizeF, RemoteViews>(sizes.size)
        for (size in sizes) {
            val spec = WidgetLayoutSpecResolver.resolve(kind, size)
            viewsBySize[SizeF(size.widthDp, size.heightDp)] = buildRemoteViewsForSize(
                context = context,
                kind = kind,
                size = size,
                snapshot = snapshot,
                model = model,
                isDark = isDark,
                density = density,
                isRtl = isRtl,
                systemOuterRadiusDp = systemOuterRadiusDp,
                chartBitmap = chartFor(spec),
                sparkBarsBitmap = sparkBarsBitmap,
                chronometerBase = chronometerBase,
                resolvedSpec = spec,
            )
        }
        return RemoteViews(viewsBySize)
    }

    private fun buildRemoteViewsForSize(
        context: Context,
        kind: WidgetKind,
        size: WidgetSizeDp,
        snapshot: WidgetSnapshot,
        model: WidgetDisplayModel,
        isDark: Boolean,
        density: Float,
        isRtl: Boolean,
        systemOuterRadiusDp: Float,
        chartBitmap: Bitmap?,
        sparkBarsBitmap: Bitmap?,
        chronometerBase: Long?,
        resolvedSpec: WidgetLayoutSpec,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, kind.layoutId)
        val radii = WidgetRadiusResolver.resolve(
            kind = kind,
            size = size,
            systemOuterRadiusDp = systemOuterRadiusDp,
            innerInsetDp = resolvedSpec.innerRadiusInsetDp,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyDynamicSurfacesAndRadii(views, kind, radii, snapshot.pureBlack)
        }

        applyLayoutSpec(views, resolvedSpec, density, isRtl)

        val glyphRes = when (model.status) {
            WidgetVisualStatus.STARTED, WidgetVisualStatus.STARTING -> R.drawable.ic_widget_glyph
            else -> R.drawable.ic_widget_glyph_idle
        }
        views.setImageViewResource(R.id.widget_glyph, glyphRes)

        val (statusBgRes, statusFgRes) = when (model.status) {
            WidgetVisualStatus.STARTED -> R.drawable.widget_bg_status_ok to R.color.widget_status_ok_fg
            WidgetVisualStatus.STARTING,
            WidgetVisualStatus.STOPPING,
            WidgetVisualStatus.SUSPENDED,
            -> R.drawable.widget_bg_status_warn to R.color.widget_status_warn_fg
            WidgetVisualStatus.STOPPED,
            WidgetVisualStatus.NO_PROFILE,
            -> R.drawable.widget_bg_status_idle to R.color.widget_text_secondary
        }
        if (kind == WidgetKind.BAR_4X1) {
            views.setImageViewResource(R.id.widget_status_dot, R.drawable.ic_widget_dot)
            setImageTintRes(views, context, R.id.widget_status_dot, statusFgRes)
            if (model.status == WidgetVisualStatus.STARTED) {
                val barTitle = model.nodeLabel.ifBlank { model.statusLabel }
                views.setTextViewText(R.id.widget_bar_node_text, barTitle)
                views.setViewVisibility(R.id.widget_bar_node_text, View.VISIBLE)
                views.setViewVisibility(R.id.widget_status_text, View.GONE)
            } else {
                views.setTextViewText(R.id.widget_status_text, model.statusLabel)
                views.setViewVisibility(R.id.widget_status_text, View.VISIBLE)
                views.setViewVisibility(R.id.widget_bar_node_text, View.GONE)
            }
        } else {
            views.setInt(R.id.widget_status_badge, "setBackgroundResource", statusBgRes)
            views.setImageViewResource(R.id.widget_status_dot, R.drawable.ic_widget_dot)
            setImageTintRes(views, context, R.id.widget_status_dot, statusFgRes)
            views.setTextViewText(R.id.widget_status_text, model.statusLabel)
            setTextColorRes(views, context, R.id.widget_status_text, statusFgRes)
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
        val hasCustomPrimary = snapshot.primaryColorLight != 0 || snapshot.primaryColorDark != 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (model.status == WidgetVisualStatus.STARTED && hasCustomPrimary) {
                val lightTint = snapshot.primaryColorLight.takeIf { it != 0 }?.let(ColorStateList::valueOf)
                val darkTint = snapshot.primaryColorDark.takeIf { it != 0 }?.let(ColorStateList::valueOf)
                views.setColorStateList(R.id.widget_toggle_button, "setBackgroundTintList", lightTint, darkTint)
            } else {
                views.setColorStateList(R.id.widget_toggle_button, "setBackgroundTintList", null)
            }
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
                if (hasCustomPrimary) {
                    val lightFg = if (snapshot.primaryColorLight != 0) {
                        readableForeground(snapshot.primaryColorLight)
                    } else {
                        Color.WHITE
                    }
                    val darkFg = if (snapshot.primaryColorDark != 0) {
                        readableForeground(snapshot.primaryColorDark)
                    } else {
                        Color.WHITE
                    }
                    setImageTintDynamic(views, R.id.widget_toggle_icon, lightFg, darkFg, isDark)
                } else {
                    setImageTintRes(views, context, R.id.widget_toggle_icon, R.color.widget_on_primary)
                }
            } else {
                views.setImageViewResource(R.id.widget_toggle_icon, R.drawable.ic_widget_play)
                val iconColorRes = when (model.status) {
                    WidgetVisualStatus.SUSPENDED -> R.color.widget_status_warn_fg
                    WidgetVisualStatus.NO_PROFILE -> R.color.widget_text_secondary
                    else -> R.color.widget_text_primary
                }
                setImageTintRes(views, context, R.id.widget_toggle_icon, iconColorRes)
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
            val nodeColorRes = if (model.status == WidgetVisualStatus.NO_PROFILE) {
                R.color.widget_text_secondary
            } else {
                R.color.widget_text_primary
            }
            setTextColorRes(views, context, R.id.widget_node_text, nodeColorRes)
            views.setViewVisibility(
                R.id.widget_node_chevron,
                if (model.canSelectProxy) View.VISIBLE else View.GONE,
            )
        }
        if (kind == WidgetKind.WIDE_4X2) {
            val headerVisibility = WidgetDisplayReducer.resolveWideHeaderVisibility(
                isRunning = model.status == WidgetVisualStatus.STARTED,
                hasChronometerBase = chronometerBase != null,
                tunEnabled = snapshot.tunEnabled,
                widthDp = size.widthDp.roundToInt(),
            )
            if (headerVisibility.showChronometer && chronometerBase != null) {
                views.setChronometer(R.id.widget_chronometer, chronometerBase, null, true)
                views.setViewVisibility(R.id.widget_chronometer, View.VISIBLE)
            } else {
                views.setChronometer(R.id.widget_chronometer, SystemClock.elapsedRealtime(), null, false)
                views.setViewVisibility(R.id.widget_chronometer, View.GONE)
            }
            views.setViewVisibility(
                R.id.widget_tun_badge,
                if (headerVisibility.showTunBadge) View.VISIBLE else View.GONE,
            )
            views.setTextViewText(R.id.widget_group_text, model.groupLabel)
        }

        val isRunning = model.status == WidgetVisualStatus.STARTED
        if (isRunning) {
            views.setViewVisibility(R.id.widget_speed_running, View.VISIBLE)
            views.setTextViewText(R.id.widget_down_value, model.downParts.value)
            views.setTextViewText(R.id.widget_down_unit, model.downParts.unit)
            views.setTextViewText(R.id.widget_up_value, model.upParts.value)
            views.setTextViewText(R.id.widget_up_unit, model.upParts.unit)
            if (hasCustomPrimary) {
                setTextColorDynamic(
                    views = views,
                    context = context,
                    viewId = R.id.widget_down_arrow,
                    lightColor = snapshot.primaryColorLight,
                    darkColor = snapshot.primaryColorDark,
                    fallbackResId = R.color.widget_chart_down,
                    isDark = isDark,
                )
            } else {
                setTextColorRes(views, context, R.id.widget_down_arrow, R.color.widget_chart_down)
            }
            if (kind.hasTrafficCard) {
                views.setViewVisibility(R.id.widget_speed_idle, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_speed_primary, View.GONE)
                val barSpec = resolvedSpec as Bar4x1LayoutSpec
                if (barSpec.showSparkBars && sparkBarsBitmap != null) {
                    views.setImageViewBitmap(R.id.widget_spark_bars, sparkBarsBitmap)
                    views.setViewVisibility(R.id.widget_spark_bars, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_spark_bars, View.GONE)
                }
            }
        } else {
            views.setViewVisibility(R.id.widget_speed_running, View.GONE)
            views.setTextViewText(R.id.widget_speed_primary, model.primaryLine)
            if (kind.hasTrafficCard) {
                views.setViewVisibility(R.id.widget_speed_idle, View.VISIBLE)
                views.setTextViewText(R.id.widget_speed_secondary, model.secondaryLine)
                val allowSecondary = when (resolvedSpec) {
                    is Compact2x2LayoutSpec -> resolvedSpec.showIdleSecondary
                    is Wide4x2LayoutSpec -> resolvedSpec.showIdleSecondary
                    is Bar4x1LayoutSpec -> false
                }
                views.setViewVisibility(
                    R.id.widget_speed_secondary,
                    if (allowSecondary && model.secondaryLine.isNotBlank()) View.VISIBLE else View.GONE,
                )
            } else {
                views.setViewVisibility(R.id.widget_speed_primary, View.VISIBLE)
                views.setViewVisibility(R.id.widget_spark_bars, View.GONE)
            }
        }

        if (kind.hasTrafficCard) {
            if (chartBitmap != null) {
                views.setImageViewBitmap(R.id.widget_traffic_chart, chartBitmap)
                views.setViewVisibility(R.id.widget_traffic_chart, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_traffic_chart, View.GONE)
            }
        }

        val openAppIntent = openAppPendingIntent(context)
        views.setOnClickPendingIntent(R.id.widget_open_app, openAppIntent)
        if (kind.hasTrafficCard) {
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

    @RequiresApi(Build.VERSION_CODES.S)
    private fun applyDynamicSurfacesAndRadii(
        views: RemoteViews,
        kind: WidgetKind,
        radii: WidgetCornerRadii,
        pureBlack: Boolean,
    ) {
        // Switch to square-cornered drawables so setViewOutlinePreferredRadius governs exact clipping without XML double-clipping.
        views.setInt(android.R.id.background, "setBackgroundResource", R.drawable.widget_bg_card_surface)
        views.setViewOutlinePreferredRadius(
            android.R.id.background,
            radii.outerRadiusDp,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        applyBlockSurface(views, R.id.widget_mode_button, radii.innerRadiusDp)
        if (kind.hasTrafficCard) {
            applyBlockSurface(views, R.id.widget_traffic_card, radii.innerRadiusDp)
            applyBlockSurface(views, R.id.widget_node_button, radii.innerRadiusDp)
        }

        val cardTintDark = if (pureBlack) ColorStateList.valueOf(Color.BLACK) else null
        val blockTintDark = if (pureBlack) ColorStateList.valueOf(PURE_BLACK_BLOCK_COLOR) else null
        setDarkOnlyBackgroundTint(views, android.R.id.background, cardTintDark)
        setDarkOnlyBackgroundTint(views, R.id.widget_mode_button, blockTintDark)
        if (kind.hasTrafficCard) {
            setDarkOnlyBackgroundTint(views, R.id.widget_traffic_card, blockTintDark)
            setDarkOnlyBackgroundTint(views, R.id.widget_node_button, blockTintDark)
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun applyBlockSurface(
        views: RemoteViews,
        viewId: Int,
        radiusDp: Float,
    ) {
        views.setInt(viewId, "setBackgroundResource", R.drawable.widget_bg_block_surface)
        views.setViewOutlinePreferredRadius(viewId, radiusDp, TypedValue.COMPLEX_UNIT_DIP)
    }

    private fun applyLayoutSpec(
        views: RemoteViews,
        spec: WidgetLayoutSpec,
        density: Float,
        isRtl: Boolean,
    ) {
        val rootPadH = dpToPx(spec.cardPaddingHorizontalDp, density)
        val rootPadV = dpToPx(spec.cardPaddingVerticalDp, density)
        views.setViewPadding(android.R.id.background, rootPadH, rootPadV, rootPadH, rootPadV)

        views.setViewVisibility(R.id.widget_glyph, if (spec.showGlyph) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.widget_mode_text, if (spec.showModeText) View.VISIBLE else View.GONE)
        views.setTextViewTextSize(R.id.widget_mode_text, TypedValue.COMPLEX_UNIT_SP, spec.modeTextSp)

        views.setTextViewTextSize(R.id.widget_down_value, TypedValue.COMPLEX_UNIT_SP, spec.downValueSp)
        views.setTextViewTextSize(R.id.widget_down_arrow, TypedValue.COMPLEX_UNIT_SP, spec.downArrowSp)
        views.setTextViewTextSize(R.id.widget_down_unit, TypedValue.COMPLEX_UNIT_SP, spec.downUnitSp)
        views.setTextViewTextSize(R.id.widget_up_value, TypedValue.COMPLEX_UNIT_SP, spec.upValueSp)
        views.setTextViewTextSize(R.id.widget_up_arrow, TypedValue.COMPLEX_UNIT_SP, spec.upArrowSp)
        views.setTextViewTextSize(R.id.widget_up_unit, TypedValue.COMPLEX_UNIT_SP, spec.upUnitSp)
        views.setTextViewTextSize(R.id.widget_speed_primary, TypedValue.COMPLEX_UNIT_SP, spec.idlePrimarySp)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setViewSquareSizeDp(views, R.id.widget_glyph, spec.glyphSizeDp)
            setViewSquareSizeDp(views, R.id.widget_toggle_button, spec.toggleSizeDp)
            setViewSquareSizeDp(views, R.id.widget_toggle_icon, spec.toggleIconSizeDp)
            setViewSquareSizeDp(views, R.id.widget_toggle_progress, spec.toggleProgressSizeDp)
            views.setViewLayoutMargin(
                R.id.widget_mode_icon,
                RemoteViews.MARGIN_END,
                if (spec.showModeText) spec.modeIconGapDp else 0f,
                TypedValue.COMPLEX_UNIT_DIP,
            )
            val modePadH = dpToPx(
                if (spec.showModeText) spec.modePaddingHorizontalDp else spec.modeIconOnlyPaddingHorizontalDp,
                density,
            )
            views.setViewPadding(R.id.widget_mode_button, modePadH, 0, modePadH, 0)
        } else {
            if (spec.showModeText) {
                val modePadH = dpToPx(spec.modePaddingHorizontalDp, density)
                views.setViewPadding(R.id.widget_mode_button, modePadH, 0, modePadH, 0)
            } else {
                val startPx = dpToPx(spec.modeIconOnlyPaddingHorizontalDp, density)
                val endPx = dpToPx(
                    (spec.modeIconOnlyPaddingHorizontalDp - spec.modeIconGapDp).coerceAtLeast(0f),
                    density,
                )
                setViewPaddingRelative(views, R.id.widget_mode_button, startPx, 0, endPx, 0, isRtl)
            }
        }

        when (spec) {
            is Compact2x2LayoutSpec -> applyCompact2x2Spec(views, spec, density, isRtl)
            is Wide4x2LayoutSpec -> applyWide4x2Spec(views, spec, density)
            is Bar4x1LayoutSpec -> applyBar4x1Spec(views, spec)
        }
    }

    private fun applyCompact2x2Spec(
        views: RemoteViews,
        spec: Compact2x2LayoutSpec,
        density: Float,
        isRtl: Boolean,
    ) {
        val badgePadH = dpToPx(spec.statusBadgePaddingHorizontalDp, density)
        views.setViewPadding(R.id.widget_status_badge, badgePadH, 0, badgePadH, 0)
        views.setTextViewTextSize(R.id.widget_status_text, TypedValue.COMPLEX_UNIT_SP, spec.statusTextSp)

        val trafficPadH = dpToPx(spec.trafficPaddingHorizontalDp, density)
        val trafficPadTop = dpToPx(spec.trafficPaddingTopDp, density)
        val trafficPadBottom = dpToPx(spec.trafficPaddingBottomDp, density)
        views.setViewPadding(R.id.widget_traffic_content, trafficPadH, trafficPadTop, trafficPadH, trafficPadBottom)
        views.setViewVisibility(R.id.widget_speed_up_row, if (spec.showUploadRow) View.VISIBLE else View.GONE)
        views.setTextViewTextSize(R.id.widget_speed_secondary, TypedValue.COMPLEX_UNIT_SP, spec.idleSecondarySp)

        setViewPaddingRelative(
            views = views,
            viewId = R.id.widget_node_button,
            startPx = dpToPx(spec.nodePaddingStartDp, density),
            topPx = 0,
            endPx = dpToPx(spec.nodePaddingEndDp, density),
            bottomPx = 0,
            isRtl = isRtl,
        )
        views.setTextViewTextSize(R.id.widget_node_text, TypedValue.COMPLEX_UNIT_SP, spec.nodeTextSp)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setInt(R.id.widget_mode_button, "setMinimumWidth", dpToPx(spec.modeMinWidthDp, density))
            views.setViewLayoutHeight(R.id.widget_header, spec.headerHeightDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(R.id.widget_status_badge, spec.statusBadgeHeightDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutMargin(
                R.id.widget_traffic_card,
                RemoteViews.MARGIN_TOP,
                spec.sectionGapDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
            views.setViewLayoutMargin(
                R.id.widget_traffic_card,
                RemoteViews.MARGIN_BOTTOM,
                spec.sectionGapDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
            views.setViewLayoutHeight(R.id.widget_footer, spec.footerHeightDp, TypedValue.COMPLEX_UNIT_DIP)
        }
    }

    private fun applyWide4x2Spec(
        views: RemoteViews,
        spec: Wide4x2LayoutSpec,
        density: Float,
    ) {
        val badgePadH = dpToPx(spec.statusBadgePaddingHorizontalDp, density)
        views.setViewPadding(R.id.widget_status_badge, badgePadH, 0, badgePadH, 0)
        views.setTextViewTextSize(R.id.widget_status_text, TypedValue.COMPLEX_UNIT_SP, spec.statusTextSp)

        val trafficPadH = dpToPx(spec.trafficPaddingHorizontalDp, density)
        val trafficPadTop = dpToPx(spec.trafficPaddingTopDp, density)
        val trafficPadBottom = dpToPx(spec.trafficPaddingBottomDp, density)
        views.setViewPadding(R.id.widget_traffic_content, trafficPadH, trafficPadTop, trafficPadH, trafficPadBottom)
        views.setViewVisibility(R.id.widget_speed_up_row, if (spec.showUploadRow) View.VISIBLE else View.GONE)
        views.setTextViewTextSize(R.id.widget_speed_secondary, TypedValue.COMPLEX_UNIT_SP, spec.idleSecondarySp)

        val nodePadH = dpToPx(spec.nodePaddingHorizontalDp, density)
        val nodePadV = dpToPx(spec.nodePaddingVerticalDp, density)
        views.setViewPadding(R.id.widget_node_button, nodePadH, nodePadV, nodePadH, nodePadV)
        views.setTextViewTextSize(R.id.widget_group_text, TypedValue.COMPLEX_UNIT_SP, spec.groupTextSp)
        views.setTextViewTextSize(R.id.widget_node_text, TypedValue.COMPLEX_UNIT_SP, spec.nodeTextSp)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutHeight(R.id.widget_header, spec.headerHeightDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(R.id.widget_status_badge, spec.statusBadgeHeightDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(R.id.widget_mode_button, spec.modeButtonHeightDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutMargin(
                R.id.widget_body,
                RemoteViews.MARGIN_TOP,
                spec.bodyTopGapDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
            views.setViewLayoutMargin(
                R.id.widget_traffic_card,
                RemoteViews.MARGIN_END,
                spec.bodyColumnGapDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
        }
    }

    private fun applyBar4x1Spec(
        views: RemoteViews,
        spec: Bar4x1LayoutSpec,
    ) {
        views.setTextViewTextSize(R.id.widget_status_text, TypedValue.COMPLEX_UNIT_SP, spec.statusTextSp)
        views.setTextViewTextSize(R.id.widget_bar_node_text, TypedValue.COMPLEX_UNIT_SP, spec.barNodeTextSp)
        val upVisibility = if (spec.showUploadRow) View.VISIBLE else View.GONE
        views.setViewVisibility(R.id.widget_up_arrow, upVisibility)
        views.setViewVisibility(R.id.widget_up_value, upVisibility)
        views.setViewVisibility(R.id.widget_up_unit, upVisibility)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutHeight(R.id.widget_mode_button, spec.modeButtonHeightDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutMargin(
                R.id.widget_mode_button,
                RemoteViews.MARGIN_END,
                spec.actionGapDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
            views.setViewLayoutMargin(
                R.id.widget_open_app,
                RemoteViews.MARGIN_END,
                spec.actionGapDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun setViewSquareSizeDp(
        views: RemoteViews,
        viewId: Int,
        sizeDp: Float,
    ) {
        views.setViewLayoutWidth(viewId, sizeDp, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(viewId, sizeDp, TypedValue.COMPLEX_UNIT_DIP)
    }

    private fun setViewPaddingRelative(
        views: RemoteViews,
        viewId: Int,
        startPx: Int,
        topPx: Int,
        endPx: Int,
        bottomPx: Int,
        isRtl: Boolean,
    ) {
        if (isRtl) {
            views.setViewPadding(viewId, endPx, topPx, startPx, bottomPx)
        } else {
            views.setViewPadding(viewId, startPx, topPx, endPx, bottomPx)
        }
    }

    private fun dpToPx(dp: Float, density: Float): Int =
        (dp * density).roundToInt().coerceAtLeast(0)

    private fun resolveSystemOuterRadiusDp(context: Context, density: Float): Float {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return WidgetRadiusResolver.FALLBACK_OUTER_RADIUS_DP
        }
        return runCatching {
            context.resources.getDimension(android.R.dimen.system_app_widget_background_radius) / density
        }.getOrDefault(0f)
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

    private fun setDarkOnlyBackgroundTint(
        views: RemoteViews,
        viewId: Int,
        darkTint: ColorStateList?,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        if (darkTint != null) {
            views.setColorStateList(viewId, "setBackgroundTintList", null, darkTint)
        } else {
            views.setColorStateList(viewId, "setBackgroundTintList", null)
        }
    }

    private fun setTextColorRes(
        views: RemoteViews,
        context: Context,
        viewId: Int,
        colorResId: Int,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(viewId, "setTextColor", colorResId)
        } else {
            views.setTextColor(viewId, ContextCompat.getColor(context, colorResId))
        }
    }

    private fun setTextColorDynamic(
        views: RemoteViews,
        context: Context,
        viewId: Int,
        lightColor: Int,
        darkColor: Int,
        fallbackResId: Int,
        isDark: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val resolvedLight = lightColor.takeIf { it != 0 }
                ?: ContextCompat.getColor(contextForNightMode(context, false), fallbackResId)
            val resolvedDark = darkColor.takeIf { it != 0 }
                ?: ContextCompat.getColor(contextForNightMode(context, true), fallbackResId)
            views.setColorStateList(
                viewId,
                "setTextColor",
                ColorStateList.valueOf(resolvedLight),
                ColorStateList.valueOf(resolvedDark),
            )
        } else {
            val resolved = (if (isDark) darkColor else lightColor).takeIf { it != 0 }
                ?: ContextCompat.getColor(context, fallbackResId)
            views.setTextColor(viewId, resolved)
        }
    }

    private fun contextForNightMode(context: Context, night: Boolean): Context {
        val config = Configuration(context.resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        return context.createConfigurationContext(config)
    }

    private fun setImageTintRes(
        views: RemoteViews,
        context: Context,
        viewId: Int,
        colorResId: Int,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(viewId, "setImageTintList", colorResId)
        } else {
            views.setInt(viewId, "setColorFilter", ContextCompat.getColor(context, colorResId))
        }
    }

    private fun setImageTintDynamic(
        views: RemoteViews,
        viewId: Int,
        lightColor: Int,
        darkColor: Int,
        isDark: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(
                viewId,
                "setImageTintList",
                ColorStateList.valueOf(lightColor),
                ColorStateList.valueOf(darkColor),
            )
        } else {
            views.setInt(viewId, "setColorFilter", if (isDark) darkColor else lightColor)
        }
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
        "openApp" -> context.getString(R.string.widget_open_app)
        "appName" -> context.getString(com.follow.clash.common.R.string.app_name)
        else -> ""
    }
}
