package com.follow.clash.plugins

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.models.WidgetSnapshot
import com.follow.clash.widget.BaseWidgetProvider
import com.follow.clash.widget.WidgetCoordinator
import com.follow.clash.widget.WidgetProvider
import com.follow.clash.widget.WidgetProviderCompact
import com.follow.clash.widget.WidgetProviderWide
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class WidgetPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var attached = false

    @Volatile
    private var applicationContext: Context? = null

    @Volatile
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        val messenger = binding.binaryMessenger
        channel = MethodChannel(
            messenger,
            CHANNEL_NAME,
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        )
        channel.setMethodCallHandler(this)
        attached = true
        WidgetCoordinator.attachPlugin(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        applicationContext = null
        WidgetCoordinator.detachPlugin(this)
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateSnapshot" -> {
                val payload = call.arguments as? Map<*, *>
                if (payload == null) {
                    result.error("INVALID_ARGUMENT", "Snapshot payload must be a map", null)
                    return
                }
                WidgetCoordinator.updateSnapshot(WidgetSnapshot.fromChannelMap(payload))
                result.success(true)
            }

            "hasActiveWidgets" -> {
                result.success(WidgetCoordinator.hasActiveWidgets())
            }

            "consumePendingAction" -> {
                result.success(WidgetCoordinator.consumePendingAction()?.toChannelMap())
            }

            "isRequestPinWidgetSupported" -> {
                result.success(isRequestPinWidgetSupported())
            }

            "requestPinWidget" -> {
                val kind = extractKind(call.arguments)
                result.success(requestPinWidget(kind))
            }

            else -> result.notImplemented()
        }
    }

    fun dispatchCycleMode() {
        invokeOnMain("cycleMode", null)
    }

    fun dispatchSelectProxy(groupName: String, proxyName: String) {
        invokeOnMain(
            "selectProxy",
            mapOf("groupName" to groupName, "proxyName" to proxyName),
        )
    }

    fun notifyWidgetsActiveChanged(active: Boolean) {
        invokeOnMain("widgetsActiveChanged", active)
    }

    private fun resolvePinContext(): Context? =
        activity ?: applicationContext ?: runCatching { GlobalState.application }.getOrNull()

    private fun isRequestPinWidgetSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val context = resolvePinContext() ?: return false
        return runCatching {
            AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported
        }.getOrDefault(false)
    }

    private fun requestPinWidget(kind: String?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val providerClass = resolveProviderClass(kind) ?: return false
        val context = resolvePinContext() ?: return false
        val manager = AppWidgetManager.getInstance(context)
        if (!manager.isRequestPinAppWidgetSupported) {
            return false
        }
        return try {
            manager.requestPinAppWidget(ComponentName(context, providerClass), null, null)
        } catch (_: IllegalStateException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun invokeOnMain(method: String, arguments: Any?) {
        mainHandler.post {
            if (!attached) return@post
            runCatching { channel.invokeMethod(method, arguments) }
        }
    }

    internal companion object {
        val CHANNEL_NAME = "${Components.PACKAGE_NAME}/widget"

        fun extractKind(arguments: Any?): String? = when (arguments) {
            is String -> arguments
            is Map<*, *> -> arguments["kind"] as? String
            else -> null
        }

        fun resolveProviderClass(kind: String?): Class<out BaseWidgetProvider>? = when (kind) {
            "2x2" -> WidgetProvider::class.java
            "4x2" -> WidgetProviderWide::class.java
            "4x1" -> WidgetProviderCompact::class.java
            else -> null
        }
    }
}
