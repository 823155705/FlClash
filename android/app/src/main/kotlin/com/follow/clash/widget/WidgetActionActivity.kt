package com.follow.clash.widget

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import com.follow.clash.R
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.intent
import com.follow.clash.models.WidgetPendingAction
import com.follow.clash.showToast

class WidgetActionActivity : Activity() {
    private var dialog: AlertDialog? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dismissDialog()
        handleIntent(intent)
    }

    override fun onDestroy() {
        dismissDialog()
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_ACTION)
        when (action) {
            WidgetPendingAction.ACTION_CYCLE_MODE -> handleCycleMode()
            WidgetPendingAction.ACTION_SELECT_PROXY -> showProxySelector()
            else -> finish()
        }
    }

    private fun handleCycleMode() {
        if (WidgetCoordinator.dispatchCycleMode()) {
            finish()
            return
        }
        WidgetCoordinator.enqueuePendingAction(
            WidgetPendingAction(action = WidgetPendingAction.ACTION_CYCLE_MODE),
        )
        openMainActivity()
        finish()
    }

    private fun showProxySelector() {
        val snapshot = WidgetCoordinator.currentSnapshot()
        val proxies = snapshot.proxyNames
        if (!snapshot.canSelectProxy || proxies.isEmpty() || snapshot.groupName.isBlank()) {
            val message = snapshot.labels["noNodesAvailable"]?.takeIf { it.isNotBlank() }
                ?: getString(R.string.widget_no_nodes)
            GlobalState.application.showToast(message)
            openMainActivity()
            finish()
            return
        }

        val title = snapshot.labels["selectNodeTitle"]?.takeIf { it.isNotBlank() }
            ?: getString(R.string.widget_select_node_title)
        val items = proxies.toTypedArray()
        val checkedIndex = proxies.indexOf(snapshot.nodeName)

        dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setSingleChoiceItems(items, checkedIndex) { dialogInterface, which ->
                val selected = items.getOrNull(which)
                dialogInterface.dismiss()
                if (selected != null) {
                    onProxyPicked(snapshot.groupName, selected)
                } else {
                    finish()
                }
            }
            .setOnCancelListener { finish() }
            .create()
        dialog?.show()
    }

    private fun onProxyPicked(groupName: String, proxyName: String) {
        if (WidgetCoordinator.dispatchSelectProxy(groupName, proxyName)) {
            finish()
            return
        }
        WidgetCoordinator.enqueuePendingAction(
            WidgetPendingAction(
                action = WidgetPendingAction.ACTION_SELECT_PROXY,
                groupName = groupName,
                proxyName = proxyName,
            ),
        )
        openMainActivity()
        finish()
    }

    private fun openMainActivity() {
        val mainIntent = Components.mainActivity.intent.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        startActivity(mainIntent)
    }

    private fun dismissDialog() {
        dialog?.dismiss()
        dialog = null
    }

    companion object {
        const val EXTRA_ACTION = "widget_action"
    }
}
