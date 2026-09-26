package com.follow.clash

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

/**
 * HyperOS / Android 4×2 card widget. Rendering is shared with the 2×2 provider
 * via [WidgetUi]; this class only owns size-specific provider config.
 */
class WidgetProviderWide : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            WidgetUi.bind(context, appWidgetManager, appWidgetId, R.layout.widget_layout_4x2)
        }
    }
}
