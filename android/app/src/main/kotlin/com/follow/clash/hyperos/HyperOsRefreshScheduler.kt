package com.follow.clash.hyperos

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.SystemClock
import com.follow.clash.WidgetRefresher
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch

/**
 * HyperOS/Miui launcher can freeze app process and drop AppWidget updates.
 * We re-draw widgets on a coarse AlarmManager heartbeat and on user present,
 * reading only WidgetDataStore — no Flutter process required.
 */
object HyperOsRefreshScheduler {
    private const val ACTION_REFRESH = "com.follow.clash.hyperos.ACTION_WIDGET_REFRESH"
    private const val INTERVAL_MS = 3 * 60_000L

    @Volatile
    private var installed = false

    fun install(context: Context) {
        if (!HyperOsCompat.shouldEnhance(context)) return
        synchronized(this) {
            if (installed) return
            installed = true
            registerUnlockReceiver(context)
            scheduleAlarm(context)
            // Immediate paint after process cold start (launcher may show stale view).
            GlobalState.launch {
                WidgetRefresher.refreshAll(context.applicationContext)
            }
        }
    }

    fun onBoot(context: Context) {
        if (!HyperOsCompat.shouldEnhance(context)) return
        scheduleAlarm(context)
        GlobalState.launch {
            WidgetRefresher.refreshAll(context.applicationContext)
        }
    }

    fun notifyRefresh(context: Context) {
        // Keep the heartbeat armed when Dart/service pushes new state.
        if (!HyperOsCompat.shouldEnhance(context)) return
        scheduleAlarm(context)
    }

    private fun scheduleAlarm(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pi = refreshPendingIntent(context)
        val triggerAt = SystemClock.elapsedRealtime() + INTERVAL_MS
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
            } else {
                @Suppress("DEPRECATION")
                am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
            }
        } catch (_: Throwable) {
            // Some ROMs restrict exact alarms; non-fatal — unlock receiver still helps.
        }
    }

    private fun refreshPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, HyperOsRefreshReceiver::class.java).apply {
            action = ACTION_REFRESH
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, 1001, intent, flags)
    }

    private fun registerUnlockReceiver(context: Context) {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(ACTION_REFRESH)
        }
        val receiver = HyperOsRefreshReceiver()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.applicationContext.registerReceiver(receiver, filter)
            }
        } catch (_: Throwable) {
        }
    }
}

/**
 * Handles unlock / screen-on / heartbeat refresh and boot re-arm.
 * Declared in the manifest so HyperOS can deliver BOOT_COMPLETED.
 */
class HyperOsRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val ctx = context ?: return
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> {
                HyperOsRefreshScheduler.onBoot(ctx)
            }

            else -> {
                if (!HyperOsCompat.shouldEnhance(ctx)) return
                // Re-arm next heartbeat then paint from persisted state.
                HyperOsRefreshScheduler.notifyRefresh(ctx)
                val app = ctx.applicationContext
                GlobalState.launch {
                    WidgetRefresher.refreshAll(app)
                }
            }
        }
    }
}
