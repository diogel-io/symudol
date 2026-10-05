package io.diogel.symudol

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

/**
 * Requests handed from [Nip55BridgeActivity] to [MainActivity], held in this process.
 *
 * The bridge owns the `nostrsigner:` intent filter and attests the caller from Android itself
 * (`callingPackage`, the package manager's certificate lookup). It registers the whole request
 * here, identity included, under an unguessable token, and the intent it sends to MainActivity
 * carries only that token.
 *
 * MainActivity is exported (it is the launcher activity), so any app can send it an intent with
 * any extras. It used to read the request, and the caller's package and certificate, from those
 * extras: an app could claim to be a trusted client and have that client's remembered decisions
 * applied (diogel-io/symudol#7). Now a request is only what the bridge registered; an intent whose
 * token isn't registered here is not a NIP-55 request.
 *
 * Pure Kotlin, no Android types, so it is unit-tested directly.
 */
object Nip55Handoff {
    private const val TOKEN_BYTES = 16
    private val random = SecureRandom()
    private val pending = ConcurrentHashMap<String, Map<String, Any?>>()

    /** A new token: [prefix] plus 128 random bits as hex. */
    fun newToken(prefix: String): String {
        val bytes = ByteArray(TOKEN_BYTES)
        random.nextBytes(bytes)
        return prefix + bytes.joinToString("") { "%02x".format(it) }
    }

    /** Registers [request] under [token]. The map is copied; later changes to it don't apply. */
    fun register(token: String, request: Map<String, Any?>) {
        pending[token] = request.toMap()
    }

    /**
     * The request registered under [token], or null if there is none. This is the only way a
     * NIP-55 request reaches MainActivity: nothing else in the intent is read.
     */
    fun resolve(token: String?): Map<String, Any?>? {
        if (token.isNullOrBlank()) return null
        return pending[token]
    }

    /** Forgets the request, once its bridge has answered the caller or gone. */
    fun remove(token: String) {
        pending.remove(token)
    }

    /** Test seam. */
    internal fun clear() {
        pending.clear()
    }
}
