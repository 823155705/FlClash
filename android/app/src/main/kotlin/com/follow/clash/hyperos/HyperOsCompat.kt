package com.follow.clash.hyperos

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build

/**
 * HyperOS / MIUI detection and feature flags.
 *
 * Core widget behavior stays on standard AppWidget APIs. Everything in this
 * package is an optional enhancement layer — on non-Xiaomi devices these
 * helpers no-op or return false.
 */
object HyperOsCompat {
    @Volatile
    private var cached: Info? = null

    data class Info(
        val isXiaomi: Boolean,
        val isMiui: Boolean,
        val isHyperOs: Boolean,
        val osVersionName: String,
    )

    fun info(context: Context): Info {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val manufacturer = Build.MANUFACTURER.orEmpty()
            val brand = Build.BRAND.orEmpty()
            val isXiaomi = manufacturer.equals("Xiaomi", ignoreCase = true) ||
                brand.equals("Xiaomi", ignoreCase = true) ||
                manufacturer.equals("Redmi", ignoreCase = true) ||
                brand.equals("Redmi", ignoreCase = true)

            val hyperOsName = systemProperty("ro.mi.os.version.name").orEmpty()
            val miuiName = systemProperty("ro.miui.ui.version.name").orEmpty()
            val isHyperOs = hyperOsName.isNotEmpty()
            val isMiui = isHyperOs || miuiName.isNotEmpty() ||
                systemProperty("ro.miui.ui.version.code").orEmpty().isNotEmpty()

            val info = Info(
                isXiaomi = isXiaomi,
                isMiui = isMiui,
                isHyperOs = isHyperOs,
                osVersionName = hyperOsName.ifEmpty { miuiName },
            )
            cached = info
            return info
        }
    }

    /** True when we should enable HyperOS reliability enhancements. */
    fun shouldEnhance(context: Context): Boolean {
        val info = info(context)
        return info.isHyperOs || info.isMiui || info.isXiaomi
    }

    @SuppressLint("PrivateApi")
    private fun systemProperty(key: String): String? {
        return try {
            val cl = Class.forName("android.os.SystemProperties")
            val get = cl.getMethod("get", String::class.java)
            (get.invoke(null, key) as? String)?.trim()
        } catch (_: Throwable) {
            null
        }
    }
}
