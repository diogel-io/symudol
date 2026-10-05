package io.diogel.symudol

import android.content.Intent
import android.util.Log

/**
 * Which NIP-55 requests [MainActivity] is handling, and where their answers go.
 *
 * Moved out of MainActivity (a FlutterActivity, which can't run in a JVM test with its engine) so
 * the security-relevant part is tested directly (diogel-io/symudol#68):
 * - a request is only what [Nip55BridgeActivity] registered in [Nip55Handoff]; nothing in the
 *   intent but its token is read (#7);
 * - an answer only ever goes to the bridge that owns the request, never to whoever started
 *   MainActivity.
 */
class Nip55RequestRouter(private val bridge: Bridge = RegistryBridge) {
    /** Where answers are delivered: the bridge activity that holds the caller's result. */
    interface Bridge {
        fun complete(token: String, extras: Map<*, *>): Boolean
        fun reject(token: String, error: String?): Boolean
    }

    object RegistryBridge : Bridge {
        override fun complete(token: String, extras: Map<*, *>) = Nip55BridgeRegistry.complete(token, extras)
        override fun reject(token: String, error: String?) = Nip55BridgeRegistry.reject(token, error)
    }

    enum class Outcome {
        /** Not a request this activity is handling: nothing was done. */
        NOT_ACTIVE,
        /** The bridge received the answer and returns it to the caller. */
        DELIVERED,
        /** The bridge has gone; the answer is dropped, never sent anywhere else. */
        NO_BRIDGE,
    }

    private val activeTokens = LinkedHashSet<String>()
    private var lastDeliveredToken: String? = null

    /** The request being shown, if any. */
    var activeRequestToken: String? = null
        private set

    /**
     * The NIP-55 request [intent] hands over, or null if it hands over none: an intent whose token
     * isn't registered in [Nip55Handoff], including one with forged identity extras or a
     * `nostrsigner:` VIEW addressed to MainActivity directly.
     */
    fun parse(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val token = intent.getStringExtra("requestToken")
        val request = Nip55Handoff.resolve(token)
        if (request == null && (token != null || intent.hasExtra("type") || intent.data?.scheme == "nostrsigner")) {
            // Never log the extras: they may carry event content or plaintext.
            Log.w(TAG, "parse: ignored a NIP-55 intent that was not handed over by the bridge")
        }
        return request
    }

    /**
     * Starts handling [request]. Returns false when it was already delivered by
     * [markDelivered] (the bridge both starts MainActivity and delivers directly, as a fallback).
     */
    fun activate(request: Map<String, Any?>, markDelivered: Boolean): Boolean {
        val token = request["requestToken"] as? String
        if (markDelivered && token != null && token == lastDeliveredToken) return false
        activeRequestToken = token
        token?.let { activeTokens.add(it) }
        if (markDelivered) lastDeliveredToken = token
        return true
    }

    fun isActive(token: String?): Boolean = token != null && activeTokens.contains(token)

    /** Sends the result of [token]'s request to its bridge. */
    fun complete(token: String?, extras: Map<*, *>): Outcome =
        settle(token) { bridge.complete(it, extras) }

    /** Sends the rejection of [token]'s request to its bridge. */
    fun reject(token: String?, error: String?): Outcome =
        settle(token) { bridge.reject(it, error) }

    private fun settle(token: String?, deliver: (String) -> Boolean): Outcome {
        if (token == null || !isActive(token)) return Outcome.NOT_ACTIVE
        clear(token)
        if (deliver(token)) return Outcome.DELIVERED
        Log.w(TAG, "settle: no bridge for the request; its answer is dropped")
        return Outcome.NO_BRIDGE
    }

    private fun clear(token: String) {
        activeTokens.remove(token)
        if (activeRequestToken == token) activeRequestToken = activeTokens.firstOrNull()
    }

    private companion object {
        const val TAG = "Diogel-Nip55Router"
    }
}
