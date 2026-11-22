package com.follow.clash.plugins

import android.os.Handler
import android.os.Looper
import com.follow.clash.common.Components
import com.follow.clash.models.WidgetSnapshot
import com.follow.clash.widget.WidgetCoordinator
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class WidgetPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var attached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
        WidgetCoordinator.detachPlugin(this)
        channel.setMethodCallHandler(null)
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

    private fun invokeOnMain(method: String, arguments: Any?) {
        mainHandler.post {
            if (!attached) return@post
            runCatching { channel.invokeMethod(method, arguments) }
        }
    }

    private companion object {
        val CHANNEL_NAME = "${Components.PACKAGE_NAME}/widget"
    }
}
