package io.diogel.symudol

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** `nostrconnect:` links for NIP-46 pairing (diogel-io/symudol#31). */
@RunWith(RobolectricTestRunner::class)
class Nip46LinksTest {
    private val link = "nostrconnect://" + "a".repeat(64) + "?relay=wss%3A%2F%2Frelay.example.com&secret=s1"
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun view(uri: String, flags: Int = 0) =
        Intent(Intent.ACTION_VIEW, Uri.parse(uri)).addFlags(flags)

    /** Records what a method call answers. */
    private class Answer : MethodChannel.Result {
        var value: Any? = null
        var error: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() { error = "notImplemented" }
    }

    private fun Nip46Links.call(method: String, args: Map<String, Any?>? = null) =
        Answer().also { handle(MethodCall(method, args), it) }

    @Test
    fun aNostrconnectLinkIsTakenOnce() {
        val links = Nip46Links(context)

        assertTrue(links.receive(view(link)))

        assertEquals(link, links.call("takeLink").value)
        assertNull(links.call("takeLink").value)
    }

    @Test
    fun otherIntentsAreNotLinks() {
        assertNull(Nip46Links.linkFrom(null))
        assertNull(Nip46Links.linkFrom(Intent(Intent.ACTION_MAIN)))
        assertNull(Nip46Links.linkFrom(view("nostrsigner:abc")))
        assertNull(Nip46Links.linkFrom(view("bunker://abc")))
        assertNull(Nip46Links.linkFrom(Intent(Intent.ACTION_SEND, Uri.parse(link))))
    }

    @Test
    fun aLinkReopenedFromRecentsIsNotNew() {
        val links = Nip46Links(context)

        assertFalse(links.receive(view(link, Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)))
        assertNull(links.call("takeLink").value)
    }

    @Test
    fun theLatestLinkWins() {
        val links = Nip46Links(context)
        val second = link.replace("s1", "s2")

        links.receive(view(link))
        links.receive(view(second))

        assertEquals(second, links.call("takeLink").value)
    }

    @Test
    fun theLinkAliasIsTurnedOnAndOff() {
        val links = Nip46Links(context)
        val alias = ComponentName(context.packageName, Nip46Links.ALIAS)

        links.call("setLinksEnabled", mapOf("enabled" to true))
        assertEquals(
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            context.packageManager.getComponentEnabledSetting(alias),
        )

        links.call("setLinksEnabled", mapOf("enabled" to false))
        assertEquals(
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            context.packageManager.getComponentEnabledSetting(alias),
        )
    }
}
