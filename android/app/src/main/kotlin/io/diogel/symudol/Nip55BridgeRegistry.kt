package io.diogel.symudol

import android.content.Intent
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap

object Nip55BridgeRegistry {
    private val pending = ConcurrentHashMap<String, WeakReference<Nip55BridgeActivity>>()

    fun register(token: String, activity: Nip55BridgeActivity) {
        pending[token] = WeakReference(activity)
    }

    fun unregister(token: String) {
        pending.remove(token)
    }

    fun complete(token: String, extras: Map<*, *>): Boolean {
        val activity = pending.remove(token)?.get() ?: return false
        val resultIntent = Intent()
        extras.forEach { (key, value) ->
            if (key is String && value != null) {
                resultIntent.putExtra(key, value.toString())
            }
        }
        activity.complete(resultIntent)
        return true
    }

    fun reject(token: String, error: String?): Boolean {
        val activity = pending.remove(token)?.get() ?: return false
        val resultIntent = Intent()
        if (!error.isNullOrBlank()) {
            resultIntent.putExtra("error", error)
        }
        activity.reject(resultIntent)
        return true
    }
}
