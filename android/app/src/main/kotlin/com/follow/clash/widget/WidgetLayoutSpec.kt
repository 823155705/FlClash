package com.follow.clash.widget

internal data class WidgetSizeDp(
    val widthDp: Float,
    val heightDp: Float,
)

internal data class WidgetOptionsSnapshot(
    val explicitSizes: List<WidgetSizeDp> = emptyList(),
    val minWidthDp: Int = 0,
    val maxWidthDp: Int = 0,
    val minHeightDp: Int = 0,
    val maxHeightDp: Int = 0,
) {
    fun hasAnyDimension(): Boolean =
        explicitSizes.any { it.widthDp.isFinite() && it.heightDp.isFinite() && it.widthDp > 0f && it.heightDp > 0f } ||
            minWidthDp > 0 ||
            maxWidthDp > 0 ||
            minHeightDp > 0 ||
            maxHeightDp > 0
}

internal enum class WidgetDensityTier {
    COMPACT,
    REGULAR,
    SPACIOUS,
}

internal data class WidgetCornerRadii(
    val outerRadiusDp: Float,
    val innerRadiusDp: Float,
)

internal object WidgetSizingResolver {
    fun defaultSize(kind: WidgetKind): WidgetSizeDp = when (kind) {
        WidgetKind.COMPACT_2X2 -> WidgetSizeDp(widthDp = 168f, heightDp = 168f)
        WidgetKind.WIDE_4X2 -> WidgetSizeDp(widthDp = 320f, heightDp = 160f)
        WidgetKind.BAR_4X1 -> WidgetSizeDp(widthDp = 320f, heightDp = 64f)
    }

    fun resolveSizes(
        kind: WidgetKind,
        options: WidgetOptionsSnapshot,
        isLandscape: Boolean,
        supportsMultiSizeRemoteViews: Boolean,
    ): List<WidgetSizeDp> {
        if (supportsMultiSizeRemoteViews) {
            val validExplicit = options.explicitSizes
                .filter { it.widthDp.isFinite() && it.heightDp.isFinite() && it.widthDp > 0f && it.heightDp > 0f }
                .distinct()
            if (validExplicit.isNotEmpty()) {
                return validExplicit
            }
        }

        val hasMinMax = options.minWidthDp > 0 ||
            options.maxWidthDp > 0 ||
            options.minHeightDp > 0 ||
            options.maxHeightDp > 0
        if (!hasMinMax) {
            return listOf(defaultSize(kind))
        }

        val fallback = defaultSize(kind)
        val portraitWidth = (options.minWidthDp.takeIf { it > 0 } ?: options.maxWidthDp.takeIf { it > 0 })
            ?.toFloat() ?: fallback.widthDp
        val portraitHeight = (options.maxHeightDp.takeIf { it > 0 } ?: options.minHeightDp.takeIf { it > 0 })
            ?.toFloat() ?: fallback.heightDp
        val landscapeWidth = (options.maxWidthDp.takeIf { it > 0 } ?: options.minWidthDp.takeIf { it > 0 })
            ?.toFloat() ?: fallback.widthDp
        val landscapeHeight = (options.minHeightDp.takeIf { it > 0 } ?: options.maxHeightDp.takeIf { it > 0 })
            ?.toFloat() ?: fallback.heightDp

        val portrait = WidgetSizeDp(widthDp = portraitWidth, heightDp = portraitHeight)
        val landscape = WidgetSizeDp(widthDp = landscapeWidth, heightDp = landscapeHeight)

        if (supportsMultiSizeRemoteViews) {
            return if (portrait == landscape) listOf(portrait) else listOf(portrait, landscape)
        }
        return listOf(if (isLandscape) landscape else portrait)
    }
}

internal object WidgetRadiusResolver {
    const val FALLBACK_OUTER_RADIUS_DP = 24f
    const val BAR_HEIGHT_RADIUS_RATIO = 0.35f
    const val BAR_MIN_OUTER_RADIUS_DP = 10f
    const val MAX_RADIUS_SHORT_SIDE_RATIO = 0.5f

