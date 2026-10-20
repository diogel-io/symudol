package io.diogel.symudol

import android.content.Intent
import android.net.Uri
import android.os.Looper
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowLog
import java.nio.ByteBuffer

/**
 * What MainActivity logs when a NIP-55 request reaches it (SR-21, #14): the `nostrsigner:` URI and
 * the handed-over request carry the event or plaintext, and must never reach the system log.
 *
 * There is no Flutter engine on the JVM, so FlutterFragmentActivity's own onCreate fails after
 * MainActivity's first log line. onNewIntent runs fully with a stand-in FlutterFragment, which
 * FlutterFragmentActivity forwards new intents to (#23), and a stand-in channel lets the request
 * go all the way to Dart.
 */
@RunWith(RobolectricTestRunner::class)
class MainActivityLoggingTest {
    private val secret = "SECRET-MARKER-7f3a"
    private val event = """{"kind":1,"content":"$secret","tags":[]}"""

    @Before
    fun setUp() {
        Nip55Handoff.clear()
        ShadowLog.reset()
    }

    @After
    fun tearDown() {
        Nip55Handoff.clear()
        ShadowLog.reset()
    }

    /** A request as clients send it: the event in the URI and in the extras. */
    private fun nostrsigner() = Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:${Uri.encode(event)}")).apply {
        putExtra("type", "sign_event")
        putExtra("content", event)
    }

    /** A request handed over by the bridge, as MainActivity receives it. */
    private fun handedOver(): Intent {
        val token = Nip55Handoff.newToken("test")
        Nip55Handoff.register(token, mapOf("requestToken" to token, "type" to "sign_event", "content" to event))
        return Intent().setClassName(BuildConfig.APPLICATION_ID, MainActivity::class.java.name)
            .putExtra("requestToken", token)
    }

    private fun assertMainActivityLoggedNoContent() {
        val lines = ShadowLog.getLogs()
        assertTrue("MainActivity logged", lines.any { it.tag == "Diogel-MainActivity" })
        for (item in lines) assertFalse("logged content: ${item.msg}", item.msg.contains(secret))
    }

    @Test
    fun onCreateDoesNotLogTheIntent() {
        for (intent in listOf(nostrsigner(), handedOver())) {
            runCatching { Robolectric.buildActivity(MainActivity::class.java, intent).create() }
        }

        assertMainActivityLoggedNoContent()
    }

    /** What reached Dart, by method name. */
    private val sentToDart = mutableListOf<String>()

    /** Gives [activity] a channel to a stand-in engine, as configureFlutterEngine would. */
    private fun attachChannel(activity: MainActivity) {
        val messenger = object : BinaryMessenger {
            override fun send(channel: String, message: ByteBuffer?) {}
            override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
                sentToDart += StandardMethodCodec.INSTANCE.decodeMethodCall(message!!.rewind() as ByteBuffer).method
            }
            override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {}
        }
        MainActivity::class.java.getDeclaredField("channel").apply { isAccessible = true }
            .set(activity, MethodChannel(messenger, "io.diogel.symudol/nip55"))
        // Without an engine there is no FlutterFragment to take the intent.
        FlutterFragmentActivity::class.java.getDeclaredField("flutterFragment")
            .apply { isAccessible = true }
            .set(activity, object : FlutterFragment() {
                override fun onNewIntent(intent: Intent) {}
            })
    }

    @Test
    fun onNewIntentDoesNotLogTheIntentOrTheRequest() {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        attachChannel(controller.get())
        val request = handedOver()

        controller.newIntent(nostrsigner())
        controller.newIntent(request)
        controller.newIntent(request) // delivered already: ignored
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals("the request reached Dart", listOf("onNip55Intent"), sentToDart)
        assertMainActivityLoggedNoContent()
    }
}
