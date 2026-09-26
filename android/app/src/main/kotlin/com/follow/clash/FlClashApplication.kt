package com.follow.clash

import android.app.Application
import android.content.Context
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch

class FlClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }

    override fun onCreate() {
        super.onCreate()
        // Widget bootstrap must never crash the host process.
        runCatching {
            com.follow.clash.hyperos.HyperOsBootstrap.init(this)
        }
        runCatching {
            GlobalState.launch {
                runCatching {
                    ServiceState.runState.collect { state ->
                        runCatching {
                            WidgetRefresher.updateRunning(
                                this@FlClashApplication,
                                state == RunState.STARTED,
                            )
                        }
                    }
                }
            }
        }
    }
}
