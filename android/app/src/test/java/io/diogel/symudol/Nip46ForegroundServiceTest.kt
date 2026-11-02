package io.diogel.symudol

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * The NIP-46 foreground service (diogel-io/symudol#29): it shows its notification with a Stop
 * action, and Stop both ends it and tells the Dart side.
 */
@RunWith(RobolectricTestRunner::class)
class Nip46ForegroundServiceTest {

    @After
    fun tearDown() {
        Nip46ForegroundService.onStopRequested = null
    }

    private fun startIntent() = Intent(
        ApplicationProvider.getApplicationContext(),
        Nip46ForegroundService::class.java,
    ).setAction(Nip46ForegroundService.ACTION_START)

    @Test
    fun startShowsTheNotificationWithAStopAction() {
        val controller = Robolectric.buildService(Nip46ForegroundService::class.java, startIntent())
        val service = controller.create().startCommand(0, 1).get()

        val notification = shadowOf(service).lastForegroundNotification
        assertNotNull(notification)
        assertEquals(Nip46ForegroundService.NOTIFICATION_ID, shadowOf(service).lastForegroundNotificationId)
        assertEquals("Remote signer is running", shadowOf(notification).contentTitle)
        assertEquals(1, notification.actions.size)
        assertEquals("Stop", notification.actions[0].title)
    }

    @Test
    fun stopEndsTheServiceAndTellsDart() {
        var stopsSeen = 0
        Nip46ForegroundService.onStopRequested = { stopsSeen++ }
        val controller = Robolectric.buildService(Nip46ForegroundService::class.java, startIntent())
        val service = controller.create().startCommand(0, 1).get()

        val stop = Intent(service, Nip46ForegroundService::class.java)
            .setAction(Nip46ForegroundService.ACTION_STOP)
        service.onStartCommand(stop, 0, 2)

        assertEquals(1, stopsSeen)
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertTrue(shadowOf(service).isForegroundStopped)
    }
}