    fun resolve(
        kind: WidgetKind,
        size: WidgetSizeDp,
        systemOuterRadiusDp: Float,
        innerInsetDp: Float,
    ): WidgetCornerRadii {
        val baseOuter = if (systemOuterRadiusDp.isFinite() && systemOuterRadiusDp > 0f) {
            systemOuterRadiusDp
        } else {
            FALLBACK_OUTER_RADIUS_DP
        }
        val shortSide = minOf(size.widthDp, size.heightDp).coerceAtLeast(0f)
        val geometryMax = if (shortSide > 0f) shortSide * MAX_RADIUS_SHORT_SIDE_RATIO else baseOuter
        val outer = if (kind == WidgetKind.BAR_4X1 && size.heightDp > 0f) {
            val barCap = (size.heightDp * BAR_HEIGHT_RADIUS_RATIO)
                .coerceAtLeast(BAR_MIN_OUTER_RADIUS_DP)
                .coerceAtMost(geometryMax)
            minOf(baseOuter, barCap)
        } else {
            minOf(baseOuter, geometryMax)
        }.coerceAtLeast(0f)

        val inset = innerInsetDp.coerceAtLeast(0f)
        val inner = (outer - inset).coerceIn(0f, outer)
        return WidgetCornerRadii(
            outerRadiusDp = outer,
            innerRadiusDp = inner,
        )
    }
}

internal sealed interface WidgetLayoutSpec {
    val tier: WidgetDensityTier
    val cardPaddingHorizontalDp: Float
    val cardPaddingVerticalDp: Float
    val innerRadiusInsetDp: Float
    val toggleSizeDp: Float
    val toggleIconSizeDp: Float
    val toggleProgressSizeDp: Float
    val glyphSizeDp: Float
    val showGlyph: Boolean
    val showModeText: Boolean
    val modePaddingHorizontalDp: Float
    val modeIconOnlyPaddingHorizontalDp: Float
    val modeIconGapDp: Float
    val modeTextSp: Float
    val downValueSp: Float
    val downArrowSp: Float
    val downUnitSp: Float
    val upValueSp: Float
    val upArrowSp: Float
    val upUnitSp: Float
    val idlePrimarySp: Float
    val trafficCardWidthDp: Float
    val trafficCardHeightDp: Float
    val trafficPaddingTopDp: Float
    val showUploadRow: Boolean
    val showChart: Boolean
}

internal data class Compact2x2LayoutSpec(
    override val tier: WidgetDensityTier,
    override val cardPaddingHorizontalDp: Float,
    override val cardPaddingVerticalDp: Float,
    override val toggleSizeDp: Float,
    override val toggleIconSizeDp: Float,
    override val toggleProgressSizeDp: Float,
    override val glyphSizeDp: Float,
    override val showGlyph: Boolean,
    override val showModeText: Boolean,
    override val modePaddingHorizontalDp: Float,
    override val modeIconOnlyPaddingHorizontalDp: Float,
    override val modeIconGapDp: Float,
    override val modeTextSp: Float,
    override val downValueSp: Float,
    override val downArrowSp: Float,
    override val downUnitSp: Float,
    override val upValueSp: Float,
    override val upArrowSp: Float,
    override val upUnitSp: Float,
    override val idlePrimarySp: Float,
    override val trafficCardWidthDp: Float,
    override val trafficCardHeightDp: Float,
    override val trafficPaddingTopDp: Float,
    override val showUploadRow: Boolean,
    override val showChart: Boolean,
    val headerHeightDp: Float,
    val sectionGapDp: Float,
    val footerHeightDp: Float,
    val statusBadgeHeightDp: Float,
    val statusBadgePaddingHorizontalDp: Float,
    val statusTextSp: Float,
    val trafficPaddingHorizontalDp: Float,
    val trafficPaddingBottomDp: Float,
    val idleSecondarySp: Float,
    val showIdleSecondary: Boolean,
    val modeMinWidthDp: Float,
    val nodePaddingStartDp: Float,
    val nodePaddingEndDp: Float,
    val nodeTextSp: Float,
) : WidgetLayoutSpec {
    override val innerRadiusInsetDp: Float
        get() = cardPaddingHorizontalDp

    val verticalChromeDp: Float
        get() = cardPaddingVerticalDp * 2f + headerHeightDp + sectionGapDp * 2f + footerHeightDp
}

