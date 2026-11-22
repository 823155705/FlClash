package com.follow.clash.models

data class WidgetSnapshot(
    val hasProfile: Boolean = false,
    val profileName: String = "",
    val mode: String = "rule",
    val groupName: String = "",
    val nodeName: String = "",
    val canSelectProxy: Boolean = false,
    val proxyNames: List<String> = emptyList(),
    val suspended: Boolean = false,
    val tunEnabled: Boolean = false,
    val pureBlack: Boolean = false,
    val primaryColorLight: Int = 0,
    val primaryColorDark: Int = 0,
    val labels: Map<String, String> = emptyMap(),
) {
    fun normalized(): WidgetSnapshot = copy(
        mode = mode.ifBlank { "rule" }.lowercase(),
        proxyNames = proxyNames.filter { it.isNotBlank() },
        labels = labels.filterValues { it.isNotBlank() },
    )

    companion object {
        fun fromChannelMap(map: Map<*, *>): WidgetSnapshot {
            val rawProxies = (map["proxyNames"] as? List<*>)
                ?.mapNotNull { it as? String }
                ?.filter { it.isNotBlank() }
                ?: emptyList()
            val rawLabels = (map["labels"] as? Map<*, *>)
                ?.entries
                ?.mapNotNull { (key, value) ->
                    val k = key as? String ?: return@mapNotNull null
                    val v = value as? String ?: return@mapNotNull null
                    if (v.isBlank()) null else k to v
                }
                ?.toMap()
                ?: emptyMap()
            return WidgetSnapshot(
                hasProfile = map["hasProfile"] as? Boolean ?: false,
                profileName = map["profileName"] as? String ?: "",
                mode = (map["mode"] as? String)?.ifBlank { "rule" }?.lowercase() ?: "rule",
                groupName = map["groupName"] as? String ?: "",
                nodeName = map["nodeName"] as? String ?: "",
                canSelectProxy = map["canSelectProxy"] as? Boolean ?: false,
                proxyNames = rawProxies,
                suspended = map["suspended"] as? Boolean ?: false,
                tunEnabled = map["tunEnabled"] as? Boolean ?: false,
                pureBlack = map["pureBlack"] as? Boolean ?: false,
                primaryColorLight = (map["primaryColorLight"] as? Number)?.toInt() ?: 0,
                primaryColorDark = (map["primaryColorDark"] as? Number)?.toInt() ?: 0,
                labels = rawLabels,
            )
        }
    }
}

data class WidgetPendingAction(
    val action: String = "",
    val groupName: String = "",
    val proxyName: String = "",
) {
    fun toChannelMap(): Map<String, Any>? = when (action) {
        ACTION_CYCLE_MODE -> mapOf("action" to ACTION_CYCLE_MODE)
        ACTION_SELECT_PROXY -> if (groupName.isNotBlank() && proxyName.isNotBlank()) {
            mapOf(
                "action" to ACTION_SELECT_PROXY,
                "groupName" to groupName,
                "proxyName" to proxyName,
            )
        } else {
            null
        }
        else -> null
    }

    companion object {
        const val ACTION_CYCLE_MODE = "cycleMode"
        const val ACTION_SELECT_PROXY = "selectProxy"
    }
}
