package io.diogel.symudol

import android.os.SystemClock
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

/** PIN lockouts are timed on elapsedRealtime and the boot count, not the wall clock (#16). */
@RunWith(RobolectricTestRunner::class)
class MonotonicClockTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun returnsElapsedRealtimeAndTheBootCount() {
        Settings.Global.putInt(context.contentResolver, Settings.Global.BOOT_COUNT, 7)

        val now = MonotonicClock.now(context)

        assertEquals(SystemClock.elapsedRealtime(), now["elapsedRealtimeMs"])
        assertEquals(7L, now["bootCount"])
    }

    @Test
    fun followsElapsedRealtime() {
        val before = MonotonicClock.now(context)["elapsedRealtimeMs"]!!

        ShadowSystemClock.advanceBy(Duration.ofSeconds(30))

        assertEquals(before + 30_000, MonotonicClock.now(context)["elapsedRealtimeMs"])
    }

    @Test
    fun aMissingBootCountReadsAsZero() {
        assertEquals(0L, MonotonicClock.now(context)["bootCount"])
    }
}
