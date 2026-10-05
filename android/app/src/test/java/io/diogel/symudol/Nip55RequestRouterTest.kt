package io.diogel.symudol

import android.content.Intent
import android.net.Uri
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * MainActivity's NIP-55 routing (#68): a request is only what the bridge registered (#7), and an
 * answer only ever goes to that bridge.
 */
@RunWith(RobolectricTestRunner::class)
class Nip55RequestRouterTest {
    /** Records what reaches the bridge, and whether it is still there. */
    private class FakeBridge(var present: Boolean = true) : Nip55RequestRouter.Bridge {
        val completed = mutableListOf<String>()
        val rejected = mutableListOf<String>()
        override fun complete(token: String, extras: Map<*, *>) = present.also { if (it) completed += token }
        override fun reject(token: String, error: String?) = present.also { if (it) rejected += token }
    }

    private val bridge = FakeBridge()
    private val router = Nip55RequestRouter(bridge)

    @Before
    fun setUp() = Nip55Handoff.clear()

    @After
    fun tearDown() = Nip55Handoff.clear()

    private fun registered(type: String = "sign_event"): String {
        val token = Nip55Handoff.newToken("bridge-")
        Nip55Handoff.register(token, mapOf(
            "requestToken" to token, "bridgeToken" to token, "type" to type,
            "callingPackage" to "com.example.client", "callerCertificateSha256" to "AA:BB",
        ))
        return token
    }

    private fun handoff(token: String) = Intent().putExtra("requestToken", token)

    @Test
    fun aForgedIntentIsNotARequest() {
        // What an app sending MainActivity explicit extras could try (#7).
        val forged = Intent().apply {
            putExtra("requestToken", "bridge-guess")
            putExtra("type", "sign_event")
            putExtra("callingPackage", "com.vitorpamplona.amethyst")
            putExtra("callerCertificateSha256", "AA:BB")
            putExtra("content", """{"kind":1}""")
        }
        assertNull(router.parse(forged))
        assertNull(router.parse(Intent().putExtra("type", "get_public_key")))
        assertNull(router.parse(Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:"))))
        assertNull(router.parse(null))
    }

    @Test
    fun aRegisteredTokenIsTheBridgeRequestAndExtrasChangeNothing() {
        val token = registered()
        val intent = handoff(token).apply {
            putExtra("callingPackage", "com.vitorpamplona.amethyst")
            putExtra("type", "get_public_key")
        }

        val request = router.parse(intent)!!

        assertEquals("com.example.client", request["callingPackage"])
        assertEquals("sign_event", request["type"])
    }

    @Test
    fun answersGoToTheBridgeThatOwnsTheRequest() {
        val signed = registered()
        val refused = registered()
        router.activate(router.parse(handoff(signed))!!, markDelivered = true)
        router.activate(router.parse(handoff(refused))!!, markDelivered = true)

        assertEquals(Nip55RequestRouter.Outcome.DELIVERED, router.complete(signed, mapOf("result" to "sig")))
        assertEquals(Nip55RequestRouter.Outcome.DELIVERED, router.reject(refused, "User rejected"))
        assertEquals(listOf(signed), bridge.completed)
        assertEquals(listOf(refused), bridge.rejected)
    }

    @Test
    fun anAnswerForARequestThatIsNotActiveDoesNothing() {
        val token = registered()

        assertEquals(Nip55RequestRouter.Outcome.NOT_ACTIVE, router.complete(token, emptyMap<Any, Any>()))
        assertEquals(Nip55RequestRouter.Outcome.NOT_ACTIVE, router.complete(null, emptyMap<Any, Any>()))
        assertTrue(bridge.completed.isEmpty())
    }

    @Test
    fun anAnswerIsSettledOnce() {
        val token = registered()
        router.activate(router.parse(handoff(token))!!, markDelivered = true)

        router.complete(token, emptyMap<Any, Any>())

        assertEquals(Nip55RequestRouter.Outcome.NOT_ACTIVE, router.complete(token, emptyMap<Any, Any>()))
        assertEquals(1, bridge.completed.size)
    }

    @Test
    fun withTheBridgeGoneTheAnswerIsDroppedNotSentElsewhere() {
        bridge.present = false
        val token = registered()
        router.activate(router.parse(handoff(token))!!, markDelivered = true)

        assertEquals(Nip55RequestRouter.Outcome.NO_BRIDGE, router.complete(token, mapOf("result" to "sig")))
    }

    @Test
    fun aRequestDeliveredTwiceIsShownOnce() {
        val request = router.parse(handoff(registered()))!!

        assertTrue(router.activate(request, markDelivered = true))
        assertFalse(router.activate(request, markDelivered = true))
    }
}
