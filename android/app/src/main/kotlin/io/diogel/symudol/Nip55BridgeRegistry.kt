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
        Nip55Handoff.remove(token)
    }

    fun complete(token: String, extras: Map<*, *>): Boolean {
        Nip55Handoff.remove(token)
        val activity = pending.remove(token)?.get() ?: return false
        val resultIntent = Intent()
        extras.forEach { (key, value) ->
            if (key is String && value != null) {
                // A Boolean stays a Boolean: clients read `rejected` with getBooleanExtra.
                if (value is Boolean) resultIntent.putExtra(key, value)
                else resultIntent.putExtra(key, value.toString())
            }
        }
        activity.complete(resultIntent)
        return true
    }

    /**
     * Ends [token]'s request without a result. When [rejected] is true the user (or a remembered
     * reject) refused it, and the caller gets NIP-55's `RESULT_OK` with a Boolean `rejected`
     * extra. Otherwise Symudol failed to handle it, which NIP-55 reports as a non-OK result.
     */
    fun reject(token: String, error: String?, rejected: Boolean): Boolean {
        Nip55Handoff.remove(token)
        val activity = pending.remove(token)?.get() ?: return false
        val resultIntent = Intent()
        if (!error.isNullOrBlank()) {
            resultIntent.putExtra("error", error)
        }
        if (rejected) activity.reject(resultIntent) else activity.fail(resultIntent)
        return true
    }
}
