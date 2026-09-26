package com.follow.clash.hyperos

import android.content.Context

/**
 * HyperOS-like card tokens for RemoteViews (rounded, quiet, high contrast text).
 * Kept as data only so non-HyperOS devices can still use the same card look
 * without pulling in any OEM APIs.
 */
object HyperOsStyle {
    /** HyperOS system-card radius (matches preview + widget_bg drawables). */
    const val CARD_RADIUS_DP = 24

    const val LIGHT_CARD = "#FFFFFFFF"
    const val DARK_CARD = "#FF1C1C1E"
    const val LIGHT_STROKE = "#00000000"
    const val DARK_STROKE = "#00000000"

    const val TEXT_PRIMARY_LIGHT = "#FF111114"
    const val TEXT_PRIMARY_DARK = "#FFF5F5F7"
    const val TEXT_SECONDARY_LIGHT = "#8A111114"
    const val TEXT_SECONDARY_DARK = "#9EF5F5F7"
    const val DIVIDER_LIGHT = "#14111114"
    const val DIVIDER_DARK = "#1AFFFFFF"

    const val ACCENT_ON = "#FF22C55E"
    const val ACCENT_OFF = "#FFA1A1A6"

    fun isDark(context: Context): Boolean {
        val uiMode = context.resources.configuration.uiMode
        val mask = android.content.res.Configuration.UI_MODE_NIGHT_MASK
        return (uiMode and mask) == android.content.res.Configuration.UI_MODE_NIGHT_YES
    }
}
