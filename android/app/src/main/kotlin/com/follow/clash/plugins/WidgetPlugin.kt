package com.follow.clash.plugins

import com.follow.clash.WidgetDataStore
import com.follow.clash.WidgetRefresher
import com.follow.clash.WidgetState
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.invokeMethodOnMainThread
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WidgetPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val gson = Gson()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "${Components.PACKAGE_NAME}/widget",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateWidget" -> {
                @Suppress("UNCHECKED_CAST")
                val data = call.arguments as? Map<String, Any?>
                if (data != null) {
                    handleUpdateWidget(data)
                }
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    fun handleCycleMode() {
        channel.invokeMethodOnMainThread("cycleMode")
    }

    fun handleCycleNode() {
        channel.invokeMethodOnMainThread("cycleNode")
    }

    fun handleSelectProxy(proxyName: String) {
        channel.invokeMethodOnMainThread("selectProxy", proxyName)
    }

    private fun handleUpdateWidget(data: Map<String, Any?>) {
        try {
            val chartBytes = data["chartBytes"] as? ByteArray
            val dataWithoutChart = data.filterKeys { it != "chartBytes" }
            val jsonString = gson.toJson(dataWithoutChart)
            val state = gson.fromJson(jsonString, WidgetState::class.java)
            val context = GlobalState.application
            WidgetDataStore.saveState(context, state)
            WidgetRefresher.refreshAll(context, chartBytes)
        } catch (_: Exception) {
        }
    }
}
