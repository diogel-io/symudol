package io.diogel.symudol

import android.content.ClipboardManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

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

    @Test
    fun onlySensitiveClipboardSetsTheClipboard() {
        val sources = File("src/main/kotlin/io/diogel/symudol").listFiles { f -> f.extension == "kt" }
        assertNotNull("run from android/app", sources)
        val offenders = sources!!.filter { it.name != "SensitiveClipboard.kt" && "setPrimaryClip" in it.readText() }

        assertEquals("copy through SensitiveClipboard", emptyList<String>(), offenders.map { it.name })
    }
}
