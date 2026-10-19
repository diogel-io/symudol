package io.diogel.symudol

import android.view.WindowManager
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * MainActivity's window is kept out of screenshots, screen recording and the recents preview
 * (SR-23, #15). Flutter draws every screen in it, so the flag covers the whole app.
 */
@RunWith(RobolectricTestRunner::class)
class MainActivityWindowTest {
    @Test
    fun theWindowIsSecureBeforeFlutterStarts() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        // There is no Flutter engine on the JVM, so FlutterActivity's own onCreate fails; the flag
        // is set before it runs.
        runCatching { controller.create() }

        val flags = controller.get().window.attributes.flags
        assertTrue("FLAG_SECURE is set", flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
    }
}
