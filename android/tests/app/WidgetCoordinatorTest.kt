package com.follow.clash.widget

import com.follow.clash.RunState
import com.follow.clash.models.WidgetSnapshot
import com.follow.clash.service.models.Traffic
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private data class RenderRecord(
    val runState: RunState,
    val snapshot: WidgetSnapshot,
    val traffic: Traffic,
    val historySize: Int,
    val startedAtMillis: Long,
)

private class FakeCoordinatorHost(
    initialRunState: RunState = RunState.STOPPED,
    initialActive: Boolean = false,
    initialScreenOn: Boolean = true,
) : WidgetCoordinatorHost {
    override val runState = MutableStateFlow(initialRunState)
    val screenState = MutableStateFlow(initialScreenOn)
    var active = initialActive
    var fallback = WidgetSnapshot()
    var nextTraffic = Traffic(up = 1024L, down = 2048L)
    var startedAtMillis = 1_700_000_000_000L

    var trafficReads = 0
    var screenSubscriptions = 0
    var activeScreenSubscriptions = 0
    val activeNotifications = mutableListOf<Boolean>()
    val renders = mutableListOf<RenderRecord>()
    val kindRenders = mutableListOf<Pair<WidgetKind, List<Int>>>()

    override fun screenOnFlow(): Flow<Boolean> = screenState
        .onStart {
            screenSubscriptions++
            activeScreenSubscriptions++
        }
        .onCompletion {
            activeScreenSubscriptions--
        }

    override fun hasActiveWidgets(): Boolean = active

    override fun readTraffic(): Traffic {
        trafficReads++
        return nextTraffic
    }

    override fun readStartedAtMillis(): Long = startedAtMillis

    override fun fallbackSnapshot(): WidgetSnapshot = fallback

    override fun renderAll(
        runState: RunState,
        snapshot: WidgetSnapshot,
        traffic: Traffic,
        history: List<Traffic>,
        startedAtMillis: Long,
    ) {
        renders += RenderRecord(runState, snapshot, traffic, history.size, startedAtMillis)
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
        kindRenders += kind to widgetIds.toList()
    }

    override fun onWidgetsActiveChanged(active: Boolean) {
        activeNotifications += active
    }
}

private class InMemoryStorage : WidgetKeyValueStorage {
    private val values = LinkedHashMap<String, String>()

    override fun getString(key: String): String? = values[key]

    override fun putString(key: String, value: String) {
        values[key] = value
    }

