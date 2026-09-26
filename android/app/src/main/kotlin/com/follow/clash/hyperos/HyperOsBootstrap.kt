package com.follow.clash.hyperos

import android.app.Application
import android.content.Context

/**
 * Single entry-point for the HyperOS compatibility layer.
 *
 * FlClash core only needs one call in Application.onCreate. If the device is
 * not Xiaomi/HyperOS/MIUI this stays a no-op, so upstream syncs stay cheap.
 */
object HyperOsBootstrap {
    fun init(application: Application) {
        // Detection is cheap and cached; enhance path registers heartbeat + unlock refresh.
        HyperOsRefreshScheduler.install(application)
    }

    /** Optional: call after widget state writes so ROMs re-arm promptly. */
    fun onWidgetStateChanged(context: Context) {
        HyperOsRefreshScheduler.notifyRefresh(context)
    }
}
