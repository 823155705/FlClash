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

internal object WidgetChartRenderer {
    const val WIDE_WIDTH = 320
    const val WIDE_HEIGHT = 152
    const val COMPACT_WIDTH = 300
    const val COMPACT_HEIGHT = 156
    private const val TOP_PADDING_RATIO = 0.54f
    private const val BOTTOM_PADDING = 6f

    fun render(
        samples: List<Traffic>,
        downColor: Int,
        upColor: Int,
        isDark: Boolean,
        width: Int = WIDE_WIDTH,
        height: Int = WIDE_HEIGHT,
    ): Bitmap? {
        if (samples.size < 2 || width <= 0 || height <= 0) return null
        val peak = samples.maxOfOrNull { max(it.down, it.up) } ?: 0L
        if (peak <= 0L) return null

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val topPadding = height * TOP_PADDING_RATIO
        val drawHeight = (height - topPadding - BOTTOM_PADDING).coerceAtLeast(1f)
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
            strokeWidth = 2.8f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            color = withAlpha(upColor, if (isDark) 235 else 210)
        }
        canvas.drawPath(smoothPath(upPoints), upPaint)

        val downPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 4.2f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            color = downColor
        }
        canvas.drawPath(downPath, downPaint)

        return bitmap
    }

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
