package com.follow.clash.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import com.follow.clash.service.models.Traffic
import kotlin.math.max
import kotlin.math.roundToInt

internal data class WidgetChartSpec(
    val widthPx: Int,
    val heightPx: Int,
    val topPaddingPx: Float,
    val bottomPaddingPx: Float,
    val downStrokePx: Float,
    val upStrokePx: Float,
)

internal object WidgetChartRenderer {
    const val WIDE_WIDTH = 320
    const val WIDE_HEIGHT = 152
    const val COMPACT_WIDTH = 300
    const val COMPACT_HEIGHT = 156
    const val SPARK_BARS_WIDTH = 66
    const val SPARK_BARS_HEIGHT = 45
    const val SPARK_BAR_COUNT = 4
    const val MAX_CHART_SIDE_PX = 512
    const val MIN_CHART_WIDTH_PX = 96
    const val MIN_CHART_HEIGHT_PX = 48
    const val DOWN_STROKE_DP = 1.6f
    const val UP_STROKE_DP = 1.1f
    const val BOTTOM_PADDING_DP = 2f
    const val TEXT_CHART_GAP_DP = 3f
    const val MIN_DRAW_HEIGHT_DP = 10f
    const val LINE_HEIGHT_MULTIPLIER = 1.15f
    const val SPEED_ROW_GAP_DP = 2f
    private const val TOP_PADDING_RATIO = 0.55f
    private const val DEFAULT_BOTTOM_PADDING = 6f
    private const val DEFAULT_DOWN_STROKE_PX = 4.2f
    private const val DEFAULT_UP_STROKE_PX = 2.8f
    private const val MIN_SPARK_BAR_RATIO = 0.25f
    private val SPARK_BAR_ALPHAS = intArrayOf(140, 179, 217, 255)

    fun resolveChartSpec(
        layoutSpec: WidgetLayoutSpec,
        density: Float,
        fontScale: Float,
    ): WidgetChartSpec? {
        if (!layoutSpec.showChart) return null
        return resolveChartSpec(
            containerWidthDp = layoutSpec.trafficCardWidthDp,
            containerHeightDp = layoutSpec.trafficCardHeightDp,
            density = density,
            fontScale = fontScale,
            trafficPaddingTopDp = layoutSpec.trafficPaddingTopDp,
            downValueSp = layoutSpec.downValueSp,
            upValueSp = layoutSpec.upValueSp,
            showUploadRow = layoutSpec.showUploadRow,
        )
    }