internal data class Wide4x2LayoutSpec(
    override val tier: WidgetDensityTier,
    override val cardPaddingHorizontalDp: Float,
    override val cardPaddingVerticalDp: Float,
    override val toggleSizeDp: Float,
    override val toggleIconSizeDp: Float,
    override val toggleProgressSizeDp: Float,
    override val glyphSizeDp: Float,
    override val showGlyph: Boolean,
    override val showModeText: Boolean,
    override val modePaddingHorizontalDp: Float,
    override val modeIconOnlyPaddingHorizontalDp: Float,
    override val modeIconGapDp: Float,
    override val modeTextSp: Float,
    override val downValueSp: Float,
    override val downArrowSp: Float,
    override val downUnitSp: Float,
    override val upValueSp: Float,
    override val upArrowSp: Float,
    override val upUnitSp: Float,
    override val idlePrimarySp: Float,
    override val trafficCardWidthDp: Float,
    override val trafficCardHeightDp: Float,
    override val trafficPaddingTopDp: Float,
    override val showUploadRow: Boolean,
    override val showChart: Boolean,
    val headerHeightDp: Float,
    val bodyTopGapDp: Float,
    val bodyColumnGapDp: Float,
    val statusBadgeHeightDp: Float,
    val statusBadgePaddingHorizontalDp: Float,
    val statusTextSp: Float,
    val modeButtonHeightDp: Float,
    val trafficPaddingHorizontalDp: Float,
    val trafficPaddingBottomDp: Float,
    val idleSecondarySp: Float,
    val showIdleSecondary: Boolean,
    val nodePaddingHorizontalDp: Float,
    val nodePaddingVerticalDp: Float,
    val groupTextSp: Float,
    val nodeTextSp: Float,
) : WidgetLayoutSpec {
    override val innerRadiusInsetDp: Float
        get() = cardPaddingHorizontalDp

    val verticalChromeDp: Float
        get() = cardPaddingVerticalDp * 2f + headerHeightDp + bodyTopGapDp
}

internal data class Bar4x1LayoutSpec(
    override val tier: WidgetDensityTier,
    override val cardPaddingHorizontalDp: Float,
    override val cardPaddingVerticalDp: Float,
    override val toggleSizeDp: Float,
    override val toggleIconSizeDp: Float,
    override val toggleProgressSizeDp: Float,
    override val glyphSizeDp: Float,
    override val showGlyph: Boolean,
    override val showModeText: Boolean,
    override val modePaddingHorizontalDp: Float,
    override val modeIconOnlyPaddingHorizontalDp: Float,
    override val modeIconGapDp: Float,
    override val modeTextSp: Float,
    override val downValueSp: Float,
    override val downArrowSp: Float,
    override val downUnitSp: Float,
    override val upValueSp: Float,
    override val upArrowSp: Float,
    override val upUnitSp: Float,
    override val idlePrimarySp: Float,
    override val showUploadRow: Boolean,
    val modeButtonHeightDp: Float,
    val actionGapDp: Float,
    val statusTextSp: Float,
    val barNodeTextSp: Float,
    val showSparkBars: Boolean,
) : WidgetLayoutSpec {
    override val innerRadiusInsetDp: Float
        get() = cardPaddingVerticalDp

    override val trafficCardWidthDp: Float
        get() = 0f

    override val trafficCardHeightDp: Float
        get() = 0f

    override val trafficPaddingTopDp: Float
        get() = 0f

    override val showChart: Boolean
        get() = false

    val minRequiredHeightDp: Float
        get() = cardPaddingVerticalDp * 2f + toggleSizeDp
}

internal object WidgetLayoutSpecResolver {
    const val WIDE_TRAFFIC_WEIGHT = 1.15f
    const val WIDE_NODE_WEIGHT = 1.0f
    const val MIN_UPLOAD_TRAFFIC_HEIGHT_DP = 46f
    const val MIN_IDLE_SECONDARY_HEIGHT_DP = 42f
    const val MIN_CHART_TRAFFIC_HEIGHT_DP = 46f
    const val MIN_CHART_TRAFFIC_WIDTH_DP = 72f
    private const val LEGACY_2X2_HEADER_HEIGHT_DP = 38f
    private const val LEGACY_2X2_SECTION_GAP_DP = 7f
    private const val LEGACY_2X2_FOOTER_HEIGHT_DP = 34f
    private const val LEGACY_4X2_HEADER_HEIGHT_DP = 40f
    private const val LEGACY_4X2_BODY_TOP_GAP_DP = 8f
    private const val LEGACY_4X2_BODY_COLUMN_GAP_DP = 8f
    private const val LEGACY_4X1_TOGGLE_SIZE_DP = 36f
    private const val LEGACY_4X1_MODE_BUTTON_HEIGHT_DP = 32f
    private const val LEGACY_4X1_ACTION_GAP_DP = 8f

