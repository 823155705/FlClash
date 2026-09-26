package com.follow.clash

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import com.follow.clash.common.QuickAction
import com.follow.clash.common.action
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.Locale

class QuickActionActivity : Activity(),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {
    private val gson = Gson()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent.action) {
            QuickAction.START.action -> {
                launch { ServiceState.handleStartAction() }
                finish()
            }

            QuickAction.STOP.action -> {
                launch { ServiceState.handleStopAction() }
                finish()
            }

            QuickAction.TOGGLE.action -> {
                launch { ServiceState.handleToggleAction() }
                finish()
            }

            QuickAction.SELECT_PROXY.action -> {
                showProxySelector()
            }

            else -> finish()
        }
    }

    private fun showProxySelector() {
        val state = WidgetDataStore.getState(this)
        val proxyNames = try {
            gson.fromJson(state.proxyNames, Array<String>::class.java)?.toList() ?: emptyList()
        } catch (_: Exception) {
            emptyList<String>()
        }
        if (proxyNames.isEmpty()) {
            finish()
            return
        }
        val items = proxyNames.toTypedArray()
        val builder = AlertDialog.Builder(this)
        builder.setTitle(if (Locale.getDefault().language == "zh") "选择节点" else "Select Proxy")
        builder.setItems(items) { _, which ->
            val selected = items[which]
            val resultIntent = Intent(this, WidgetProvider::class.java).apply {
                action = WidgetProvider.actionSelectProxy(this@QuickActionActivity)
                putExtra("selectedProxy", selected)
            }
            sendBroadcast(resultIntent)
            finish()
        }
        builder.setOnCancelListener { finish() }
        builder.show()
    }
}
