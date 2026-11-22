package com.follow.clash.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.follow.clash.common.BroadcastLease
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch

abstract class BaseWidgetProvider internal constructor(
    private val kind: WidgetKind,
) : AppWidgetProvider() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetCoordinator.onWidgetsChanged(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetCoordinator.onWidgetsChanged(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetCoordinator.onWidgetsChanged(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        dispatchAsyncUpdate(context, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_MIUI_APPWIDGET_UPDATE) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                ?: manager.getAppWidgetIds(ComponentName(context, javaClass))
            dispatchAsyncUpdate(context, ids)
            return
        }
        super.onReceive(context, intent)
    }

    private fun dispatchAsyncUpdate(context: Context, widgetIds: IntArray) {
        val pendingResult = goAsync()
        val lease = BroadcastLease { pendingResult.finish() }
        val timeout = Runnable {
            lease.release { GlobalState.log("Widget update broadcast timed out: ${javaClass.simpleName}") }
        }
        mainHandler.postDelayed(timeout, BROADCAST_TIMEOUT_MILLIS)
        GlobalState.launch {
            try {
                WidgetCoordinator.handleProviderUpdate(context, kind, widgetIds)
            } finally {
                mainHandler.removeCallbacks(timeout)
                lease.release()
            }
        }
    }

    private companion object {
        const val ACTION_MIUI_APPWIDGET_UPDATE = "miui.appwidget.action.APPWIDGET_UPDATE"
        const val BROADCAST_TIMEOUT_MILLIS = 9_000L
        val mainHandler = Handler(Looper.getMainLooper())
    }
}