    fun resolve(
        kind: WidgetKind,
        size: WidgetSizeDp,
        supportsDynamicLayoutParams: Boolean = true,
    ): WidgetLayoutSpec = when (kind) {
        WidgetKind.COMPACT_2X2 -> resolveCompact2x2(size, supportsDynamicLayoutParams)
        WidgetKind.WIDE_4X2 -> resolveWide4x2(size, supportsDynamicLayoutParams)
        WidgetKind.BAR_4X1 -> resolveBar4x1(size, supportsDynamicLayoutParams)
    }

    private fun resolveCompact2x2(
        size: WidgetSizeDp,
        supportsDynamicLayoutParams: Boolean,
    ): Compact2x2LayoutSpec {
        val tier = when {
            size.heightDp < 162f || size.widthDp < 152f -> WidgetDensityTier.COMPACT
            size.heightDp >= 200f && size.widthDp >= 196f -> WidgetDensityTier.SPACIOUS
            else -> WidgetDensityTier.REGULAR
        }
        val cardPadding: Float
        val headerHeight: Float
        val sectionGap: Float
        val footerHeight: Float
        val toggleIcon: Float
        val toggleProgress: Float
        val glyphSize: Float
        val statusBadgeHeight: Float
        val statusBadgePaddingH: Float
        val statusTextSp: Float
        val trafficPaddingH: Float
        val trafficPaddingTop: Float
        val trafficPaddingBottom: Float
        val downValueSp: Float
        val downArrowSp: Float
        val downUnitSp: Float
        val upValueSp: Float
        val upArrowSp: Float
        val upUnitSp: Float
        val idlePrimarySp: Float
        val idleSecondarySp: Float
        val footerTextSp: Float
        val modePaddingH: Float
        val nodePaddingStart: Float
        val nodePaddingEnd: Float

        when (tier) {
            WidgetDensityTier.COMPACT -> {
                cardPadding = 7f
                headerHeight = 30f
                sectionGap = 4f
                footerHeight = 27f
                toggleIcon = 14f
                toggleProgress = 15f
                glyphSize = 14f
                statusBadgeHeight = 22f
                statusBadgePaddingH = 6f
                statusTextSp = 10f
                trafficPaddingH = 8f
                trafficPaddingTop = 4f
                trafficPaddingBottom = 4f
                downValueSp = 14f
                downArrowSp = 10f
                downUnitSp = 9f
                upValueSp = 10.5f
                upArrowSp = 9f
                upUnitSp = 8.5f
                idlePrimarySp = 12.5f
                idleSecondarySp = 10f
                footerTextSp = 10.5f
                modePaddingH = 5f
                nodePaddingStart = 6f
                nodePaddingEnd = 5f
            }

            WidgetDensityTier.REGULAR -> {
                cardPadding = 10f
                headerHeight = 38f
                sectionGap = 7f
                footerHeight = 34f
                toggleIcon = 17f
                toggleProgress = 18f
                glyphSize = 16f
                statusBadgeHeight = 24f
                statusBadgePaddingH = 7f
                statusTextSp = 11f
                trafficPaddingH = 10f
                trafficPaddingTop = 7f
                trafficPaddingBottom = 6f
                downValueSp = 16f
                downArrowSp = 11f
                downUnitSp = 9.5f
                upValueSp = 11.5f
                upArrowSp = 9.5f
                upUnitSp = 9f
                idlePrimarySp = 14f
                idleSecondarySp = 11f
                footerTextSp = 11f
                modePaddingH = 7f
                nodePaddingStart = 8f
                nodePaddingEnd = 6f
            }

            WidgetDensityTier.SPACIOUS -> {
                cardPadding = 12f
                headerHeight = 42f
                sectionGap = 8f
                footerHeight = 38f
                toggleIcon = 18f
                toggleProgress = 20f
                glyphSize = 18f
                statusBadgeHeight = 26f
                statusBadgePaddingH = 8f
                statusTextSp = 12f
                trafficPaddingH = 12f
                trafficPaddingTop = 9f
                trafficPaddingBottom = 8f
                downValueSp = 18f
                downArrowSp = 12f
                downUnitSp = 10f
                upValueSp = 12.5f
                upArrowSp = 10f
                upUnitSp = 9.5f
                idlePrimarySp = 15.5f
                idleSecondarySp = 12f
                footerTextSp = 12f
                modePaddingH = 8f
                nodePaddingStart = 10f
                nodePaddingEnd = 8f
            }
        }

        val effectiveHeaderHeight = if (supportsDynamicLayoutParams) headerHeight else LEGACY_2X2_HEADER_HEIGHT_DP
        val effectiveSectionGap = if (supportsDynamicLayoutParams) sectionGap else LEGACY_2X2_SECTION_GAP_DP
        val effectiveFooterHeight = if (supportsDynamicLayoutParams) footerHeight else LEGACY_2X2_FOOTER_HEIGHT_DP
        val verticalChrome = cardPadding * 2f +
            effectiveHeaderHeight +
            effectiveSectionGap * 2f +
            effectiveFooterHeight
        val trafficHeight = (size.heightDp - verticalChrome).coerceAtLeast(0f)
        val trafficWidth = (size.widthDp - cardPadding * 2f).coerceAtLeast(0f)
        val showModeText = size.widthDp >= 136f

        return Compact2x2LayoutSpec(
            tier = tier,
            cardPaddingHorizontalDp = cardPadding,
            cardPaddingVerticalDp = cardPadding,
            toggleSizeDp = effectiveHeaderHeight,
            toggleIconSizeDp = toggleIcon,
            toggleProgressSizeDp = toggleProgress,
            glyphSizeDp = glyphSize,
            showGlyph = size.widthDp >= 132f,
            showModeText = showModeText,
            modePaddingHorizontalDp = modePaddingH,
            modeIconOnlyPaddingHorizontalDp = 7f,
            modeIconGapDp = 3f,
            modeTextSp = footerTextSp,
            downValueSp = downValueSp,
            downArrowSp = downArrowSp,
            downUnitSp = downUnitSp,
            upValueSp = upValueSp,
            upArrowSp = upArrowSp,
            upUnitSp = upUnitSp,
            idlePrimarySp = idlePrimarySp,
            trafficCardWidthDp = trafficWidth,
            trafficCardHeightDp = trafficHeight,
            trafficPaddingTopDp = trafficPaddingTop,
            showUploadRow = trafficHeight >= MIN_UPLOAD_TRAFFIC_HEIGHT_DP,
            showChart = trafficHeight >= MIN_CHART_TRAFFIC_HEIGHT_DP && trafficWidth >= MIN_CHART_TRAFFIC_WIDTH_DP,
            headerHeightDp = effectiveHeaderHeight,
            sectionGapDp = effectiveSectionGap,
            footerHeightDp = effectiveFooterHeight,
            statusBadgeHeightDp = statusBadgeHeight,
            statusBadgePaddingHorizontalDp = statusBadgePaddingH,
            statusTextSp = statusTextSp,
            trafficPaddingHorizontalDp = trafficPaddingH,
            trafficPaddingBottomDp = trafficPaddingBottom,
            idleSecondarySp = idleSecondarySp,
            showIdleSecondary = trafficHeight >= MIN_IDLE_SECONDARY_HEIGHT_DP,
            modeMinWidthDp = if (showModeText) 44f else 30f,
            nodePaddingStartDp = nodePaddingStart,
            nodePaddingEndDp = nodePaddingEnd,
            nodeTextSp = footerTextSp,
        )
    }

