package com.follow.clash.hyperos

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.follow.clash.WidgetProvider
import com.follow.clash.WidgetProviderWide
import com.follow.clash.common.GlobalState

/**
 * Prefer official-ish MIUI / HyperOS widget channels when the ROM exposes them;
 * every call is reflection-based and degrades to standard AppWidgetManager.
 *
 * This keeps non-Xiaomi devices on pure AOSP widgets while HyperOS gets the
 * faster / more reliable launcher-native update path when available.
 */
object HyperOsMiuiBridge {

    /** MIUI home / launcher package names used by stock HyperOS desktops. */
    private val MIUI_LAUNCHER_PACKAGES = listOf(
        "com.miui.home",
        "com.mi.launcher",
        "com.miui.personalassistant",
    )

    private val MIUI_UPDATE_ACTIONS = listOf(
        "miui.home.launcher.action.APPWIDGET_UPDATE",
        "com.miui.home.launcher.action.APPWIDGET_UPDATE",
        "miui.intent.action.APPWIDGET_UPDATE",
    )

    /**
     * True when MIUI runtime classes exist (even if we are not on a phone with
     * the home launcher). Used to decide whether to try OEM channels first.
     */
    fun hasMiuiRuntime(): Boolean {
        return try {
            Class.forName("miui.os.Build")
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun isHyperOsRuntime(): Boolean {
        return try {
            val cl = Class.forName("miui.os.Build")
            val field = cl.getField("IS_HYPEROS")
            field.getBoolean(null)
        } catch (_: Throwable) {
            try {
                val cl = Class.forName("miui.os.Build")
                val field = cl.getField("IS_MIUI")
                field.getBoolean(null)
            } catch (_: Throwable) {
                false
            }
        }
    }

    /**
     * Refresh every FlClash widget instance.
     *
     * Order:
     * 1. MIUI/HyperOS launcher broadcast (fastest when supported)
     * 2. AppWidgetManager partial/full update (universal fallback)
     */
    fun refreshWidgets(context: Context, chartBytes: ByteArray? = null) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)

        val deliveredViaMiui = if (hasMiuiRuntime()) {
            sendMiuiUpdateBroadcast(appContext, manager)
        } else {
            false
        }

        // Always also push through the standard path so state cannot drift
        // if the launcher ignored the OEM broadcast.
        pushStandardUpdate(appContext, manager, chartBytes)

        if (!deliveredViaMiui) {
            GlobalState.log("HyperOsMiuiBridge: standard AppWidget update used")
        }
    }

    /**
     * Ask HyperOS launcher to redraw our widgets using its own pipeline.
     * Returns true when at least one known OEM action was dispatched.
     */
    private fun sendMiuiUpdateBroadcast(
        context: Context,
        manager: AppWidgetManager,
    ): Boolean {
        var dispatched = false
        val components = listOf(
            ComponentName(context, WidgetProvider::class.java),
            ComponentName(context, WidgetProviderWide::class.java),
        )
        val ids = components.flatMap { component ->
            manager.getAppWidgetIds(component)?.toList().orEmpty()
        }
        if (ids.isEmpty()) return false

        for (packageName in MIUI_LAUNCHER_PACKAGES) {
            for (action in MIUI_UPDATE_ACTIONS) {
                try {
                    val intent = Intent(action).apply {
                        setPackage(packageName)
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids.toIntArray())
                        putExtra("appWidgetIds", ids.toIntArray())
                        // Some HyperOS builds key off component instead of ids.
                        putExtra(
                            AppWidgetManager.EXTRA_APPWIDGET_PROVIDER,
                            components.first(),
                        )
                        addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
                    }
                    context.sendBroadcast(intent)
                    dispatched = true
                } catch (_: Throwable) {
                }
            }
        }

        // HyperOS 1.x also accepts a global "widgets changed" signal.
        if (dispatched) {
            try {
                val changed = Intent("miui.home.launcher.action.WIDGETS_CHANGED").apply {
                    setPackage("com.miui.home")
                    val bundle = Bundle().apply {
                        putIntArray(
                            AppWidgetManager.EXTRA_APPWIDGET_IDS,
                            ids.toIntArray(),
                        )
                    }
                    putExtras(bundle)
                    addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
                }
                context.sendBroadcast(changed)
            } catch (_: Throwable) {
            }
        }
        return dispatched
    }

    private fun pushStandardUpdate(
        context: Context,
        manager: AppWidgetManager,
        chartBytes: ByteArray?,
    ) {
        val pairs = listOf(
            ComponentName(context, WidgetProvider::class.java) to
                com.follow.clash.R.layout.widget_layout,
            ComponentName(context, WidgetProviderWide::class.java) to
                com.follow.clash.R.layout.widget_layout_4x2,
        )
        for ((component, layoutId) in pairs) {
            val ids = manager.getAppWidgetIds(component) ?: continue
            for (id in ids) {
                com.follow.clash.WidgetUi.bind(context, manager, id, layoutId, chartBytes)
            }
        }
    }

    /**
     * Some HyperOS builds honor a provider metadata hint for lock-screen /
     * host widgets. Safe no-op when reflection target is missing.
     */
    fun applyProviderExtras(context: Context) {
        if (!hasMiuiRuntime()) return
        try {
            val clazz = Class.forName("com.miui.home.launcher.LauncherProvider")
            GlobalState.log("HyperOsMiuiBridge: MIUI LauncherProvider present (${clazz.name})")
        } catch (_: Throwable) {
        }
    }
}