    fun resolveChartSpec(
        containerWidthDp: Float,
        containerHeightDp: Float,
        density: Float,
        fontScale: Float,
        trafficPaddingTopDp: Float,
        downValueSp: Float,
        upValueSp: Float,
        showUploadRow: Boolean,
    ): WidgetChartSpec? {
        if (!containerWidthDp.isFinite() || !containerHeightDp.isFinite() || !density.isFinite()) return null
        if (containerWidthDp <= 0f || containerHeightDp <= 0f || density <= 0f) return null

        val safeFontScale = fontScale.takeIf { it.isFinite() && it > 0f } ?: 1f
        val downLineDp = downValueSp * LINE_HEIGHT_MULTIPLIER * safeFontScale
        val upLineDp = if (showUploadRow) {
            SPEED_ROW_GAP_DP + upValueSp * LINE_HEIGHT_MULTIPLIER * safeFontScale
        } else {
            0f
        }
        val textBottomDp = trafficPaddingTopDp + downLineDp + upLineDp + TEXT_CHART_GAP_DP
        val remainingDrawDp = containerHeightDp - textBottomDp - BOTTOM_PADDING_DP
        if (remainingDrawDp < MIN_DRAW_HEIGHT_DP) return null

        val rawWidthPx = containerWidthDp * density
        val rawHeightPx = containerHeightDp * density
        val maxRawSide = maxOf(rawWidthPx, rawHeightPx)
        val downScale = if (maxRawSide > MAX_CHART_SIDE_PX) MAX_CHART_SIDE_PX / maxRawSide else 1f
        val scaledW = rawWidthPx * downScale
        val scaledH = rawHeightPx * downScale
        val upScale = maxOf(
            if (scaledW < MIN_CHART_WIDTH_PX) MIN_CHART_WIDTH_PX / scaledW else 1f,
            if (scaledH < MIN_CHART_HEIGHT_PX) MIN_CHART_HEIGHT_PX / scaledH else 1f,
        )
        val finalScale = minOf(downScale * upScale, MAX_CHART_SIDE_PX / maxRawSide)
        val widthPx = (rawWidthPx * finalScale).roundToInt().coerceIn(1, MAX_CHART_SIDE_PX)
        val heightPx = (rawHeightPx * finalScale).roundToInt().coerceIn(1, MAX_CHART_SIDE_PX)

        val effectiveDensityX = widthPx / containerWidthDp
        val effectiveDensityY = heightPx / containerHeightDp
        val strokeScale = minOf(effectiveDensityX, effectiveDensityY)
        val topPaddingPx = (textBottomDp * effectiveDensityY).coerceIn(0f, heightPx - 1f)
        val bottomPaddingPx = (BOTTOM_PADDING_DP * effectiveDensityY).coerceAtLeast(1f)
        if (heightPx - topPaddingPx - bottomPaddingPx < 1f) return null

        return WidgetChartSpec(
            widthPx = widthPx,
            heightPx = heightPx,
            topPaddingPx = topPaddingPx,
            bottomPaddingPx = bottomPaddingPx,
            downStrokePx = (DOWN_STROKE_DP * strokeScale).coerceAtLeast(1.5f),
            upStrokePx = (UP_STROKE_DP * strokeScale).coerceAtLeast(1f),
        )
    }

    fun resolveSparkBarsSize(density: Float): Pair<Int, Int> {
        val safeDensity = density.takeIf { it.isFinite() && it > 0f } ?: 3f
        val width = (22f * safeDensity).roundToInt().coerceIn(44, 132)
        val height = (15f * safeDensity).roundToInt().coerceIn(30, 90)
        return width to height
    }

    fun render(
        samples: List<Traffic>,
        downColor: Int,
        upColor: Int,
        isDark: Boolean,
        spec: WidgetChartSpec,
    ): Bitmap? = render(
        samples = samples,
        downColor = downColor,
        upColor = upColor,
        isDark = isDark,
        width = spec.widthPx,
        height = spec.heightPx,
        topPaddingPx = spec.topPaddingPx,
        bottomPaddingPx = spec.bottomPaddingPx,
        downStrokePx = spec.downStrokePx,
        upStrokePx = spec.upStrokePx,
    )

