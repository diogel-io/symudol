package io.diogel.symudol

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.content.pm.SigningInfo
import android.database.Cursor
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
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
import java.security.MessageDigest

/**
 * The real NIP-55 ContentProvider on Robolectric (#68): what it answers in the background, with no
 * screen, for which caller and which remembered decision.
 */
@RunWith(RobolectricTestRunner::class)
class Nip55ContentProviderTest {
    // The well-known secp256k1 test keypair (also used by Nip55NativeCryptoTest).
    private val privKey = "0000000000000000000000000000000000000000000000000000000000000001"
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
        Nip55CryptoBridge.setActiveKey(privKey, pubKey, "local-1")
        grants()
    }

    @After
    fun tearDown() {
        Nip55CryptoBridge.clearActiveKey()
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

    // ── Current behaviour that other tickets change ────────────────────────
    // These record what the provider does today. The tickets named flip them.

    @Test
    fun currentBehaviour_anEventWithNoKindIsSignedAsKind0_seeIssue10() {
        // #10: a missing kind should not match a kind-0 grant; it should go to the app.
        grants(grant("sign_event", kind = 0))

        val cursor = signEvent("""{"content":"hi","tags":[],"created_at":1700000000}""")

        assertNotNull("#10 should make this null", cursor)
    }

    @Test
    fun currentBehaviour_aSignMessageGrantSignsAnEventsHash_seeIssue8() {
        // #8: an event serialisation passed to sign_message yields a valid event signature.
        grants(grant("sign_message"))
        val serialised = """[0,"$pubKey",1700000000,1,[],"hi"]"""

        val cursor = provider.query(
            Uri.parse("content://$appId.SIGN_MESSAGE"), arrayOf(serialised, "", pubKey), null, null, null,
        )

        assertNotNull("#8 should make this refuse", cursor)
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
