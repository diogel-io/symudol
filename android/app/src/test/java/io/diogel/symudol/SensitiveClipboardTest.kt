package io.diogel.symudol

import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.util.concurrent.TimeUnit

/** Every clip Symudol makes is marked sensitive, and only SensitiveClipboard makes them (#94). */
@RunWith(RobolectricTestRunner::class)
class SensitiveClipboardTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun aClipIsMarkedSensitive() {
        val clip = SensitiveClipboard.clip("NIP-55 result", "decrypted plaintext")

        assertEquals("NIP-55 result", clip.description.label)
        assertEquals("decrypted plaintext", clip.getItemAt(0).text)
        assertTrue(clip.description.extras.getBoolean(SensitiveClipboard.EXTRA_IS_SENSITIVE))
    }

    @Test
    fun copyPutsTheSensitiveClipOnTheClipboard() {
        SensitiveClipboard.copy(context, "bunker URI", "bunker://abc?secret=xyz")

        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        assertNotNull(clip)
        assertEquals("bunker://abc?secret=xyz", clip!!.getItemAt(0).text)
        assertTrue(clip.description.extras.getBoolean(SensitiveClipboard.EXTRA_IS_SENSITIVE))
    }

    private val clipboard get() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private fun clipText(): String? = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()

    @Test
    fun aTimedCopyIsClearedAfterTheDelay() {
        SensitiveClipboard.copy(context, "Nostr private key", "nsec1abc", clearAfterMs = 60_000)

        ShadowLooper.idleMainLooper(59, TimeUnit.SECONDS)
        assertEquals("nsec1abc", clipText())

        ShadowLooper.idleMainLooper(2, TimeUnit.SECONDS)
        assertFalse(clipboard.hasPrimaryClip() && clipText() == "nsec1abc")
    }

    @Test
    fun aNewerCopyCancelsTheClear() {
        SensitiveClipboard.copy(context, "Nostr private key", "nsec1abc", clearAfterMs = 60_000)
        SensitiveClipboard.copy(context, "bunker URI", "bunker://abc")

        ShadowLooper.idleMainLooper(61, TimeUnit.SECONDS)
        assertEquals("bunker://abc", clipText())
    }

    @Test
    fun aClipReplacedElsewhereIsLeftAlone() {
        SensitiveClipboard.copy(context, "Nostr private key", "nsec1abc", clearAfterMs = 60_000)
        // Another app's copy, not through SensitiveClipboard.
        clipboard.setPrimaryClip(SensitiveClipboard.clip("other", "the user's own text"))

        ShadowLooper.idleMainLooper(61, TimeUnit.SECONDS)
        assertEquals("the user's own text", clipText())
    }

    @Test
    fun copyThrowsWhenThereIsNoClipboard() {
        val noClipboard = object : ContextWrapper(context) {
            override fun getSystemService(name: String): Any? =
                if (name == Context.CLIPBOARD_SERVICE) null else super.getSystemService(name)
        }

        assertThrows(IllegalStateException::class.java) {
            SensitiveClipboard.copy(noClipboard, "bunker URI", "bunker://abc?secret=xyz")
        }
    }

    @Test
    fun onlySensitiveClipboardSetsTheClipboard() {
        val root = File("src/main/kotlin")
        assertTrue("run from android/app", root.isDirectory)
        // Recursive, so a subpackage can't slip past (#96).
        val sources = root.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue("found the Kotlin sources", sources.any { it.name == "SensitiveClipboard.kt" })
        val offenders = sources.filter { it.name != "SensitiveClipboard.kt" && "setPrimaryClip" in it.readText() }

        assertEquals("copy through SensitiveClipboard", emptyList<String>(), offenders.map { it.name })
    }
}
