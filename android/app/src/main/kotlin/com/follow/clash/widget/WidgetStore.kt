package com.follow.clash.widget

import android.content.Context
import com.follow.clash.models.WidgetPendingAction
import com.follow.clash.models.WidgetSnapshot
import com.google.gson.Gson

internal interface WidgetKeyValueStorage {
    fun getString(key: String): String?

    fun putString(key: String, value: String)

    fun remove(key: String)
}

internal class SharedPrefsWidgetStorage(
    context: Context,
) : WidgetKeyValueStorage {
    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE,
    )

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }

    private companion object {
        const val PREFS_NAME = "flclash_widget"
    }
}

internal class WidgetStore(
    private val storage: WidgetKeyValueStorage,
    private val gson: Gson = Gson(),
) {
    private val lock = Any()

    fun hasSavedSnapshot(): Boolean = synchronized(lock) {
        storage.getString(KEY_SNAPSHOT) != null
    }

    fun loadSnapshot(): WidgetSnapshot = synchronized(lock) {
        val raw = storage.getString(KEY_SNAPSHOT) ?: return@synchronized WidgetSnapshot()
        runCatching {
            gson.fromJson(raw, WidgetSnapshot::class.java)?.normalized()
        }.getOrNull() ?: WidgetSnapshot()
    }

    fun saveSnapshot(snapshot: WidgetSnapshot) = synchronized(lock) {
        storage.putString(KEY_SNAPSHOT, gson.toJson(snapshot.normalized()))
    }

    fun savePendingAction(action: WidgetPendingAction) = synchronized(lock) {
        if (action.toChannelMap() == null) return@synchronized
        storage.putString(KEY_PENDING_ACTION, gson.toJson(action))
    }

    fun peekPendingAction(): WidgetPendingAction? = synchronized(lock) {
        val raw = storage.getString(KEY_PENDING_ACTION) ?: return@synchronized null
        runCatching {
            gson.fromJson(raw, WidgetPendingAction::class.java)
        }.getOrNull()?.takeIf { it.toChannelMap() != null }
    }

    fun consumePendingAction(): WidgetPendingAction? = synchronized(lock) {
        val raw = storage.getString(KEY_PENDING_ACTION) ?: return@synchronized null
        storage.remove(KEY_PENDING_ACTION)
        runCatching {
            gson.fromJson(raw, WidgetPendingAction::class.java)
        }.getOrNull()?.takeIf { it.toChannelMap() != null }
    }

    companion object {
        internal const val KEY_SNAPSHOT = "snapshot"
        internal const val KEY_PENDING_ACTION = "pending_action"
    }
}