    fun render(
        samples: List<Traffic>,
        downColor: Int,
        upColor: Int,
        isDark: Boolean,
        width: Int = WIDE_WIDTH,
        height: Int = WIDE_HEIGHT,
        topPaddingPx: Float? = null,
        bottomPaddingPx: Float = DEFAULT_BOTTOM_PADDING,
        downStrokePx: Float = DEFAULT_DOWN_STROKE_PX,
        upStrokePx: Float = DEFAULT_UP_STROKE_PX,
    ): Bitmap? {
        if (samples.size < 2 || width <= 0 || height <= 0) return null
        val peak = samples.maxOfOrNull { max(it.down, it.up) } ?: 0L
        if (peak <= 0L) return null

        val topPadding = (topPaddingPx ?: (height * TOP_PADDING_RATIO)).coerceIn(0f, height.toFloat())
        val bottomPadding = bottomPaddingPx.coerceAtLeast(0f)
        if (topPaddingPx != null && height - topPadding - bottomPadding < 1f) return null

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val drawHeight = (height - topPadding - bottomPadding).coerceAtLeast(1f)
        val stepX = width.toFloat() / (samples.size - 1).toFloat()
        val scaleY = peak.toFloat()

        val downPoints = samples.mapIndexed { index, sample ->
            val x = index * stepX
            val ratio = (sample.down.coerceAtLeast(0L).toFloat() / scaleY).coerceIn(0f, 1f)
            val y = topPadding + drawHeight * (1f - ratio)
            x to y
        }
        val upPoints = samples.mapIndexed { index, sample ->
            val x = index * stepX
            val ratio = (sample.up.coerceAtLeast(0L).toFloat() / scaleY).coerceIn(0f, 1f)
            val y = topPadding + drawHeight * (1f - ratio)
            x to y
        }

        val downPath = smoothPath(downPoints)
        val fillPath = Path(downPath).apply {
            lineTo(downPoints.last().first, height.toFloat())
            lineTo(downPoints.first().first, height.toFloat())
            close()
        }

        val fillTopAlpha = if (isDark) 72 else 56
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            shader = LinearGradient(
                0f,
                topPadding,
                0f,
                height.toFloat(),
                withAlpha(downColor, fillTopAlpha),
                withAlpha(downColor, 0),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawPath(fillPath, fillPaint)

        val upPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = upStrokePx.coerceAtLeast(1f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            color = withAlpha(upColor, if (isDark) 235 else 210)
        }
        canvas.drawPath(smoothPath(upPoints), upPaint)

        val downPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = downStrokePx.coerceAtLeast(1.5f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            color = downColor
        }
        canvas.drawPath(downPath, downPaint)

        return bitmap
    }

    fun computeSparkBarRatios(samples: List<Traffic>): List<Float>? {
        if (samples.isEmpty()) return null
        val recent = samples.takeLast(SPARK_BAR_COUNT)
        val recentPeak = recent.maxOfOrNull { totalBytes(it) } ?: 0L
        if (recentPeak <= 0L) return null
        val peak = samples.maxOfOrNull { totalBytes(it) } ?: 0L
        if (peak <= 0L) return null

        val padded = List(SPARK_BAR_COUNT - recent.size) { Traffic(0L, 0L) } + recent
        val scale = peak.toFloat()
        return padded.map { sample ->
            val raw = (totalBytes(sample).toFloat() / scale).coerceIn(0f, 1f)
            MIN_SPARK_BAR_RATIO + (1f - MIN_SPARK_BAR_RATIO) * raw
        }
    }

    fun renderSparkBars(
        samples: List<Traffic>,
        downColor: Int,
        upColor: Int,
        isDark: Boolean,
        width: Int = SPARK_BARS_WIDTH,
        height: Int = SPARK_BARS_HEIGHT,
    ): Bitmap? {
        if (width <= 0 || height <= 0) return null
        val ratios = computeSparkBarRatios(samples) ?: return null

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val gap = width * 0.12f
        val barWidth = (width - gap * (SPARK_BAR_COUNT - 1)) / SPARK_BAR_COUNT
        val radius = barWidth * 0.5f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        ratios.forEachIndexed { index, ratio ->
            val left = index * (barWidth + gap)
            val barHeight = (height * ratio).coerceIn(barWidth, height.toFloat())
            val top = height.toFloat() - barHeight
            val baseColor = if (index < 2) upColor else downColor
            val alpha = if (isDark && index < 2) {
                (SPARK_BAR_ALPHAS[index] + 20).coerceAtMost(255)
            } else {
                SPARK_BAR_ALPHAS[index]
            }
            paint.color = withAlpha(baseColor, alpha)
            canvas.drawRoundRect(
                left,
                top,
                left + barWidth,
                height.toFloat(),
                radius,
                radius,
                paint,
            )
        }

        return bitmap
    }

    private fun totalBytes(sample: Traffic): Long =
        sample.down.coerceAtLeast(0L) + sample.up.coerceAtLeast(0L)

    private fun smoothPath(points: List<Pair<Float, Float>>): Path {
        val path = Path()
        if (points.isEmpty()) return path
        path.moveTo(points.first().first, points.first().second)
        for (i in 0 until points.lastIndex) {
            val (x0, y0) = points[i]
            val (x1, y1) = points[i + 1]
            val midX = (x0 + x1) * 0.5f
            path.cubicTo(midX, y0, midX, y1, x1, y1)
        }
        return path
    }

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha.coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))
}
