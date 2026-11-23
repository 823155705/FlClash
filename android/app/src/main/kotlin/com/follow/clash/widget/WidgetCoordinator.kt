package com.follow.clash.widget

import android.app.Application
import android.appwidget.AppWidgetManager
import android.content.ComponentCallbacks
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.PowerManager
import androidx.core.content.getSystemService
import com.follow.clash.RunState
import com.follow.clash.ServiceController
import com.follow.clash.ServiceState
import com.follow.clash.common.GlobalState
import com.follow.clash.common.receiveBroadcastFlow
import com.follow.clash.core.Core
import com.follow.clash.models.WidgetPendingAction
import com.follow.clash.models.WidgetSnapshot
import com.follow.clash.plugins.WidgetPlugin
import com.follow.clash.service.ServiceConfig
import com.follow.clash.service.models.Traffic
import com.follow.clash.sharedState
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicReference

internal interface WidgetCoordinatorHost {
    val runState: StateFlow<RunState>

    fun screenOnFlow(): Flow<Boolean>

    fun hasActiveWidgets(): Boolean

    fun readTraffic(): Traffic

    fun readStartedAtMillis(): Long

    fun fallbackSnapshot(): WidgetSnapshot

    fun renderAll(
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
        startedAtMillis: Long,
    )

    fun renderKind(
        kind: WidgetKind,
        widgetIds: IntArray,
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
        startedAtMillis: Long,
    )

    fun onWidgetsActiveChanged(active: Boolean)
}

