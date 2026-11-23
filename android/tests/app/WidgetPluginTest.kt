package com.follow.clash.plugins

import com.follow.clash.widget.WidgetProvider
import com.follow.clash.widget.WidgetProviderCompact
import com.follow.clash.widget.WidgetProviderWide
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WidgetPluginTest {
    @Test
    fun `resolveProviderClass maps supported widget kinds and rejects unknown`() {
        assertEquals(WidgetProvider::class.java, WidgetPlugin.resolveProviderClass("2x2"))
        assertEquals(WidgetProviderWide::class.java, WidgetPlugin.resolveProviderClass("4x2"))
        assertEquals(WidgetProviderCompact::class.java, WidgetPlugin.resolveProviderClass("4x1"))
        assertNull(WidgetPlugin.resolveProviderClass("3x3"))
        assertNull(WidgetPlugin.resolveProviderClass(""))
        assertNull(WidgetPlugin.resolveProviderClass(null))
    }

    @Test
    fun `extractKind accepts both map payload and raw string`() {
        assertEquals("2x2", WidgetPlugin.extractKind(mapOf("kind" to "2x2")))
        assertEquals("4x2", WidgetPlugin.extractKind("4x2"))
        assertNull(WidgetPlugin.extractKind(mapOf("kind" to 123)))
        assertNull(WidgetPlugin.extractKind(null))
    }
}
