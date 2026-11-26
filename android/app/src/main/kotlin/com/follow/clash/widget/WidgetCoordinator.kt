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
import java.util.concurrent.ConcurrentHashMap
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
        optionsByWidgetId: Map<Int, WidgetOptionsSnapshot> = emptyMap(),
    )

    fun onWidgetsActiveChanged(active: Boolean)

    fun onWidgetsDeleted(widgetIds: IntArray) = Unit
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

    fun onWidgetsDeleted(widgetIds: IntArray) {
        host.onWidgetsDeleted(widgetIds)
        onWidgetsChanged()
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

    fun renderKindNow(
        kind: WidgetKind,
        widgetIds: IntArray,
        optionsByWidgetId: Map<Int, WidgetOptionsSnapshot> = emptyMap(),
    ) {
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
        host.renderKind(
            kind = kind,
            widgetIds = widgetIds,
            runState = runState,
            snapshot = snapshot,
            traffic = traffic,
            history = history,
            startedAtMillis = startedAt,
            optionsByWidgetId = optionsByWidgetId,
        )
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

    internal fun onWidgetsDeleted(context: Context, widgetIds: IntArray) {
        val appContext = context.applicationContext
        val deletedIds = widgetIds.copyOf()
        scope.launch {
            runCatching {
                ensureEngine(appContext).onWidgetsDeleted(deletedIds)
            }.onFailure { error ->
                GlobalState.log("Unable to clear deleted widget state: $error")
            }
        }
    }

    internal fun onConfigChanged(context: Context) {
        val appContext = context.applicationContext
        scope.launch {
            runCatching {
                ensureEngine(appContext).refreshNow()
            }.onFailure { error ->
                GlobalState.log("Unable to refresh widgets after configuration change: $error")
            }
        }
    }

    internal fun onNightModeChanged(context: Context) {
        onConfigChanged(context)
    }

    internal suspend fun handleProviderUpdate(
        context: Context,
        kind: WidgetKind,
        widgetIds: IntArray,
        optionsByWidgetId: Map<Int, WidgetOptionsSnapshot> = emptyMap(),
    ) = withContext(serialDispatcher) {
        runCatching {
            ensureEngine(context.applicationContext).renderKindNow(kind, widgetIds, optionsByWidgetId)
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
        val tracker = WidgetConfigChangeTracker(configSignature(appContext.resources.configuration))
        appContext.registerComponentCallbacks(
            object : ComponentCallbacks {
                override fun onConfigurationChanged(newConfig: Configuration) {
                    if (!tracker.shouldRefresh(configSignature(newConfig))) return
                    onConfigChanged(appContext)
                }

                @Deprecated("Deprecated in Java")
                override fun onLowMemory() = Unit
            },
        )
    }

    private fun configSignature(config: Configuration): WidgetConfigSignature =
        WidgetConfigSignature(
            nightMode = config.uiMode and Configuration.UI_MODE_NIGHT_MASK,
            densityDpi = config.densityDpi,
            fontScale = config.fontScale,
            orientation = config.orientation,
        )
}

private class AndroidWidgetCoordinatorHost(
    private val context: Context,
    private val pluginRef: AtomicReference<WidgetPlugin?>,
    private val gson: Gson,
) : WidgetCoordinatorHost {
    private val cachedOptions = ConcurrentHashMap<Int, WidgetOptionsSnapshot>()

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
                optionsProvider = { id -> resolveOptions(manager, id, null) },
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
        optionsByWidgetId: Map<Int, WidgetOptionsSnapshot>,
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
            optionsProvider = { id -> resolveOptions(manager, id, optionsByWidgetId[id]) },
        )
    }

    override fun onWidgetsActiveChanged(active: Boolean) {
        pluginRef.get()?.notifyWidgetsActiveChanged(active)
    }

    override fun onWidgetsDeleted(widgetIds: IntArray) {
        for (id in widgetIds) {
            cachedOptions.remove(id)
        }
    }

    private fun resolveOptions(
        manager: AppWidgetManager,
        widgetId: Int,
        overrideOptions: WidgetOptionsSnapshot?,
    ): WidgetOptionsSnapshot {
        if (overrideOptions != null && overrideOptions.hasAnyDimension()) {
            cachedOptions[widgetId] = overrideOptions
            return overrideOptions
        }
        val live = WidgetRenderer.extractOptionsSnapshot(manager.getAppWidgetOptions(widgetId))
        if (live.hasAnyDimension()) {
            cachedOptions[widgetId] = live
            return live
        }
        return cachedOptions[widgetId] ?: WidgetOptionsSnapshot()
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