internal class WidgetCoordinatorEngine(
    private val host: WidgetCoordinatorHost,
    private val store: WidgetStore,
    private val scope: CoroutineScope,
    private val pollIntervalMillis: Long = DEFAULT_POLL_INTERVAL_MILLIS,
) {
    private val activeWidgets = MutableStateFlow(false)
    private val snapshotFlow = MutableStateFlow(WidgetSnapshot())
    private val historyLock = Any()
    private val trafficHistory = ArrayDeque<Traffic>(MAX_HISTORY_SAMPLES)
    private var collectorJob: Job? = null

    fun start() {
        if (collectorJob != null) return
        snapshotFlow.value = resolveEffectiveSnapshot()
        activeWidgets.value = host.hasActiveWidgets()
        collectorJob = scope.launch {
            activeWidgets.collectLatest { active ->
                if (!active) {
                    clearHistory()
                    return@collectLatest
                }
                combine(
                    host.runState,
                    snapshotFlow,
                    host.screenOnFlow(),
                ) { runState, snapshot, screenOn ->
                    Triple(runState, snapshot, screenOn)
                }.collectLatest { (runState, snapshot, screenOn) ->
                    if (runState != RunState.STARTED) {
                        clearHistory()
                        host.renderAll(runState, snapshot, ZERO_TRAFFIC, emptyList(), 0L)
                        return@collectLatest
                    }
                    val current = if (screenOn) recordSample(host.readTraffic()) else ZERO_TRAFFIC
                    host.renderAll(
                        runState,
                        snapshot,
                        current,
                        copyHistory(),
                        host.readStartedAtMillis(),
                    )
                    if (!screenOn) return@collectLatest
                    while (true) {
                        delay(pollIntervalMillis)
                        val sample = recordSample(host.readTraffic())
                        host.renderAll(
                            runState,
                            snapshot,
                            sample,
                            copyHistory(),
                            host.readStartedAtMillis(),
                        )
                    }
                }
            }
        }
    }

    fun stop() {
        collectorJob?.cancel()
        collectorJob = null
        clearHistory()
    }

    fun hasActiveWidgets(): Boolean {
        val current = host.hasActiveWidgets()
        updateActiveState(current)
        return current
    }

    fun onWidgetsChanged() {
        updateActiveState(host.hasActiveWidgets())
    }

    fun updateSnapshot(snapshot: WidgetSnapshot) {
        val normalized = snapshot.normalized()
        store.saveSnapshot(normalized)
        snapshotFlow.value = normalized
    }

    fun currentSnapshot(): WidgetSnapshot = resolveEffectiveSnapshot()

    fun enqueuePendingAction(action: WidgetPendingAction) {
        store.savePendingAction(action)
    }

    fun consumePendingAction(): WidgetPendingAction? = store.consumePendingAction()

    fun renderKindNow(kind: WidgetKind, widgetIds: IntArray) {
        updateActiveState(host.hasActiveWidgets())
        if (widgetIds.isEmpty()) return
        val runState = host.runState.value
        val snapshot = resolveEffectiveSnapshot()
        snapshotFlow.value = snapshot
        val traffic = if (runState == RunState.STARTED) {
            recordSample(host.readTraffic())
        } else {
            ZERO_TRAFFIC
        }
        val history = if (runState == RunState.STARTED) copyHistory() else emptyList()
        val startedAt = if (runState == RunState.STARTED) host.readStartedAtMillis() else 0L
        host.renderKind(kind, widgetIds, runState, snapshot, traffic, history, startedAt)
    }

    fun refreshNow() {
        val active = host.hasActiveWidgets()
        updateActiveState(active)
        if (!active) return
        val runState = host.runState.value
        val snapshot = resolveEffectiveSnapshot()
        snapshotFlow.value = snapshot
        val history = if (runState == RunState.STARTED) copyHistory() else emptyList()
        val traffic = if (runState == RunState.STARTED) {
            history.lastOrNull() ?: recordSample(host.readTraffic())
        } else {
            ZERO_TRAFFIC
        }
        val startedAt = if (runState == RunState.STARTED) host.readStartedAtMillis() else 0L
        host.renderAll(
            runState,
            snapshot,
            traffic,
            if (runState == RunState.STARTED) copyHistory() else emptyList(),
            startedAt,
        )
    }

    private fun resolveEffectiveSnapshot(): WidgetSnapshot =
        if (store.hasSavedSnapshot()) store.loadSnapshot() else host.fallbackSnapshot()

    private fun updateActiveState(active: Boolean) {
        val previous = activeWidgets.value
        activeWidgets.value = active
        if (previous != active) {
            host.onWidgetsActiveChanged(active)
        }
    }

    private fun recordSample(sample: Traffic): Traffic = synchronized(historyLock) {
        val sanitized = Traffic(
            up = sample.up.coerceAtLeast(0L),
            down = sample.down.coerceAtLeast(0L),
        )
        if (trafficHistory.size >= MAX_HISTORY_SAMPLES) {
            trafficHistory.removeFirst()
        }
        trafficHistory.addLast(sanitized)
        sanitized
    }

    private fun copyHistory(): List<Traffic> = synchronized(historyLock) {
        trafficHistory.toList()
    }

    private fun clearHistory() = synchronized(historyLock) {
        trafficHistory.clear()
    }

    companion object {
        const val DEFAULT_POLL_INTERVAL_MILLIS = 2_000L
        const val MAX_HISTORY_SAMPLES = 20
        val ZERO_TRAFFIC = Traffic(0L, 0L)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
object WidgetCoordinator {
    private val serialDispatcher: CoroutineDispatcher = Dispatchers.IO.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + serialDispatcher)
    private val pluginRef = AtomicReference<WidgetPlugin?>(null)
    private val gson = Gson()

    @Volatile
    private var engine: WidgetCoordinatorEngine? = null
    private var configCallbacksRegistered = false

    fun install(application: Application) {
        ensureEngine(application)
    }

    internal fun attachPlugin(plugin: WidgetPlugin) {
        pluginRef.set(plugin)
        scope.launch {
            val active = runCatching { ensureEngine(GlobalState.application).hasActiveWidgets() }
                .getOrDefault(false)
            plugin.notifyWidgetsActiveChanged(active)
        }
    }

    internal fun detachPlugin(plugin: WidgetPlugin) {
        pluginRef.compareAndSet(plugin, null)
    }

    internal fun updateSnapshot(snapshot: WidgetSnapshot) {
        scope.launch {
            runCatching {
                ensureEngine(GlobalState.application).updateSnapshot(snapshot)
            }.onFailure { error ->
                GlobalState.log("Unable to update widget snapshot: $error")
            }
        }
    }

    internal fun hasActiveWidgets(): Boolean = runCatching {
        ensureEngine(GlobalState.application).hasActiveWidgets()
    }.getOrDefault(false)

    internal fun currentSnapshot(): WidgetSnapshot = runCatching {
        ensureEngine(GlobalState.application).currentSnapshot()
    }.getOrDefault(WidgetSnapshot())

    internal fun enqueuePendingAction(action: WidgetPendingAction) {
        runCatching {
            ensureEngine(GlobalState.application).enqueuePendingAction(action)
        }.onFailure { error ->
            GlobalState.log("Unable to enqueue widget pending action: $error")
        }
    }

    internal fun consumePendingAction(): WidgetPendingAction? = runCatching {
        ensureEngine(GlobalState.application).consumePendingAction()
    }.getOrNull()

    internal fun dispatchCycleMode(): Boolean {
        val plugin = pluginRef.get() ?: return false
        plugin.dispatchCycleMode()
        return true
    }

    internal fun dispatchSelectProxy(groupName: String, proxyName: String): Boolean {
        val plugin = pluginRef.get() ?: return false
        plugin.dispatchSelectProxy(groupName, proxyName)
        return true
    }

    internal fun onWidgetsChanged(context: Context) {
        val appContext = context.applicationContext
        scope.launch {
            runCatching {
                ensureEngine(appContext).onWidgetsChanged()
            }.onFailure { error ->
                GlobalState.log("Unable to refresh active widget state: $error")
            }
        }
    }

    internal fun onNightModeChanged(context: Context) {
        val appContext = context.applicationContext
        scope.launch {
            runCatching {
                ensureEngine(appContext).refreshNow()
            }.onFailure { error ->
                GlobalState.log("Unable to refresh widgets after theme change: $error")
            }
        }
    }

    internal suspend fun handleProviderUpdate(
        context: Context,
        kind: WidgetKind,
        widgetIds: IntArray,
    ) = withContext(serialDispatcher) {
        runCatching {
            ensureEngine(context.applicationContext).renderKindNow(kind, widgetIds)
        }.onFailure { error ->
            GlobalState.log("Unable to render widget update: $error")
        }
    }

    private fun ensureEngine(context: Context): WidgetCoordinatorEngine {
        engine?.let { return it }
        return synchronized(this) {
            engine?.let { return@synchronized it }
            val appContext = context.applicationContext
            registerConfigCallbacks(appContext)
            val store = WidgetStore(SharedPrefsWidgetStorage(appContext), gson)
            val host = AndroidWidgetCoordinatorHost(appContext, pluginRef, gson)
            WidgetCoordinatorEngine(host, store, scope).also { created ->
                engine = created
                created.start()
            }
        }
    }

    private fun registerConfigCallbacks(appContext: Context) {
        if (configCallbacksRegistered) return
        configCallbacksRegistered = true
        var lastNightMode = appContext.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        appContext.registerComponentCallbacks(
            object : ComponentCallbacks {
                override fun onConfigurationChanged(newConfig: Configuration) {
                    val nightMode = newConfig.uiMode and Configuration.UI_MODE_NIGHT_MASK
                    if (nightMode == lastNightMode) return
                    lastNightMode = nightMode
                    onNightModeChanged(appContext)
                }

                @Deprecated("Deprecated in Java")
                override fun onLowMemory() = Unit
            },
        )
    }
}

private class AndroidWidgetCoordinatorHost(
    private val context: Context,
    private val pluginRef: AtomicReference<WidgetPlugin?>,
    private val gson: Gson,
) : WidgetCoordinatorHost {
    override val runState: StateFlow<RunState>
        get() = ServiceState.runState

    override fun screenOnFlow(): Flow<Boolean> =
        // SystemUI sends USER_PRESENT from another app, so the receiver must be exported.
        context.receiveBroadcastFlow(exported = true) {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }.map { intent ->
            intent.action != Intent.ACTION_SCREEN_OFF
        }.onStart {
            emit(isScreenInteractive())
        }

    override fun hasActiveWidgets(): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return PROVIDERS.any { (_, cls) ->
            manager.getAppWidgetIds(ComponentName(context, cls)).isNotEmpty()
        }
    }

    override fun readTraffic(): Traffic = runCatching {
        val onlyProxy = ServiceConfig.notificationParams.value.onlyStatisticsProxy
        gson.fromJson(Core.getTraffic(onlyProxy), Traffic::class.java)
    }.getOrNull() ?: WidgetCoordinatorEngine.ZERO_TRAFFIC

    override fun readStartedAtMillis(): Long = ServiceController.runtime?.startedAtMillis ?: 0L

    override fun fallbackSnapshot(): WidgetSnapshot {
        val shared = runCatching { (context as? Application)?.sharedState }.getOrNull()
            ?: return WidgetSnapshot()
        return WidgetSnapshot(
            hasProfile = shared.setupParams != null,
            profileName = shared.currentProfileName,
            tunEnabled = shared.vpnOptions?.enable == true,
        )
    }

    override fun renderAll(
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
        startedAtMillis: Long,
    ) {
        val manager = AppWidgetManager.getInstance(context)
        for ((kind, cls) in PROVIDERS) {
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            WidgetRenderer.bind(
                context = context,
                manager = manager,
                widgetIds = ids,
                kind = kind,
                runState = runState,
                snapshot = snapshot,
                traffic = traffic,
                history = history,
                startedAtMillis = startedAtMillis,
            )
        }
    }

    override fun renderKind(
        kind: WidgetKind,
        widgetIds: IntArray,
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
        startedAtMillis: Long,
    ) {
        val manager = AppWidgetManager.getInstance(context)
        WidgetRenderer.bind(
            context = context,
            manager = manager,
            widgetIds = widgetIds,
            kind = kind,
            runState = runState,
            snapshot = snapshot,
            traffic = traffic,
            history = history,
            startedAtMillis = startedAtMillis,
        )
    }

    override fun onWidgetsActiveChanged(active: Boolean) {
        pluginRef.get()?.notifyWidgetsActiveChanged(active)
    }

    private fun isScreenInteractive(): Boolean =
        context.getSystemService<PowerManager>()?.isInteractive ?: true

    private companion object {
        val PROVIDERS = listOf(
            WidgetKind.COMPACT_2X2 to WidgetProvider::class.java,
            WidgetKind.WIDE_4X2 to WidgetProviderWide::class.java,
            WidgetKind.BAR_4X1 to WidgetProviderCompact::class.java,
        )
    }
}
