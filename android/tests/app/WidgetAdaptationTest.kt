package com.follow.clash.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetAdaptationTest {
    @Test
    fun `size resolver prioritizes explicit SizeF list on API 31+ and filters invalid entries`() {
        val options = WidgetOptionsSnapshot(
            explicitSizes = listOf(
                WidgetSizeDp(0f, 140f),
                WidgetSizeDp(-10f, 140f),
                WidgetSizeDp(Float.NaN, 140f),
                WidgetSizeDp(140f, 150f),
                WidgetSizeDp(140f, 150f),
                WidgetSizeDp(185f, 120f),
            ),
            minWidthDp = 120,
            maxWidthDp = 200,
            minHeightDp = 110,
            maxHeightDp = 160,
        )

        val resolvedApi31 = WidgetSizingResolver.resolveSizes(
            kind = WidgetKind.COMPACT_2X2,
            options = options,
            isLandscape = false,
            supportsMultiSizeRemoteViews = true,
        )
        assertEquals(
            listOf(WidgetSizeDp(140f, 150f), WidgetSizeDp(185f, 120f)),
            resolvedApi31,
        )

        val resolvedLegacyPortrait = WidgetSizingResolver.resolveSizes(
            kind = WidgetKind.COMPACT_2X2,
            options = options,
            isLandscape = false,
            supportsMultiSizeRemoteViews = false,
        )
        assertEquals(listOf(WidgetSizeDp(120f, 160f)), resolvedLegacyPortrait)

        val resolvedLegacyLandscape = WidgetSizingResolver.resolveSizes(
            kind = WidgetKind.COMPACT_2X2,
            options = options,
            isLandscape = true,
            supportsMultiSizeRemoteViews = false,
        )
        assertEquals(listOf(WidgetSizeDp(200f, 110f)), resolvedLegacyLandscape)
    }

    @Test
    fun `size resolver falls back to portrait and landscape bounds when explicit sizes are absent`() {
        val options = WidgetOptionsSnapshot(
            minWidthDp = 280,
            maxWidthDp = 420,
            minHeightDp = 124,
            maxHeightDp = 164,
        )

        val multi = WidgetSizingResolver.resolveSizes(
            kind = WidgetKind.WIDE_4X2,
            options = options,
            isLandscape = false,
            supportsMultiSizeRemoteViews = true,
        )
        assertEquals(
            listOf(WidgetSizeDp(280f, 164f), WidgetSizeDp(420f, 124f)),
            multi,
        )

        val squareOptions = WidgetOptionsSnapshot(
            minWidthDp = 150,
            maxWidthDp = 150,
            minHeightDp = 150,
            maxHeightDp = 150,
        )
        assertEquals(
            listOf(WidgetSizeDp(150f, 150f)),
            WidgetSizingResolver.resolveSizes(
                kind = WidgetKind.COMPACT_2X2,
                options = squareOptions,
                isLandscape = false,
                supportsMultiSizeRemoteViews = true,
            ),
        )

        val partialOptions = WidgetOptionsSnapshot(minWidthDp = 260)
        val partialResolved = WidgetSizingResolver.resolveSizes(
            kind = WidgetKind.BAR_4X1,
            options = partialOptions,
            isLandscape = false,
            supportsMultiSizeRemoteViews = true,
        )
        assertEquals(listOf(WidgetSizeDp(260f, 64f)), partialResolved)
    }

    @Test
    fun `size resolver uses per-kind defaults when launcher provides zero options`() {
        val empty = WidgetOptionsSnapshot()
        assertFalse(empty.hasAnyDimension())

        assertEquals(
            listOf(WidgetSizingResolver.defaultSize(WidgetKind.COMPACT_2X2)),
            WidgetSizingResolver.resolveSizes(WidgetKind.COMPACT_2X2, empty, false, true),
        )
        assertEquals(
            listOf(WidgetSizingResolver.defaultSize(WidgetKind.WIDE_4X2)),
            WidgetSizingResolver.resolveSizes(WidgetKind.WIDE_4X2, empty, true, false),
        )
        assertEquals(
            listOf(WidgetSizingResolver.defaultSize(WidgetKind.BAR_4X1)),
            WidgetSizingResolver.resolveSizes(WidgetKind.BAR_4X1, empty, false, true),
        )
    }

    @Test
    fun `radius resolver computes concentric inner radii and handles zero fallback`() {
        val pixel2x2 = WidgetRadiusResolver.resolve(
            kind = WidgetKind.COMPACT_2X2,
            size = WidgetSizeDp(168f, 168f),
            systemOuterRadiusDp = 28f,
            innerInsetDp = 10f,
        )
        assertEquals(28f, pixel2x2.outerRadiusDp, 0.01f)
        assertEquals(18f, pixel2x2.innerRadiusDp, 0.01f)

        val hyperOs2x2 = WidgetRadiusResolver.resolve(
            kind = WidgetKind.COMPACT_2X2,
            size = WidgetSizeDp(140f, 140f),
            systemOuterRadiusDp = 20f,
            innerInsetDp = 7f,
        )
        assertEquals(20f, hyperOs2x2.outerRadiusDp, 0.01f)
        assertEquals(13f, hyperOs2x2.innerRadiusDp, 0.01f)

        val tightAosp = WidgetRadiusResolver.resolve(
            kind = WidgetKind.WIDE_4X2,
            size = WidgetSizeDp(320f, 160f),
            systemOuterRadiusDp = 8f,
            innerInsetDp = 10f,
        )
        assertEquals(8f, tightAosp.outerRadiusDp, 0.01f)
        assertEquals(0f, tightAosp.innerRadiusDp, 0.01f)

        val zeroFallback = WidgetRadiusResolver.resolve(
            kind = WidgetKind.WIDE_4X2,
            size = WidgetSizeDp(320f, 160f),
            systemOuterRadiusDp = 0f,
            innerInsetDp = 10f,
        )
        assertEquals(WidgetRadiusResolver.FALLBACK_OUTER_RADIUS_DP, zeroFallback.outerRadiusDp, 0.01f)
        assertEquals(14f, zeroFallback.innerRadiusDp, 0.01f)

        val nanFallback = WidgetRadiusResolver.resolve(
            kind = WidgetKind.COMPACT_2X2,
            size = WidgetSizeDp(168f, 168f),
            systemOuterRadiusDp = Float.NaN,
            innerInsetDp = 10f,
        )
        assertEquals(WidgetRadiusResolver.FALLBACK_OUTER_RADIUS_DP, nanFallback.outerRadiusDp, 0.01f)
    }

    @Test
    fun `radius resolver caps 4x1 outer radius proportionally to height`() {
        val shortBarPixel = WidgetRadiusResolver.resolve(
            kind = WidgetKind.BAR_4X1,
            size = WidgetSizeDp(320f, 40f),
            systemOuterRadiusDp = 28f,
            innerInsetDp = 3f,
        )
        assertEquals(14f, shortBarPixel.outerRadiusDp, 0.01f)
        assertEquals(11f, shortBarPixel.innerRadiusDp, 0.01f)

        val regularBarPixel = WidgetRadiusResolver.resolve(
            kind = WidgetKind.BAR_4X1,
            size = WidgetSizeDp(320f, 64f),
            systemOuterRadiusDp = 28f,
            innerInsetDp = 6f,
        )
        assertEquals(22.4f, regularBarPixel.outerRadiusDp, 0.01f)
        assertEquals(16.4f, regularBarPixel.innerRadiusDp, 0.01f)

        val regularBarTightOem = WidgetRadiusResolver.resolve(
            kind = WidgetKind.BAR_4X1,
            size = WidgetSizeDp(320f, 64f),
            systemOuterRadiusDp = 16f,
            innerInsetDp = 6f,
        )
        assertEquals(16f, regularBarTightOem.outerRadiusDp, 0.01f)
        assertEquals(10f, regularBarTightOem.innerRadiusDp, 0.01f)

        val tallBarPixel = WidgetRadiusResolver.resolve(
            kind = WidgetKind.BAR_4X1,
            size = WidgetSizeDp(380f, 84f),
            systemOuterRadiusDp = 28f,
            innerInsetDp = 8f,
        )
        assertEquals(28f, tallBarPixel.outerRadiusDp, 0.01f)
        assertEquals(20f, tallBarPixel.innerRadiusDp, 0.01f)
    }

    @Test
    fun `2x2 layout tiers fit minimum bounds and fold secondary details cleanly`() {
        val minSpec = WidgetLayoutSpecResolver.resolve(
            WidgetKind.COMPACT_2X2,
            WidgetSizeDp(110f, 110f),
        ) as Compact2x2LayoutSpec
        assertEquals(WidgetDensityTier.COMPACT, minSpec.tier)
        assertTrue(minSpec.verticalChromeDp < 110f)
        assertEquals(31f, minSpec.trafficCardHeightDp, 0.01f)
        assertFalse(minSpec.showUploadRow)
        assertFalse(minSpec.showIdleSecondary)
        assertFalse(minSpec.showChart)
        assertFalse(minSpec.showGlyph)
        assertFalse(minSpec.showModeText)

        val denseHyperOs = WidgetLayoutSpecResolver.resolve(
            WidgetKind.COMPACT_2X2,
            WidgetSizeDp(136f, 140f),
        ) as Compact2x2LayoutSpec
        assertEquals(WidgetDensityTier.COMPACT, denseHyperOs.tier)
        assertTrue(denseHyperOs.trafficCardHeightDp >= 56f)
        assertTrue(denseHyperOs.showUploadRow)
        assertTrue(denseHyperOs.showChart)
        assertTrue(denseHyperOs.showGlyph)
        assertTrue(denseHyperOs.showModeText)

        val regular = WidgetLayoutSpecResolver.resolve(
            WidgetKind.COMPACT_2X2,
            WidgetSizeDp(168f, 168f),
        ) as Compact2x2LayoutSpec
        assertEquals(WidgetDensityTier.REGULAR, regular.tier)
        assertEquals(106f, regular.verticalChromeDp, 0.01f)
        assertEquals(62f, regular.trafficCardHeightDp, 0.01f)

        val spacious = WidgetLayoutSpecResolver.resolve(
            WidgetKind.COMPACT_2X2,
            WidgetSizeDp(220f, 220f),
        ) as Compact2x2LayoutSpec
        assertEquals(WidgetDensityTier.SPACIOUS, spacious.tier)
        assertTrue(spacious.downValueSp > regular.downValueSp)
        assertTrue(spacious.cardPaddingHorizontalDp > regular.cardPaddingHorizontalDp)
    }

    @Test
    fun `4x2 layout tiers adapt across narrow, landscape-short, regular, and spacious sizes`() {
        val narrowMin = WidgetLayoutSpecResolver.resolve(
            WidgetKind.WIDE_4X2,
            WidgetSizeDp(220f, 110f),
        ) as Wide4x2LayoutSpec
        assertEquals(WidgetDensityTier.COMPACT, narrowMin.tier)
        assertEquals(54f, narrowMin.verticalChromeDp, 0.01f)
        assertEquals(56f, narrowMin.trafficCardHeightDp, 0.01f)
        assertFalse(narrowMin.showModeText)
        assertTrue(narrowMin.showUploadRow)
        assertTrue(narrowMin.showChart)

        val landscapeShort = WidgetLayoutSpecResolver.resolve(
            WidgetKind.WIDE_4X2,
            WidgetSizeDp(440f, 128f),
        ) as Wide4x2LayoutSpec
        assertEquals(WidgetDensityTier.COMPACT, landscapeShort.tier)
        assertTrue(landscapeShort.showModeText)
        val expectedWidth = (440f - 16f - 6f) * (1.15f / 2.15f)
        assertEquals(expectedWidth, landscapeShort.trafficCardWidthDp, 0.1f)
        val landscapeHeader = WidgetDisplayReducer.resolveWideHeaderVisibility(
            isRunning = true,
            hasChronometerBase = true,
            tunEnabled = true,
            widthDp = 440,
        )
        assertTrue(landscapeHeader.showChronometer)
        assertTrue(landscapeHeader.showTunBadge)

        val regular = WidgetLayoutSpecResolver.resolve(
            WidgetKind.WIDE_4X2,
            WidgetSizeDp(320f, 160f),
        ) as Wide4x2LayoutSpec
        assertEquals(WidgetDensityTier.REGULAR, regular.tier)
        assertEquals(68f, regular.verticalChromeDp, 0.01f)
        assertEquals(92f, regular.trafficCardHeightDp, 0.01f)

        val spacious = WidgetLayoutSpecResolver.resolve(
            WidgetKind.WIDE_4X2,
            WidgetSizeDp(400f, 210f),
        ) as Wide4x2LayoutSpec
        assertEquals(WidgetDensityTier.SPACIOUS, spacious.tier)
        assertTrue(spacious.nodeTextSp > regular.nodeTextSp)
    }

    @Test
    fun `4x1 bar layout fits down to 40dp without overflow and adapts narrow widths`() {
        val narrowShort = WidgetLayoutSpecResolver.resolve(
            WidgetKind.BAR_4X1,
            WidgetSizeDp(220f, 40f),
        ) as Bar4x1LayoutSpec
        assertEquals(WidgetDensityTier.COMPACT, narrowShort.tier)
        assertTrue(narrowShort.minRequiredHeightDp <= 40f)
        assertFalse(narrowShort.showModeText)
        assertFalse(narrowShort.showUploadRow)
        assertFalse(narrowShort.showSparkBars)

        val wideShort = WidgetLayoutSpecResolver.resolve(
            WidgetKind.BAR_4X1,
            WidgetSizeDp(320f, 44f),
        ) as Bar4x1LayoutSpec
        assertEquals(WidgetDensityTier.COMPACT, wideShort.tier)
        assertTrue(wideShort.minRequiredHeightDp <= 44f)
        assertTrue(wideShort.showModeText)
        assertTrue(wideShort.showUploadRow)
        assertTrue(wideShort.showSparkBars)

        val regular = WidgetLayoutSpecResolver.resolve(
            WidgetKind.BAR_4X1,
            WidgetSizeDp(320f, 64f),
        ) as Bar4x1LayoutSpec
        assertEquals(WidgetDensityTier.REGULAR, regular.tier)
        assertTrue(regular.minRequiredHeightDp <= 64f)

        val spacious = WidgetLayoutSpecResolver.resolve(
            WidgetKind.BAR_4X1,
            WidgetSizeDp(380f, 80f),
        ) as Bar4x1LayoutSpec
        assertEquals(WidgetDensityTier.SPACIOUS, spacious.tier)
        assertTrue(spacious.minRequiredHeightDp <= 80f)
        assertTrue(spacious.toggleSizeDp > regular.toggleSizeDp)
    }

    @Test
    fun `chart spec matches container aspect ratio, clamps max side, and scales strokes by density`() {
        val regular4x2 = WidgetLayoutSpecResolver.resolve(
            WidgetKind.WIDE_4X2,
            WidgetSizeDp(320f, 160f),
        )
        val mdpi = WidgetChartRenderer.resolveChartSpec(regular4x2, density = 1.5f, fontScale = 1.0f)
        val xxhdpi = WidgetChartRenderer.resolveChartSpec(regular4x2, density = 3.0f, fontScale = 1.0f)
        assertNotNull(mdpi)
        assertNotNull(xxhdpi)
        val expectedRatio = regular4x2.trafficCardWidthDp / regular4x2.trafficCardHeightDp
        assertEquals(expectedRatio, xxhdpi!!.widthPx.toFloat() / xxhdpi.heightPx.toFloat(), 0.03f)
        assertTrue(xxhdpi.downStrokePx > mdpi!!.downStrokePx)
        assertTrue(xxhdpi.upStrokePx > mdpi.upStrokePx)

        val hugeWidget = WidgetLayoutSpecResolver.resolve(
            WidgetKind.WIDE_4X2,
            WidgetSizeDp(520f, 240f),
        )
        val clamped = WidgetChartRenderer.resolveChartSpec(hugeWidget, density = 3.5f, fontScale = 1.0f)
        assertNotNull(clamped)
        assertTrue(clamped!!.widthPx <= WidgetChartRenderer.MAX_CHART_SIDE_PX)
        assertTrue(clamped.heightPx <= WidgetChartRenderer.MAX_CHART_SIDE_PX)
        val hugeRatio = hugeWidget.trafficCardWidthDp / hugeWidget.trafficCardHeightDp
        assertEquals(hugeRatio, clamped.widthPx.toFloat() / clamped.heightPx.toFloat(), 0.03f)

        val squareBox = WidgetChartRenderer.resolveChartSpec(
            containerWidthDp = 120f,
            containerHeightDp = 120f,
            density = 2.0f,
            fontScale = 1.0f,
            trafficPaddingTopDp = 8f,
            downValueSp = 16f,
            upValueSp = 11.5f,
            showUploadRow = true,
        )
        assertNotNull(squareBox)
        assertEquals(1.0f, squareBox!!.widthPx.toFloat() / squareBox.heightPx.toFloat(), 0.02f)
        assertTrue(squareBox.topPaddingPx / squareBox.heightPx < 0.45f)
    }

    @Test
    fun `chart spec computes dynamic top padding from font scale and hides chart when text fills card`() {
        val dense2x2 = WidgetLayoutSpecResolver.resolve(
            WidgetKind.COMPACT_2X2,
            WidgetSizeDp(140f, 140f),
        )
        val normalFont = WidgetChartRenderer.resolveChartSpec(dense2x2, density = 3.0f, fontScale = 1.0f)
        val largeFont = WidgetChartRenderer.resolveChartSpec(dense2x2, density = 3.0f, fontScale = 1.15f)
        val hugeFont = WidgetChartRenderer.resolveChartSpec(dense2x2, density = 3.0f, fontScale = 1.5f)
        assertNotNull(normalFont)
        assertNotNull(largeFont)
        assertTrue(largeFont!!.topPaddingPx > normalFont!!.topPaddingPx)
        assertNull(hugeFont)

        val withUpload = WidgetChartRenderer.resolveChartSpec(
            containerWidthDp = 130f,
            containerHeightDp = 80f,
            density = 2.5f,
            fontScale = 1.0f,
            trafficPaddingTopDp = 6f,
            downValueSp = 15f,
            upValueSp = 11f,
            showUploadRow = true,
        )
        val withoutUpload = WidgetChartRenderer.resolveChartSpec(
            containerWidthDp = 130f,
            containerHeightDp = 80f,
            density = 2.5f,
            fontScale = 1.0f,
            trafficPaddingTopDp = 6f,
            downValueSp = 15f,
            upValueSp = 11f,
            showUploadRow = false,
        )
        assertNotNull(withUpload)
        assertNotNull(withoutUpload)
        assertTrue(withUpload!!.topPaddingPx > withoutUpload!!.topPaddingPx)

        val (sparkW, sparkH) = WidgetChartRenderer.resolveSparkBarsSize(3.0f)
        assertEquals(66, sparkW)
        assertEquals(45, sparkH)
        val (clampedSparkW, clampedSparkH) = WidgetChartRenderer.resolveSparkBarsSize(10.0f)
        assertEquals(132, clampedSparkW)
        assertEquals(90, clampedSparkH)
    }

    @Test
    fun `legacy API 24-30 layout specs use fixed XML chrome budgets to prevent overflow`() {
        val legacy2x2 = WidgetLayoutSpecResolver.resolve(
            kind = WidgetKind.COMPACT_2X2,
            size = WidgetSizeDp(136f, 140f),
            supportsDynamicLayoutParams = false,
        ) as Compact2x2LayoutSpec
        assertEquals(38f, legacy2x2.headerHeightDp, 0.01f)
        assertEquals(7f, legacy2x2.sectionGapDp, 0.01f)
        assertEquals(34f, legacy2x2.footerHeightDp, 0.01f)
        assertEquals(100f, legacy2x2.verticalChromeDp, 0.01f)
        assertEquals(40f, legacy2x2.trafficCardHeightDp, 0.01f)
        assertFalse(legacy2x2.showUploadRow)
        assertFalse(legacy2x2.showChart)
        assertNull(WidgetChartRenderer.resolveChartSpec(legacy2x2, density = 3.0f, fontScale = 1.0f))

        val legacy4x2 = WidgetLayoutSpecResolver.resolve(
            kind = WidgetKind.WIDE_4X2,
            size = WidgetSizeDp(220f, 110f),
            supportsDynamicLayoutParams = false,
        ) as Wide4x2LayoutSpec
        assertEquals(40f, legacy4x2.headerHeightDp, 0.01f)
        assertEquals(8f, legacy4x2.bodyTopGapDp, 0.01f)
        assertEquals(8f, legacy4x2.bodyColumnGapDp, 0.01f)
        assertEquals(64f, legacy4x2.verticalChromeDp, 0.01f)
        assertEquals(46f, legacy4x2.trafficCardHeightDp, 0.01f)
        val expectedLegacyWidth = (220f - 16f - 8f) * (1.15f / 2.15f)
        assertEquals(expectedLegacyWidth, legacy4x2.trafficCardWidthDp, 0.1f)

        val legacy4x1 = WidgetLayoutSpecResolver.resolve(
            kind = WidgetKind.BAR_4X1,
            size = WidgetSizeDp(220f, 40f),
            supportsDynamicLayoutParams = false,
        ) as Bar4x1LayoutSpec
        assertEquals(36f, legacy4x1.toggleSizeDp, 0.01f)
        assertEquals(32f, legacy4x1.modeButtonHeightDp, 0.01f)
        assertEquals(2f, legacy4x1.cardPaddingVerticalDp, 0.01f)
        assertEquals(40f, legacy4x1.minRequiredHeightDp, 0.01f)
    }
}
