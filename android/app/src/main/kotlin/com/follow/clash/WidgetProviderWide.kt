package com.follow.clash

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent

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

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "miui.appwidget.action.APPWIDGET_UPDATE") {
            val am = AppWidgetManager.getInstance(context)
            val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                ?: am.getAppWidgetIds(ComponentName(context, WidgetProviderWide::class.java))
            onUpdate(context, am, ids)
            return
        }
        super.onReceive(context, intent)
    }
}
