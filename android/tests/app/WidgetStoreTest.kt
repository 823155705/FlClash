package com.follow.clash.widget

import com.follow.clash.models.WidgetPendingAction
import com.follow.clash.models.WidgetSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class MemoryWidgetStorage : WidgetKeyValueStorage {
    private val map = LinkedHashMap<String, String>()

    override fun getString(key: String): String? = map[key]

    override fun putString(key: String, value: String) {
        map[key] = value
    }

    override fun remove(key: String) {
        map.remove(key)
    }
}

class WidgetStoreTest {
    @Test
    fun `snapshot persists full payload without dropping fields`() {
        val store = WidgetStore(MemoryWidgetStorage())
        assertFalse(store.hasSavedSnapshot())

        val snapshot = WidgetSnapshot(
            hasProfile = true,
            profileName = "Main Profile",
            mode = "GLOBAL",
            groupName = "Proxy",
            nodeName = "HK-01",
            canSelectProxy = true,
            proxyNames = listOf("HK-01", "", "JP-02"),
            suspended = false,
            tunEnabled = true,
            pureBlack = true,
            primaryColorLight = 0xFF007AFF.toInt(),
            primaryColorDark = 0xFF2F83FF.toInt(),
            labels = mapOf("running" to "Running", "empty" to "  "),
        )
        store.saveSnapshot(snapshot)

        assertTrue(store.hasSavedSnapshot())
        val loaded = store.loadSnapshot()
        assertEquals(true, loaded.hasProfile)
        assertEquals("Main Profile", loaded.profileName)
        assertEquals("global", loaded.mode)
        assertEquals("Proxy", loaded.groupName)
        assertEquals("HK-01", loaded.nodeName)
        assertEquals(true, loaded.canSelectProxy)
        assertEquals(listOf("HK-01", "JP-02"), loaded.proxyNames)
        assertEquals(true, loaded.tunEnabled)
        assertEquals(true, loaded.pureBlack)
        assertEquals(0xFF007AFF.toInt(), loaded.primaryColorLight)
        assertEquals(0xFF2F83FF.toInt(), loaded.primaryColorDark)
        assertEquals(mapOf("running" to "Running"), loaded.labels)
    }

    @Test
    fun `channel map decodes unsigned 64-bit ARGB ints from Flutter`() {
        val snapshot = WidgetSnapshot.fromChannelMap(
            mapOf(
                "hasProfile" to true,
                "profileName" to "Work",
                "mode" to "Rule",
                "groupName" to "Select",
                "nodeName" to "SG-01",
                "canSelectProxy" to true,
                "proxyNames" to listOf("SG-01", "US-01"),
                "suspended" to true,
                "tunEnabled" to true,
                "pureBlack" to true,
                "primaryColorLight" to 0xFF007AFFL,
                "primaryColorDark" to 0xFF2F83FFL,
                "labels" to mapOf("suspended" to "Suspended"),
            ),
        )

        assertEquals(0xFF007AFF.toInt(), snapshot.primaryColorLight)
        assertEquals(0xFF2F83FF.toInt(), snapshot.primaryColorDark)
        assertEquals("rule", snapshot.mode)
        assertEquals(true, snapshot.suspended)
        assertEquals(listOf("SG-01", "US-01"), snapshot.proxyNames)
        assertEquals(mapOf("suspended" to "Suspended"), snapshot.labels)
    }

    @Test
    fun `corrupt json falls back to default snapshot`() {
        val storage = MemoryWidgetStorage()
        storage.putString(WidgetStore.KEY_SNAPSHOT, "{not-valid-json")
        val store = WidgetStore(storage)

        val loaded = store.loadSnapshot()

        assertEquals(WidgetSnapshot(), loaded)
    }

    @Test
    fun `partial json retains declared defaults`() {
        val storage = MemoryWidgetStorage()
        storage.putString(WidgetStore.KEY_SNAPSHOT, """{"hasProfile":true,"profileName":"Sub"}""")
        val store = WidgetStore(storage)

        val loaded = store.loadSnapshot()

        assertTrue(loaded.hasProfile)
        assertEquals("Sub", loaded.profileName)
        assertEquals("rule", loaded.mode)
        assertEquals(emptyList<String>(), loaded.proxyNames)
        assertEquals(emptyMap<String, String>(), loaded.labels)
    }

    @Test
    fun `pending action is latest-wins and consumed once`() {
        val store = WidgetStore(MemoryWidgetStorage())
        assertNull(store.consumePendingAction())

        store.savePendingAction(WidgetPendingAction(action = WidgetPendingAction.ACTION_CYCLE_MODE))
        store.savePendingAction(
            WidgetPendingAction(
                action = WidgetPendingAction.ACTION_SELECT_PROXY,
                groupName = "Proxy",
                proxyName = "JP-01",
            ),
        )

        val peeked = store.peekPendingAction()
        assertNotNull(peeked)
        assertEquals(WidgetPendingAction.ACTION_SELECT_PROXY, peeked?.action)

        val consumed = store.consumePendingAction()
        assertEquals(
            mapOf(
                "action" to "selectProxy",
                "groupName" to "Proxy",
                "proxyName" to "JP-01",
            ),
            consumed?.toChannelMap(),
        )
        assertNull(store.consumePendingAction())
    }

    @Test
    fun `invalid pending action is ignored`() {
        val store = WidgetStore(MemoryWidgetStorage())

        store.savePendingAction(
            WidgetPendingAction(
                action = WidgetPendingAction.ACTION_SELECT_PROXY,
                groupName = "",
                proxyName = "JP-01",
            ),
        )

        assertNull(store.peekPendingAction())
        assertNull(store.consumePendingAction())
    }
}
