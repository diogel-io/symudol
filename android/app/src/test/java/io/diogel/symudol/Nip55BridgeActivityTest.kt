package io.diogel.symudol

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.content.pm.SigningInfo
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.security.MessageDigest

/**
 * The real Nip55BridgeActivity on Robolectric (#68): the caller is the one Android reports, and
 * nothing a client puts in its intent can change that (#7).
 */
@RunWith(RobolectricTestRunner::class)
class Nip55BridgeActivityTest {
    private val client = "com.example.client"
    private val clientSignature = Signature("cafebabe")

    @Before
    fun setUp() {
        Nip55Handoff.clear()
        Nip55BridgeActivity.resetRateLimitsForTests()
        installPackage(client, clientSignature)
    }

    @After
    fun tearDown() = Nip55Handoff.clear()

    private fun installPackage(name: String, signature: Signature) {
        // API 28+ reads signingInfo (GET_SIGNING_CERTIFICATES); older APIs read signatures.
        val signing = SigningInfo().also { shadowOf(it).setSignatures(arrayOf(signature)) }
        val info = PackageInfo().apply {
            packageName = name
            signingInfo = signing
            @Suppress("DEPRECATION")
            signatures = arrayOf(signature)
        }
        shadowOf(ApplicationProvider.getApplicationContext<android.content.Context>().packageManager)
            .installPackage(info)
    }

    private fun certOf(signature: Signature) =
        MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            .joinToString(":") { "%02X".format(it) }

    private fun nostrsigner(type: String, browsable: Boolean = false) =
        Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:")).apply {
            putExtra("type", type)
            if (browsable) addCategory(Intent.CATEGORY_BROWSABLE)
        }

    /** Starts the bridge as [caller] would, returning the activity. */
    private fun launch(intent: Intent, caller: String? = client): Nip55BridgeActivity {
        val controller = Robolectric.buildActivity(Nip55BridgeActivity::class.java, intent)
        shadowOf(controller.get()).setCallingPackage(caller)
        return controller.create().get()
    }

    private fun handedOver(activity: Activity): Pair<Intent, Map<String, Any?>> {
        val started = shadowOf(activity).nextStartedActivity
        assertNotNull("the bridge starts MainActivity", started)
        val request = Nip55Handoff.resolve(started.getStringExtra("requestToken"))
        assertNotNull("the handoff is registered", request)
        return started to request!!
    }

    @Test
    fun registersTheRequestWithTheCallerAndroidReports() {
        val activity = launch(nostrsigner("get_public_key"))

        val (_, request) = handedOver(activity)
        assertEquals("get_public_key", request["type"])
        assertEquals(client, request["callingPackage"])
        assertEquals(certOf(clientSignature), request["callerCertificateSha256"])
    }

    @Test
    fun identityExtrasCannotOverrideTheAttestedCaller() {
        installPackage("com.vitorpamplona.amethyst", Signature("deadbeef"))
        val forged = nostrsigner("get_public_key").apply {
            putExtra("callingPackage", "com.vitorpamplona.amethyst")
            putExtra("callerCertificateSha256", certOf(Signature("deadbeef")))
            putExtra("callerAppLabel", "Amethyst")
        }

        val (_, request) = handedOver(launch(forged))

        assertEquals(client, request["callingPackage"])
        assertEquals(certOf(clientSignature), request["callerCertificateSha256"])
    }

    @Test
    fun handsMainActivityOnlyTheToken() {
        val signEvent = nostrsigner("sign_event").apply {
            putExtra("content", """{"kind":1,"content":"hi","tags":[]}""")
        }

        val (started, request) = handedOver(launch(signEvent))

        assertEquals(MainActivity::class.java.name, started.component?.className)
        assertEquals(setOf("requestToken"), started.extras!!.keySet())
        assertEquals("""{"kind":1,"content":"hi","tags":[]}""", request["content"])
    }

    @Test
    fun marksBrowsableRequestsAsTheBrowserFlow() {
        val (_, request) = handedOver(launch(nostrsigner("get_public_key", browsable = true)))
        assertEquals(true, request["isBrowserFlow"])

        val (_, appRequest) = handedOver(launch(nostrsigner("get_public_key")))
        assertEquals(false, appRequest["isBrowserFlow"])
    }

    @Test
    fun readsARequestSentAsUrlParametersTheWayBrowsersSendIt() {
        val event = Uri.encode("""{"kind":1,"content":"hi","tags":[]}""")
        val url = Intent(
            Intent.ACTION_VIEW,
            Uri.parse(
                "nostrsigner:$event?compressionType=none&returnType=signature&type=sign_event" +
                    "&callbackUrl=https%3A%2F%2Fclient.example%2Fcb%3Fevent%3D",
            ),
        ).addCategory(Intent.CATEGORY_BROWSABLE)

        val (_, request) = handedOver(launch(url))

        assertEquals("sign_event", request["type"])
        assertEquals("""{"kind":1,"content":"hi","tags":[]}""", request["content"])
        assertEquals("https://client.example/cb?event=", request["callbackUrl"])
        assertEquals("signature", request["returnType"])
        assertEquals("none", request["compressionType"])
        assertEquals(true, request["isBrowserFlow"])
    }

    @Test
    fun withNoCallingPackageTheCallerIsUnknownNotSymudol() {
        // startActivity (not for result) with setPackage: Android reports no caller (#11).
        val appId = BuildConfig.APPLICATION_ID
        val intent = nostrsigner("get_public_key").setPackage(appId)

        val (_, request) = handedOver(launch(intent, caller = null))

        assertNull(request["callingPackage"])
        assertNull(request["callerCertificateSha256"])
        assertNull(request["callerAppLabel"])
        assertEquals("the target is kept only as data", appId, request["intentPackage"])
    }

    @Test
    fun symudolAsItsOwnCallerIsUnknown() {
        val (_, request) = handedOver(launch(nostrsigner("get_public_key"), caller = BuildConfig.APPLICATION_ID))

        assertNull(request["callingPackage"])
        assertNull(request["callerCertificateSha256"])
    }

    @Test
    fun anUnknownCallerIsStillRateLimited() {
        repeat(3) { handedOver(launch(nostrsigner("sign_message"), caller = null)) }

        val fourth = launch(nostrsigner("sign_message"), caller = null)

        assertEquals("rate_limited", shadowOf(fourth).resultIntent.getStringExtra("rejected"))
    }

    @Test
    fun rateLimitsBurstsFromOneClient() {
        repeat(3) { handedOver(launch(nostrsigner("sign_message"))) }

        val fourth = launch(nostrsigner("sign_message"))

        assertNull(shadowOf(fourth).nextStartedActivity)
        assertEquals(Activity.RESULT_CANCELED, shadowOf(fourth).resultCode)
        assertEquals("rate_limited", shadowOf(fourth).resultIntent.getStringExtra("rejected"))
    }

    @Test
    fun ignoresIntentsThatAreNotNostrsignerViews() {
        val activity = launch(Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")))

        assertNull(shadowOf(activity).nextStartedActivity)
        assertTrue(activity.isFinishing)
    }
}
