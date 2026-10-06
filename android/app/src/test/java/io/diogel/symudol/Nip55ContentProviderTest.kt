package io.diogel.symudol

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.content.pm.SigningInfo
import android.database.Cursor
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.MessageDigest

/**
 * The real NIP-55 ContentProvider on Robolectric (#68): what it answers in the background, with no
 * screen, for which caller and which remembered decision.
 */
@RunWith(RobolectricTestRunner::class)
class Nip55ContentProviderTest {
    // The well-known secp256k1 test keypair (also used by Nip55NativeCryptoTest).
    private val privKey = ByteArray(32).also { it[31] = 1 }
    private val pubKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    private val client = "com.example.client"
    private val clientSignature = Signature("cafebabe")
    private val appId = BuildConfig.APPLICATION_ID

    private lateinit var context: Context
    private lateinit var provider: Nip55ContentProvider

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // API 28+ reads signingInfo (GET_SIGNING_CERTIFICATES); older APIs read signatures.
        val signing = SigningInfo().also { shadowOf(it).setSignatures(arrayOf(clientSignature)) }
        val info = PackageInfo().apply {
            packageName = client
            signingInfo = signing
            @Suppress("DEPRECATION")
            signatures = arrayOf(clientSignature)
        }
        shadowOf(context.packageManager).installPackage(info)
        provider = Robolectric.setupContentProvider(Nip55ContentProvider::class.java, "$appId.SIGN_EVENT")
        shadowOf(provider).setCallingPackage(client)
        Nip55PermissionMirror(context).setActiveIdentityPubkey(pubKey)
        Nip55CryptoBridge.clock = { now }
        Nip55CryptoBridge.setActiveKey(privKey, pubKey, "local-1")
        grants()
    }

    private var now = 1_000_000L

    @After
    fun tearDown() {
        Nip55ProviderBridge.detach(flutterChannel)
        Nip55CryptoBridge.clearActiveKey()
        Nip55CryptoBridge.clock = { android.os.SystemClock.elapsedRealtime() }
        Nip55PermissionMirror(context).clearAll()
    }

    private fun cert(signature: Signature = clientSignature) =
        MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            .joinToString(":") { "%02X".format(it) }

    /** Remembered decisions, as the Dart side syncs them. */
    private fun grants(vararg grants: JSONObject) {
        Nip55PermissionMirror(context).syncGrants(JSONArray(grants.toList()).toString())
    }

    private fun grant(
        type: String,
        kind: Int? = null,
        decision: String = "allow",
        certificate: String? = cert(),
    ) = JSONObject().apply {
        put("id", "g-$type-$kind-$decision")
        put("identityPubkey", pubKey)
        put("packageName", client)
        put("certificateSha256", certificate ?: JSONObject.NULL)
        put("scope", JSONObject().apply {
            put("type", type)
            if (kind != null) put("kind", kind)
        })
        put("decision", decision)
        put("expiresAt", JSONObject.NULL)
    }

    private fun event(kind: Int) = """{"kind":$kind,"content":"hi","tags":[],"created_at":1700000000}"""

    private fun signEvent(eventJson: String): Cursor? = provider.query(
        Uri.parse("content://$appId.SIGN_EVENT"), arrayOf(eventJson, "", pubKey), null, null, null,
    )

    private fun signMessage(message: String): Cursor? = provider.query(
        Uri.parse("content://$appId.SIGN_MESSAGE"), arrayOf(message, "", pubKey), null, null, null,
    )

    private fun sha256Hex(text: String) = MessageDigest.getInstance("SHA-256").digest(text.toByteArray())
        .joinToString("") { "%02x".format(it) }

    private fun Cursor.only(column: String): String? {
        assertTrue(moveToFirst())
        return getString(getColumnIndexOrThrow(column))
    }

    @Test
    fun pingAnswersPong() {
        val cursor = provider.query(Uri.parse("content://$appId.PING"), null, null, null, null)
        assertEquals("pong", cursor!!.only("result"))
    }

    @Test
    fun withNoRememberedDecisionTheClientIsSentToTheApp() {
        // null: the client falls back to the intent, and the user sees the request.
        assertNull(signEvent(event(1)))
    }

    @Test
    fun aRememberedKindIsSignedAndOnlyThatKind() {
        grants(grant("sign_event", kind = 1))

        val cursor = signEvent(event(1))!!
        val signed = JSONObject(cursor.only("event")!!)
        val signature = cursor.getString(cursor.getColumnIndexOrThrow("signature"))
        assertEquals(1, signed.getInt("kind"))
        assertEquals(pubKey, signed.getString("pubkey"))
        assertTrue("the signature verifies", Schnorr.verify(signature, signed.getString("id"), pubKey))
        assertEquals(eventId(signed), signed.getString("id"))

        assertNull("kind 0 was not remembered", signEvent(event(0)))
    }

    @Test
    fun aBroadAllowSignsNothing() {
        // #5: an "any kind" allow must never sign in the background.
        grants(grant("sign_event", kind = null))

        for (kind in listOf(0, 1, 3, 5)) assertNull("kind $kind", signEvent(event(kind)))
    }

    @Test
    fun aRememberedRejectionIsReturnedAsRejected() {
        grants(grant("sign_event", kind = 1, decision = "reject"))

        // NIP-55: a "rejected" column, true when there is no reason.
        assertEquals("true", signEvent(event(1))!!.only("rejected"))
    }

    @Test
    fun nothingIsSignedWhileLocked() {
        grants(grant("sign_event", kind = 1))
        Nip55CryptoBridge.clearActiveKey()

        assertNull(signEvent(event(1)))
    }

    @Test
    fun aGrantForAnotherCertificateDoesNotMatch() {
        // The same package name, signed by someone else: a different app.
        grants(grant("sign_event", kind = 1, certificate = cert(Signature("deadbeef"))))

        assertNull(signEvent(event(1)))
    }

    @Test
    fun aDifferentCallerDoesNotGetTheClientsDecisions() {
        grants(grant("sign_event", kind = 1))
        shadowOf(provider).setCallingPackage("com.example.other")

        assertNull(signEvent(event(1)))
    }

    @Test
    fun aRememberedSignMessageNeverSignsAnEventsHash() {
        // #8: an event serialisation passed to sign_message would yield a valid event signature.
        grants(grant("sign_message"))

        val cursor = signMessage("""[0,"$pubKey",1700000000,1,[],"hi"]""")

        assertEquals("refused", cursor!!.only("rejected"))
    }

    @Test
    fun aRememberedSignMessageStillSignsAnOrdinaryMessage() {
        grants(grant("sign_message"))

        val signature = signMessage("hello")!!.only("result")!!

        assertTrue("the signature verifies", Schnorr.verify(signature, sha256Hex("hello"), pubKey))
    }

    // ── How long the key lives (#9) ────────────────────────────────────────

    /** Records what is sent to Flutter, standing in for the engine's channel. */
    private val sentToFlutter = mutableListOf<String>()
    private val flutterChannel = MethodChannel(object : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) { sentToFlutter += channel }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            sentToFlutter += channel
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {}
    }, "io.diogel.symudol/nip55")

    @Test
    fun aRememberedKindIsNotSignedOnceTheKeyIsCleared() {
        grants(grant("sign_event", kind = 1))
        Nip55ProviderBridge.attach(flutterChannel)
        Nip55CryptoBridge.clearActiveKey()

        assertNull(signEvent(event(1)))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue("nothing is passed on to Flutter to sign", sentToFlutter.isEmpty())
    }

    @Test
    fun aRememberedKindIsSignedBeforeTheLockDeadline() {
        grants(grant("sign_event", kind = 1))
        Nip55CryptoBridge.setLockDeadline(60_000)

        now += 59_999

        assertNotNull(signEvent(event(1))!!.only("signature"))
    }

    @Test
    fun nothingIsSignedOnceTheLockDeadlineHasPassed() {
        grants(grant("sign_event", kind = 1), grant("sign_message"))
        Nip55ProviderBridge.attach(flutterChannel)
        Nip55CryptoBridge.setLockDeadline(60_000)

        now += 60_000

        assertNull(signEvent(event(1)))
        assertNull(signMessage("hello"))
        assertFalse("the key is gone", Nip55CryptoBridge.hasActiveKey)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue("nothing is passed on to Flutter to sign", sentToFlutter.isEmpty())
    }

    @Test
    fun returningToTheForegroundRemovesTheDeadline() {
        grants(grant("sign_event", kind = 1))
        Nip55CryptoBridge.setLockDeadline(60_000)
        Nip55CryptoBridge.clearLockDeadline()

        now += 120_000

        assertNotNull(signEvent(event(1)))
    }

    // ── The request's account and kind (#10) ───────────────────────────────

    private val otherPubKey = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
    private val npub = "npub10xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqpkge6d"
    private val otherNpub = "npub1ccz8l9zpa47k6vz9gphftsrumpw80rjt3nhnefat4symjhrsnmjs38mnyd"

    private fun query(authority: String, vararg projection: String): Cursor? = provider.query(
        Uri.parse("content://$appId.$authority"), arrayOf(*projection), null, null, null,
    )

    @Test
    fun aRequestForAnotherAccountIsNotAnswered() {
        grants(grant("sign_event", kind = 1))

        assertNull("current_user at index 2", query("SIGN_EVENT", event(1), "", otherPubKey))
        assertNull("legacy current_user at index 1", query("SIGN_EVENT", event(1), otherPubKey))
        assertNull("as an npub", query("SIGN_EVENT", event(1), "", otherNpub))
    }

    @Test
    fun anUnreadableCurrentUserIsNotAnswered() {
        grants(grant("sign_event", kind = 1))

        assertNull(query("SIGN_EVENT", event(1), "", "not-a-pubkey"))
        assertNull(query("SIGN_EVENT", event(1), "", "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8g"))
    }

    @Test
    fun theActiveAccountOrNoneIsAnswered() {
        grants(grant("sign_event", kind = 1))

        assertNotNull("hex", query("SIGN_EVENT", event(1), "", pubKey))
        assertNotNull("upper-case hex", query("SIGN_EVENT", event(1), "", pubKey.uppercase()))
        assertNotNull("npub", query("SIGN_EVENT", event(1), "", npub))
        assertNotNull("no current_user", query("SIGN_EVENT", event(1)))
        assertNotNull("blank current_user", query("SIGN_EVENT", event(1), "", ""))
    }

    @Test
    fun otherMethodsCheckTheAccountToo() {
        grants(grant("sign_message"), grant("nip44_encrypt"))

        assertNull(query("SIGN_MESSAGE", "hello", "", otherPubKey))
        assertNull(query("NIP44_ENCRYPT", "hello", otherPubKey, otherPubKey))
        assertNotNull(query("SIGN_MESSAGE", "hello", "", pubKey))
        assertNotNull(query("NIP44_ENCRYPT", "hello", otherPubKey, pubKey))
    }

    @Test
    fun anEventWithoutAnIntegerKindIsNotSigned() {
        // A remembered kind-0 grant must not sign an event with no kind as kind 0.
        grants(grant("sign_event", kind = 0), grant("sign_event", kind = 1))

        assertNull("no kind", signEvent("""{"content":"hi","tags":[],"created_at":1700000000}"""))
        assertNull("string kind", signEvent("""{"kind":"1","content":"hi","tags":[],"created_at":1700000000}"""))
        assertNull("float kind", signEvent("""{"kind":1.5,"content":"hi","tags":[],"created_at":1700000000}"""))
        assertNull("null kind", signEvent("""{"kind":null,"content":"hi","tags":[],"created_at":1700000000}"""))
        assertNotNull("kind 0 itself still signs", signEvent(event(0)))
    }

    private fun eventId(event: JSONObject): String {
        val serialised = JSONArray().apply {
            put(0); put(event.getString("pubkey")); put(event.getLong("created_at"))
            put(event.getInt("kind")); put(event.getJSONArray("tags")); put(event.getString("content"))
        }.toString().replace("\\/", "/")
        return MessageDigest.getInstance("SHA-256").digest(serialised.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    /** BIP-340 verification, from the curve operations the app ships. */
    private object Schnorr {
        fun verify(signatureHex: String, messageHex: String, pubkeyHex: String): Boolean {
            if (signatureHex.length != 128) return false
            val p = Secp256k1.pointFromHex(pubkeyHex) ?: return false
            val r = BigInteger(signatureHex.substring(0, 64), 16)
            val s = BigInteger(signatureHex.substring(64), 16)
            if (r >= Secp256k1.p || s >= Secp256k1.n) return false
            val e = BigInteger(1, taggedHash(
                "BIP0340/challenge",
                hex(signatureHex.substring(0, 64)) + hex(pubkeyHex) + hex(messageHex),
            )).mod(Secp256k1.n)
            val sG = Secp256k1.multiply(Secp256k1.G, s) ?: return false
            val eP = Secp256k1.multiply(p, Secp256k1.n.subtract(e)) ?: return false
            val point = Secp256k1.add(sG, eP) ?: return false
            return point.y.mod(Secp256k1.TWO) == BigInteger.ZERO && point.x == r
        }

        private fun taggedHash(tag: String, message: ByteArray): ByteArray {
            val sha = MessageDigest.getInstance("SHA-256")
            val tagHash = sha.digest(tag.toByteArray())
            return MessageDigest.getInstance("SHA-256").digest(tagHash + tagHash + message)
        }

        private fun hex(value: String) = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
}
