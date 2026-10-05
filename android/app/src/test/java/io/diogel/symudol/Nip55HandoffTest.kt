package io.diogel.symudol

import org.junit.After
import org.junit.Assert.*
import org.junit.Test

/**
 * The bridge-to-MainActivity handoff (diogel-io/symudol#7): a NIP-55 request reaches MainActivity
 * only as something Nip55BridgeActivity registered, never from intent extras another app could
 * set.
 */
class Nip55HandoffTest {
    @After
    fun tearDown() = Nip55Handoff.clear()

    private fun attested(token: String) = mapOf(
        "requestToken" to token,
        "bridgeToken" to token,
        "type" to "sign_event",
        "content" to "{\"kind\":1,\"content\":\"hi\",\"tags\":[]}",
        "callingPackage" to "com.vitorpamplona.amethyst",
        "callerCertificateSha256" to "AA:BB",
    )

    @Test
    fun anUnregisteredTokenIsNotARequest() {
        // What a forged intent to MainActivity carries: a token the bridge never issued.
        assertNull(Nip55Handoff.resolve("bridge-forged"))
        assertNull(Nip55Handoff.resolve(null))
        assertNull(Nip55Handoff.resolve(""))
    }

    @Test
    fun aRegisteredTokenResolvesToWhatTheBridgeRecorded() {
        val token = Nip55Handoff.newToken("bridge-")
        Nip55Handoff.register(token, attested(token))

        val request = Nip55Handoff.resolve(token)!!
        assertEquals("com.vitorpamplona.amethyst", request["callingPackage"])
        assertEquals("AA:BB", request["callerCertificateSha256"])
        assertEquals(token, request["bridgeToken"])
    }

    @Test
    fun theRegisteredRequestCannotBeChangedAfterwards() {
        val token = Nip55Handoff.newToken("bridge-")
        val request = attested(token).toMutableMap()
        Nip55Handoff.register(token, request)

        request["callingPackage"] = "com.evil.app"

        assertEquals("com.vitorpamplona.amethyst", Nip55Handoff.resolve(token)!!["callingPackage"])
    }

    @Test
    fun aRemovedTokenNoLongerResolves() {
        val token = Nip55Handoff.newToken("bridge-")
        Nip55Handoff.register(token, attested(token))
        Nip55Handoff.remove(token)

        assertNull(Nip55Handoff.resolve(token))
    }

    @Test
    fun tokensAreLongRandomAndUnique() {
        val tokens = (1..1000).map { Nip55Handoff.newToken("bridge-") }
        assertEquals(1000, tokens.toSet().size)
        for (token in tokens) {
            assertTrue(token, token.matches(Regex("bridge-[0-9a-f]{32}")))
        }
    }
}