    private fun resolveWide4x2(
        size: WidgetSizeDp,
        supportsDynamicLayoutParams: Boolean,
    ): Wide4x2LayoutSpec {
        val tier = when {
            size.heightDp < 140f || size.widthDp < 268f -> WidgetDensityTier.COMPACT
            size.heightDp >= 192f && size.widthDp >= 360f -> WidgetDensityTier.SPACIOUS
            else -> WidgetDensityTier.REGULAR
        }
        val cardPadding: Float
        val headerHeight: Float
        val bodyTopGap: Float
        val bodyColumnGap: Float
        val toggleIcon: Float
        val toggleProgress: Float
        val glyphSize: Float
        val statusBadgeHeight: Float
        val statusBadgePaddingH: Float
        val statusTextSp: Float
        val modeButtonHeight: Float
        val modePaddingH: Float
        val modeTextSp: Float
        val trafficPaddingH: Float
        val trafficPaddingTop: Float
        val trafficPaddingBottom: Float
        val downValueSp: Float
        val downArrowSp: Float
        val downUnitSp: Float
        val upValueSp: Float
        val upArrowSp: Float
        val upUnitSp: Float
        val idlePrimarySp: Float
        val idleSecondarySp: Float
        val nodePaddingH: Float
        val nodePaddingV: Float
        val groupTextSp: Float
        val nodeTextSp: Float

        when (tier) {
            WidgetDensityTier.COMPACT -> {
                cardPadding = 8f
                headerHeight = 32f
                bodyTopGap = 6f
                bodyColumnGap = 6f
                toggleIcon = 15f
                toggleProgress = 16f
                glyphSize = 16f
                statusBadgeHeight = 22f
                statusBadgePaddingH = 7f
                statusTextSp = 10.5f
                modeButtonHeight = 28f
                modePaddingH = 7f
                modeTextSp = 11f
                trafficPaddingH = 9f
                trafficPaddingTop = 5f
                trafficPaddingBottom = 4f
                downValueSp = 15f
                downArrowSp = 11f
                downUnitSp = 9.5f
                upValueSp = 10.5f
                upArrowSp = 9.5f
                upUnitSp = 9f
                idlePrimarySp = 13.5f
                idleSecondarySp = 10.5f
                nodePaddingH = 9f
                nodePaddingV = 5f
                groupTextSp = 10f
                nodeTextSp = 12.5f
            }

            WidgetDensityTier.REGULAR -> {
                cardPadding = 10f
                headerHeight = 40f
                bodyTopGap = 8f
                bodyColumnGap = 8f
                toggleIcon = 18f
                toggleProgress = 20f
                glyphSize = 18f
                statusBadgeHeight = 24f
                statusBadgePaddingH = 8f
                statusTextSp = 11.5f
                modeButtonHeight = 34f
                modePaddingH = 9f
                modeTextSp = 12f
                trafficPaddingH = 11f
                trafficPaddingTop = 8f
                trafficPaddingBottom = 6f
                downValueSp = 18f
                downArrowSp = 12f
                downUnitSp = 10f
                upValueSp = 12f
                upArrowSp = 10f
                upUnitSp = 9.5f
                idlePrimarySp = 15f
                idleSecondarySp = 11f
                nodePaddingH = 12f
                nodePaddingV = 6f
                groupTextSp = 11f
                nodeTextSp = 14f
            }

            WidgetDensityTier.SPACIOUS -> {
                cardPadding = 12f
                headerHeight = 44f
                bodyTopGap = 10f
                bodyColumnGap = 10f
                toggleIcon = 19f
                toggleProgress = 21f
                glyphSize = 20f
                statusBadgeHeight = 26f
                statusBadgePaddingH = 9f
                statusTextSp = 12f
                modeButtonHeight = 36f
                modePaddingH = 11f
                modeTextSp = 12.5f
                trafficPaddingH = 13f
                trafficPaddingTop = 10f
                trafficPaddingBottom = 8f
                downValueSp = 20f
                downArrowSp = 13f
                downUnitSp = 10.5f
                upValueSp = 13f
                upArrowSp = 10.5f
                upUnitSp = 10f
                idlePrimarySp = 16.5f
                idleSecondarySp = 12f
                nodePaddingH = 14f
                nodePaddingV = 8f
                groupTextSp = 12f
                nodeTextSp = 15.5f
            }
        }

        val effectiveHeaderHeight = if (supportsDynamicLayoutParams) headerHeight else LEGACY_4X2_HEADER_HEIGHT_DP
        val effectiveBodyTopGap = if (supportsDynamicLayoutParams) bodyTopGap else LEGACY_4X2_BODY_TOP_GAP_DP
        val effectiveBodyColumnGap = if (supportsDynamicLayoutParams) bodyColumnGap else LEGACY_4X2_BODY_COLUMN_GAP_DP
        val effectiveModeButtonHeight = if (supportsDynamicLayoutParams) {
            modeButtonHeight
        } else {
            34f
        }
        val verticalChrome = cardPadding * 2f + effectiveHeaderHeight + effectiveBodyTopGap
        val trafficHeight = (size.heightDp - verticalChrome).coerceAtLeast(0f)
        val bodyWidth = (size.widthDp - cardPadding * 2f - effectiveBodyColumnGap).coerceAtLeast(0f)
        val trafficWidth = bodyWidth * (WIDE_TRAFFIC_WEIGHT / (WIDE_TRAFFIC_WEIGHT + WIDE_NODE_WEIGHT))

        return Wide4x2LayoutSpec(
            tier = tier,
            cardPaddingHorizontalDp = cardPadding,
            cardPaddingVerticalDp = cardPadding,
            toggleSizeDp = effectiveHeaderHeight,
            toggleIconSizeDp = toggleIcon,
            toggleProgressSizeDp = toggleProgress,
            glyphSizeDp = glyphSize,
            showGlyph = true,
            showModeText = size.widthDp >= 244f,
            modePaddingHorizontalDp = modePaddingH,
            modeIconOnlyPaddingHorizontalDp = 8f,
            modeIconGapDp = 5f,
            modeTextSp = modeTextSp,
            downValueSp = downValueSp,
            downArrowSp = downArrowSp,
            downUnitSp = downUnitSp,
            upValueSp = upValueSp,
            upArrowSp = upArrowSp,
            upUnitSp = upUnitSp,
            idlePrimarySp = idlePrimarySp,
            trafficCardWidthDp = trafficWidth,
            trafficCardHeightDp = trafficHeight,
            trafficPaddingTopDp = trafficPaddingTop,
            showUploadRow = trafficHeight >= MIN_UPLOAD_TRAFFIC_HEIGHT_DP,
            showChart = trafficHeight >= MIN_CHART_TRAFFIC_HEIGHT_DP && trafficWidth >= MIN_CHART_TRAFFIC_WIDTH_DP,
            headerHeightDp = effectiveHeaderHeight,
            bodyTopGapDp = effectiveBodyTopGap,
            bodyColumnGapDp = effectiveBodyColumnGap,
            statusBadgeHeightDp = statusBadgeHeight,
            statusBadgePaddingHorizontalDp = statusBadgePaddingH,
            statusTextSp = statusTextSp,
            modeButtonHeightDp = effectiveModeButtonHeight,
            trafficPaddingHorizontalDp = trafficPaddingH,
            trafficPaddingBottomDp = trafficPaddingBottom,
            idleSecondarySp = idleSecondarySp,
            showIdleSecondary = trafficHeight >= MIN_IDLE_SECONDARY_HEIGHT_DP,
            nodePaddingHorizontalDp = nodePaddingH,
            nodePaddingVerticalDp = nodePaddingV,
            groupTextSp = groupTextSp,
            nodeTextSp = nodeTextSp,
        )
    }