    override fun remove(key: String) {
        values.remove(key)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class WidgetCoordinatorTest {
    @Test
    fun `visual status derives all six states from RunState and snapshot`() {
        val withProfile = WidgetSnapshot(hasProfile = true)
        val noProfile = WidgetSnapshot(hasProfile = false)
        val suspended = WidgetSnapshot(hasProfile = true, suspended = true)

        assertEquals(
            WidgetVisualStatus.NO_PROFILE,
            WidgetDisplayReducer.deriveStatus(RunState.STOPPED, noProfile),
        )
        assertEquals(
            WidgetVisualStatus.STOPPED,
            WidgetDisplayReducer.deriveStatus(RunState.STOPPED, withProfile),
        )
        assertEquals(
            WidgetVisualStatus.SUSPENDED,
            WidgetDisplayReducer.deriveStatus(RunState.STOPPED, suspended),
        )
        assertEquals(
            WidgetVisualStatus.STARTING,
            WidgetDisplayReducer.deriveStatus(RunState.STARTING, suspended),
        )
        assertEquals(
            WidgetVisualStatus.STARTED,
            WidgetDisplayReducer.deriveStatus(RunState.STARTED, suspended),
        )
        assertEquals(
            WidgetVisualStatus.STOPPING,
            WidgetDisplayReducer.deriveStatus(RunState.STOPPING, withProfile),
        )
    }

    @Test
    fun `speed formatting uses 1024 units and clamps negative values`() {
        assertEquals("0 B/s", WidgetDisplayReducer.formatSpeed(-50L))
        assertEquals("512 B/s", WidgetDisplayReducer.formatSpeed(512L))
        assertEquals("1.5 KB/s", WidgetDisplayReducer.formatSpeed(1536L))
        assertEquals("2.0 MB/s", WidgetDisplayReducer.formatSpeed(2L * 1024L * 1024L))
        assertEquals("1.0 GB/s", WidgetDisplayReducer.formatSpeed(1024L * 1024L * 1024L))

        assertEquals("0B", WidgetDisplayReducer.formatSpeedCompact(-50L))
        assertEquals("512B", WidgetDisplayReducer.formatSpeedCompact(512L))
        assertEquals("1.5K", WidgetDisplayReducer.formatSpeedCompact(1536L))
        assertEquals("2.0M", WidgetDisplayReducer.formatSpeedCompact(2L * 1024L * 1024L))
        assertEquals("1.0G", WidgetDisplayReducer.formatSpeedCompact(1024L * 1024L * 1024L))
    }

    @Test
    fun `speed parts split numeric value and unit for full and compact layouts`() {
        assertEquals(SpeedParts("0", "B/s"), WidgetDisplayReducer.formatSpeedParts(-1L))
        assertEquals(SpeedParts("512", "B/s"), WidgetDisplayReducer.formatSpeedParts(512L))
        assertEquals(SpeedParts("1.5", "KB/s"), WidgetDisplayReducer.formatSpeedParts(1536L))
        assertEquals(
            SpeedParts("12.4", "MB/s"),
            WidgetDisplayReducer.formatSpeedParts((12.4 * 1024 * 1024).toLong()),
        )

        assertEquals(SpeedParts("0", "B"), WidgetDisplayReducer.formatSpeedCompactParts(-1L))
        assertEquals(SpeedParts("512", "B"), WidgetDisplayReducer.formatSpeedCompactParts(512L))
        assertEquals(SpeedParts("1.5", "K"), WidgetDisplayReducer.formatSpeedCompactParts(1536L))
        assertEquals(
            SpeedParts("12.4", "M"),
            WidgetDisplayReducer.formatSpeedCompactParts((12.4 * 1024 * 1024).toLong()),
        )

        val snapshot = WidgetSnapshot(hasProfile = true, mode = "rule", nodeName = "HK-01")
        val traffic = Traffic(up = 1536L, down = 2L * 1024L * 1024L)
        val wide = WidgetDisplayReducer.reduce(WidgetKind.WIDE_4X2, RunState.STARTED, snapshot, traffic) { it }
        assertEquals(SpeedParts("2.0", "MB/s"), wide.downParts)
        assertEquals(SpeedParts("1.5", "KB/s"), wide.upParts)

        val compact = WidgetDisplayReducer.reduce(WidgetKind.COMPACT_2X2, RunState.STARTED, snapshot, traffic) { it }
        assertEquals(SpeedParts("2.0", "MB/s"), compact.downParts)
        assertEquals(SpeedParts("1.5", "KB/s"), compact.upParts)

        val bar = WidgetDisplayReducer.reduce(WidgetKind.BAR_4X1, RunState.STARTED, snapshot, traffic) { it }
        assertEquals(SpeedParts("2.0", "M"), bar.downParts)
        assertEquals(SpeedParts("1.5", "K"), bar.upParts)
    }

    @Test
    fun `spark bars hide when idle and normalize last four samples with breathing floor`() {
        assertNull(WidgetChartRenderer.computeSparkBarRatios(emptyList()))
        assertNull(WidgetChartRenderer.computeSparkBarRatios(listOf(Traffic(0L, 0L), Traffic(0L, 0L))))
        assertNull(
            WidgetChartRenderer.computeSparkBarRatios(
                listOf(
                    Traffic(up = 500L, down = 1000L),
                    Traffic(0L, 0L),
                    Traffic(0L, 0L),
                    Traffic(0L, 0L),
                    Traffic(0L, 0L),
                ),
            ),
        )
        assertNull(
            WidgetChartRenderer.renderSparkBars(
                listOf(Traffic(100L, 200L)),
                0xFF007AFF.toInt(),
                0xFF76ADF2.toInt(),
                false,
                width = 0,
                height = WidgetChartRenderer.SPARK_BARS_HEIGHT,
            ),
        )

        val single = WidgetChartRenderer.computeSparkBarRatios(listOf(Traffic(up = 200L, down = 800L)))
        assertNotNull(single)
        assertEquals(4, single!!.size)
        assertEquals(0.25f, single[0], 0.001f)
        assertEquals(0.25f, single[1], 0.001f)
        assertEquals(0.25f, single[2], 0.001f)
        assertEquals(1.0f, single[3], 0.001f)

        val history = listOf(
            Traffic(up = 0L, down = 1000L),
            Traffic(up = 0L, down = 0L),
            Traffic(up = 100L, down = 150L),
            Traffic(up = 250L, down = 250L),
            Traffic(up = 200L, down = 800L),
        )
        val ratios = WidgetChartRenderer.computeSparkBarRatios(history)!!
        assertEquals(4, ratios.size)
        assertEquals(0.25f, ratios[0], 0.001f)
        assertEquals(0.4375f, ratios[1], 0.001f)
        assertEquals(0.625f, ratios[2], 0.001f)
        assertEquals(1.0f, ratios[3], 0.001f)
    }

    @Test
    fun `chronometer base converts wall time to elapsed realtime and header adapts to width`() {
        assertNull(WidgetDisplayReducer.computeChronometerBase(0L, 1_700_000_065_000L, 500_000L))
        assertNull(WidgetDisplayReducer.computeChronometerBase(-10L, 1_700_000_065_000L, 500_000L))
        assertEquals(
            435_000L,
            WidgetDisplayReducer.computeChronometerBase(
                startedAtWallMillis = 1_700_000_000_000L,
                nowWallMillis = 1_700_000_065_000L,
                nowElapsedRealtimeMillis = 500_000L,
            ),
        )
        assertEquals(
            500_000L,
            WidgetDisplayReducer.computeChronometerBase(
                startedAtWallMillis = 1_700_000_100_000L,
                nowWallMillis = 1_700_000_065_000L,
                nowElapsedRealtimeMillis = 500_000L,
            ),
        )

        assertEquals(
            WideHeaderVisibility(showChronometer = false, showTunBadge = false),
            WidgetDisplayReducer.resolveWideHeaderVisibility(
                isRunning = false,
                hasChronometerBase = true,
                tunEnabled = true,
                widthDp = 412,
            ),
        )
        assertEquals(
            WideHeaderVisibility(showChronometer = false, showTunBadge = false),
            WidgetDisplayReducer.resolveWideHeaderVisibility(
                isRunning = true,
                hasChronometerBase = true,
                tunEnabled = true,
                widthDp = 250,
            ),
        )
        assertEquals(
            WideHeaderVisibility(showChronometer = true, showTunBadge = false),
            WidgetDisplayReducer.resolveWideHeaderVisibility(
                isRunning = true,
                hasChronometerBase = true,
                tunEnabled = true,
                widthDp = 290,
            ),
        )
        assertEquals(
            WideHeaderVisibility(showChronometer = true, showTunBadge = true),
            WidgetDisplayReducer.resolveWideHeaderVisibility(
                isRunning = true,
                hasChronometerBase = true,
                tunEnabled = true,
                widthDp = 412,
            ),
        )
    }

    @Test
    fun `reducer disables node selection in direct mode and no-profile state`() {
        val base = WidgetSnapshot(
            hasProfile = true,
            profileName = "Sub",
            mode = "direct",
            groupName = "Proxy",
            nodeName = "HK-01",
            canSelectProxy = true,
            proxyNames = listOf("HK-01", "JP-01"),
            labels = mapOf("direct" to "Direct", "modeDirect" to "Direct"),
        )
        val directModel = WidgetDisplayReducer.reduce(
            kind = WidgetKind.WIDE_4X2,
            runState = RunState.STARTED,
            snapshot = base,
            traffic = Traffic(up = 1024L, down = 2048L),
        ) { it }

        assertFalse(directModel.canSelectProxy)
        assertEquals("Direct", directModel.nodeLabel)
        assertEquals("↓ 2.0 KB/s", directModel.primaryLine)
        assertEquals("↑ 1.0 KB/s", directModel.secondaryLine)

        val barRunning = WidgetDisplayReducer.reduce(
            kind = WidgetKind.BAR_4X1,
            runState = RunState.STARTED,
            snapshot = base.copy(mode = "rule"),
            traffic = Traffic(up = 1024L, down = 2048L),
        ) { it }
        assertTrue(barRunning.canSelectProxy)
        assertEquals("↓2.0K ↑1.0K", barRunning.primaryLine)

        val compactRunning = WidgetDisplayReducer.reduce(
            kind = WidgetKind.COMPACT_2X2,
            runState = RunState.STARTED,
            snapshot = base.copy(mode = "rule"),
            traffic = Traffic(up = 1024L, down = 2048L),
        ) { it }
        assertTrue(WidgetKind.COMPACT_2X2.hasTrafficCard)
        assertTrue(WidgetKind.WIDE_4X2.hasTrafficCard)
        assertFalse(WidgetKind.BAR_4X1.hasTrafficCard)
        assertTrue(compactRunning.canSelectProxy)
        assertEquals("↓ 2.0 KB/s", compactRunning.primaryLine)
        assertEquals("↑ 1.0 KB/s", compactRunning.secondaryLine)
        assertEquals("HK-01", compactRunning.nodeLabel)

        val compactStopped = WidgetDisplayReducer.reduce(
            kind = WidgetKind.COMPACT_2X2,
            runState = RunState.STOPPED,
            snapshot = base.copy(mode = "rule"),
            traffic = Traffic(0L, 0L),
        ) { key -> if (key == "tapToStart") "Tap to start" else key }
        assertEquals("Sub", compactStopped.primaryLine)
        assertEquals("Tap to start", compactStopped.secondaryLine)
        assertTrue(compactStopped.canSelectProxy)

        val compactStoppedNoName = WidgetDisplayReducer.reduce(
            kind = WidgetKind.COMPACT_2X2,
            runState = RunState.STOPPED,
            snapshot = base.copy(mode = "rule", profileName = ""),
            traffic = Traffic(0L, 0L),
        ) { key -> if (key == "tapToStart") "Tap to start" else key }
        assertEquals("Tap to start", compactStoppedNoName.primaryLine)
        assertEquals("", compactStoppedNoName.secondaryLine)

        val noProfileFallback: (String) -> String = { key ->
            when (key) {
                "noProfile" -> "No profile"
                "openApp" -> "Open FlClash"
                "appName" -> "FlClash"
                else -> key
            }
        }
        val noProfile4x2 = WidgetDisplayReducer.reduce(
            kind = WidgetKind.WIDE_4X2,
            runState = RunState.STOPPED,
            snapshot = WidgetSnapshot(hasProfile = false),
            traffic = Traffic(0L, 0L),
            fallbackLabel = noProfileFallback,
        )
        assertFalse(noProfile4x2.canSelectProxy)
        assertEquals("No profile", noProfile4x2.statusLabel)
        assertEquals("Open FlClash", noProfile4x2.primaryLine)
        assertEquals("FlClash", noProfile4x2.secondaryLine)
        assertEquals("FlClash", noProfile4x2.groupLabel)
        assertEquals("—", noProfile4x2.nodeLabel)

        val noProfile4x1 = WidgetDisplayReducer.reduce(
            kind = WidgetKind.BAR_4X1,
            runState = RunState.STOPPED,
            snapshot = WidgetSnapshot(hasProfile = false),
            traffic = Traffic(0L, 0L),
            fallbackLabel = noProfileFallback,
        )
        assertEquals("No profile", noProfile4x1.statusLabel)
        assertEquals("Open FlClash", noProfile4x1.primaryLine)

        val noProfile2x2 = WidgetDisplayReducer.reduce(
            kind = WidgetKind.COMPACT_2X2,
            runState = RunState.STOPPED,
            snapshot = WidgetSnapshot(hasProfile = false),
            traffic = Traffic(0L, 0L),
            fallbackLabel = noProfileFallback,
        )
        assertFalse(noProfile2x2.canSelectProxy)
        assertEquals("No profile", noProfile2x2.statusLabel)
        assertEquals("Open FlClash", noProfile2x2.primaryLine)
        assertEquals("FlClash", noProfile2x2.secondaryLine)
        assertEquals("—", noProfile2x2.nodeLabel)
    }

    @Test
    fun `chart renderer skips empty, single-sample, zero-peak, or invalid bounds`() {
        assertEquals(null, WidgetChartRenderer.render(emptyList(), 0xFF007AFF.toInt(), 0xFF84B9F7.toInt(), false))
        assertEquals(
            null,
            WidgetChartRenderer.render(
                listOf(Traffic(up = 100L, down = 200L)),
                0xFF007AFF.toInt(),
                0xFF84B9F7.toInt(),
                false,
                width = WidgetChartRenderer.COMPACT_WIDTH,
                height = WidgetChartRenderer.COMPACT_HEIGHT,
            ),
        )
        assertEquals(
            null,
            WidgetChartRenderer.render(
                listOf(Traffic(0L, 0L), Traffic(0L, 0L)),
                0xFF007AFF.toInt(),
                0xFF84B9F7.toInt(),
                true,
                width = WidgetChartRenderer.COMPACT_WIDTH,
                height = WidgetChartRenderer.COMPACT_HEIGHT,
            ),
        )
        assertEquals(
            null,
            WidgetChartRenderer.render(
                listOf(Traffic(100L, 200L), Traffic(300L, 400L)),
                0xFF007AFF.toInt(),
                0xFF84B9F7.toInt(),
                false,
                width = 0,
                height = WidgetChartRenderer.COMPACT_HEIGHT,
            ),
        )
    }

    @Test
    fun `zero polling and zero screen receivers when no widgets exist`() = runTest(StandardTestDispatcher()) {
        val host = FakeCoordinatorHost(
            initialRunState = RunState.STARTED,
            initialActive = false,
            initialScreenOn = true,
        )
        val engine = WidgetCoordinatorEngine(host, WidgetStore(InMemoryStorage()), backgroundScope)

        engine.start()
        runCurrent()
        advanceTimeBy(10_000L)
        runCurrent()

        assertEquals(0, host.renders.size)
        assertEquals(0, host.trafficReads)
        assertEquals(0, host.screenSubscriptions)
        engine.stop()
    }

    @Test
    fun `polling runs only when started, active, and screen is on`() = runTest(StandardTestDispatcher()) {
        val host = FakeCoordinatorHost(
            initialRunState = RunState.STOPPED,
            initialActive = true,
            initialScreenOn = true,
        )
        val engine = WidgetCoordinatorEngine(
            host = host,
            store = WidgetStore(InMemoryStorage()),
            scope = backgroundScope,
            pollIntervalMillis = 2_000L,
        )

        engine.start()
        runCurrent()
        assertEquals(1, host.renders.size)
        assertEquals(0, host.trafficReads)
        assertEquals(0L, host.renders.last().startedAtMillis)

        advanceTimeBy(6_000L)
        runCurrent()
        assertEquals(0, host.trafficReads)

        host.runState.value = RunState.STARTED
        runCurrent()
        assertEquals(1, host.trafficReads)
        assertEquals(host.startedAtMillis, host.renders.last().startedAtMillis)

        advanceTimeBy(4_000L)
        runCurrent()
        assertEquals(3, host.trafficReads)

        host.screenState.value = false
        runCurrent()
        val readsAtScreenOff = host.trafficReads
        advanceTimeBy(10_000L)
        runCurrent()
        assertEquals(readsAtScreenOff, host.trafficReads)

        host.screenState.value = true
        runCurrent()
        assertEquals(readsAtScreenOff + 1, host.trafficReads)

        host.runState.value = RunState.STOPPED
        runCurrent()
        assertEquals(0, host.renders.last().historySize)
        assertEquals(0L, host.renders.last().startedAtMillis)
        engine.stop()
    }

    @Test
    fun `disabling last widget unregisters screen flow and notifies plugin`() = runTest(StandardTestDispatcher()) {
        val host = FakeCoordinatorHost(
            initialRunState = RunState.STARTED,
            initialActive = true,
            initialScreenOn = true,
        )
        val engine = WidgetCoordinatorEngine(host, WidgetStore(InMemoryStorage()), backgroundScope)

        engine.start()
        runCurrent()
        assertEquals(1, host.activeScreenSubscriptions)

        host.active = false
        engine.onWidgetsChanged()
        runCurrent()

        assertEquals(0, host.activeScreenSubscriptions)
        assertEquals(listOf(false), host.activeNotifications)

        val readsAfterDisable = host.trafficReads
        advanceTimeBy(6_000L)
        runCurrent()
        assertEquals(readsAfterDisable, host.trafficReads)
        engine.stop()
    }

    @Test
    fun `history is bounded to max samples`() = runTest(StandardTestDispatcher()) {
        val host = FakeCoordinatorHost(
            initialRunState = RunState.STARTED,
            initialActive = true,
            initialScreenOn = true,
        )
        val engine = WidgetCoordinatorEngine(
            host = host,
            store = WidgetStore(InMemoryStorage()),
            scope = backgroundScope,
            pollIntervalMillis = 1_000L,
        )

        engine.start()
        runCurrent()
        advanceTimeBy(30_000L)
        runCurrent()

        assertEquals(WidgetCoordinatorEngine.MAX_HISTORY_SAMPLES, host.renders.last().historySize)
        engine.stop()
    }

    @Test
    fun `fallback snapshot is replaced once real snapshot is saved`() = runTest(StandardTestDispatcher()) {
        val host = FakeCoordinatorHost(
            initialRunState = RunState.STOPPED,
            initialActive = true,
            initialScreenOn = true,
        )
        host.fallback = WidgetSnapshot(hasProfile = true, profileName = "Fallback")
        val engine = WidgetCoordinatorEngine(host, WidgetStore(InMemoryStorage()), backgroundScope)

        engine.start()
        runCurrent()
        assertEquals("Fallback", host.renders.last().snapshot.profileName)

        engine.updateSnapshot(WidgetSnapshot(hasProfile = true, profileName = "Real"))
        runCurrent()
        assertEquals("Real", host.renders.last().snapshot.profileName)
        engine.stop()
    }

    @Test
    fun `refreshNow re-renders only when widgets are active and keeps history`() = runTest(StandardTestDispatcher()) {
        val host = FakeCoordinatorHost(
            initialRunState = RunState.STARTED,
            initialActive = false,
            initialScreenOn = true,
        )
        val engine = WidgetCoordinatorEngine(host, WidgetStore(InMemoryStorage()), backgroundScope)

        engine.refreshNow()
        assertEquals(0, host.renders.size)

        host.active = true
        engine.start()
        runCurrent()
        val rendersAfterStart = host.renders.size
        val readsAfterStart = host.trafficReads

        engine.refreshNow()
        assertEquals(rendersAfterStart + 1, host.renders.size)
        assertEquals(readsAfterStart, host.trafficReads)
        assertEquals(1, host.renders.last().historySize)
        engine.stop()
    }
}