    private fun resolveBar4x1(
        size: WidgetSizeDp,
        supportsDynamicLayoutParams: Boolean,
    ): Bar4x1LayoutSpec {
        val tier = when {
            size.heightDp < 54f || size.widthDp < 270f -> WidgetDensityTier.COMPACT
            size.heightDp >= 74f && size.widthDp >= 350f -> WidgetDensityTier.SPACIOUS
            else -> WidgetDensityTier.REGULAR
        }
        val isShort = size.heightDp < 46f

        val cardPaddingH: Float
        val cardPaddingV: Float
        val toggleSize: Float
        val toggleIcon: Float
        val toggleProgress: Float
        val glyphSize: Float
        val modeButtonHeight: Float
        val modePaddingH: Float
        val actionGap: Float
        val statusTextSp: Float
        val barNodeTextSp: Float
        val modeTextSp: Float
        val downValueSp: Float
        val downArrowSp: Float
        val downUnitSp: Float
        val upValueSp: Float
        val upArrowSp: Float
        val upUnitSp: Float
        val idlePrimarySp: Float

        when (tier) {
            WidgetDensityTier.COMPACT -> {
                cardPaddingH = if (size.widthDp < 250f) 9f else 10f
                cardPaddingV = if (isShort) 3f else 4f
                toggleSize = if (isShort) 32f else 36f
                toggleIcon = if (isShort) 15f else 16f
                toggleProgress = if (isShort) 16f else 18f
                glyphSize = if (isShort) 18f else 20f
                modeButtonHeight = if (isShort) 28f else 30f
                modePaddingH = 8f
                actionGap = 6f
                statusTextSp = if (isShort) 11.5f else 12f
                barNodeTextSp = if (isShort) 10.5f else 11f
                modeTextSp = 11.5f
                downValueSp = if (isShort) 12.5f else 13.5f
                downArrowSp = 10f
                downUnitSp = 9f
                upValueSp = if (isShort) 10.5f else 11f
                upArrowSp = 9.5f
                upUnitSp = 8.5f
                idlePrimarySp = if (isShort) 10f else 10.5f
            }

            WidgetDensityTier.REGULAR -> {
                cardPaddingH = 12f
                cardPaddingV = 6f
                toggleSize = 40f
                toggleIcon = 18f
                toggleProgress = 20f
                glyphSize = 22f
                modeButtonHeight = 34f
                modePaddingH = 10f
                actionGap = 8f
                statusTextSp = 13f
                barNodeTextSp = 11.5f
                modeTextSp = 12f
                downValueSp = 15f
                downArrowSp = 11f
                downUnitSp = 9.5f
                upValueSp = 12f
                upArrowSp = 10f
                upUnitSp = 9f
                idlePrimarySp = 11f
            }

            WidgetDensityTier.SPACIOUS -> {
                cardPaddingH = 14f
                cardPaddingV = 8f
                toggleSize = 44f
                toggleIcon = 19f
                toggleProgress = 21f
                glyphSize = 24f
                modeButtonHeight = 38f
                modePaddingH = 12f
                actionGap = 10f
                statusTextSp = 14f
                barNodeTextSp = 12.5f
                modeTextSp = 12.5f
                downValueSp = 16.5f
                downArrowSp = 11.5f
                downUnitSp = 10f
                upValueSp = 13f
                upArrowSp = 10.5f
                upUnitSp = 9.5f
                idlePrimarySp = 12f
            }
        }

        val effectiveCardPaddingV = if (!supportsDynamicLayoutParams && size.heightDp < 48f) {
            2f
        } else {
            cardPaddingV
        }
        val effectiveToggleSize = if (supportsDynamicLayoutParams) toggleSize else LEGACY_4X1_TOGGLE_SIZE_DP
        val effectiveModeButtonHeight = if (supportsDynamicLayoutParams) {
            modeButtonHeight
        } else {
            LEGACY_4X1_MODE_BUTTON_HEIGHT_DP
        }
        val effectiveActionGap = if (supportsDynamicLayoutParams) actionGap else LEGACY_4X1_ACTION_GAP_DP

        return Bar4x1LayoutSpec(
            tier = tier,
            cardPaddingHorizontalDp = cardPaddingH,
            cardPaddingVerticalDp = effectiveCardPaddingV,
            toggleSizeDp = effectiveToggleSize,
            toggleIconSizeDp = toggleIcon,
            toggleProgressSizeDp = toggleProgress,
            glyphSizeDp = glyphSize,
            showGlyph = true,
            showModeText = size.widthDp >= 264f,
            modePaddingHorizontalDp = modePaddingH,
            modeIconOnlyPaddingHorizontalDp = 8f,
            modeIconGapDp = 4f,
            modeTextSp = modeTextSp,
            downValueSp = downValueSp,
            downArrowSp = downArrowSp,
            downUnitSp = downUnitSp,
            upValueSp = upValueSp,
            upArrowSp = upArrowSp,
            upUnitSp = upUnitSp,
            idlePrimarySp = idlePrimarySp,
            showUploadRow = size.widthDp >= 236f,
            modeButtonHeightDp = effectiveModeButtonHeight,
            actionGapDp = effectiveActionGap,
            statusTextSp = statusTextSp,
            barNodeTextSp = barNodeTextSp,
            showSparkBars = size.widthDp >= 272f && size.heightDp >= 44f,
        )
    }
}

internal data class WidgetConfigSignature(
    val nightMode: Int,
    val densityDpi: Int,
    val fontScale: Float,
    val orientation: Int,
)

internal class WidgetConfigChangeTracker(
    initial: WidgetConfigSignature,
) {
    private var last: WidgetConfigSignature = initial

    fun shouldRefresh(next: WidgetConfigSignature): Boolean {
        if (next == last) return false
        last = next
        return true
    }
}
