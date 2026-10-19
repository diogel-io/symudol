package io.diogel.symudol

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.content.pm.SigningInfo
import android.net.Uri
import android.util.Log
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
import org.robolectric.shadows.ShadowLog
import java.io.File
import java.security.MessageDigest

/**
 * What the NIP-55 code writes to the system log (SR-21, #14): never a request's content,
 * plaintext or ciphertext, and nothing but fixed text and an exception's class name at warning
 * level and above, which release builds keep.
 */
@RunWith(RobolectricTestRunner::class)
class Nip55LoggingTest {
    private val privKey = ByteArray(32).also { it[31] = 1 }
    private val pubKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    private val otherPubKey = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
    private val client = "com.example.client"
    private val clientSignature = Signature("cafebabe")
    private val appId = BuildConfig.APPLICATION_ID
    private val secret = "SECRET-MARKER-7f3a"

    private lateinit var context: Context
    private lateinit var provider: Nip55ContentProvider

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
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
        Nip55ContentProvider.nativeCryptoSound = { true }
        ShadowLog.reset()
    }

    @After
    fun tearDown() {
        Nip55ContentProvider.nativeCryptoSound = { Nip55NativeCrypto.selfTestPassed }
        Nip55CryptoBridge.clearActiveKey()
        Nip55PermissionMirror(context).clearAll()
        ShadowLog.reset()
    }

    private val cert
        get() = MessageDigest.getInstance("SHA-256").digest(clientSignature.toByteArray())
            .joinToString(":") { "%02X".format(it) }

    private fun grant(type: String, kind: Int? = null) = JSONObject().apply {
        put("id", "g-$type-$kind")
        put("identityPubkey", pubKey)
        put("packageName", client)
        put("certificateSha256", cert)
        put("scope", JSONObject().apply {
            put("type", type)
            if (kind != null) put("kind", kind)
        })
        put("decision", "allow")
        put("expiresAt", JSONObject.NULL)
    }

    private fun grants(vararg grants: JSONObject) =
        Nip55PermissionMirror(context).syncGrants(JSONArray(grants.toList()).toString())

    private fun query(authority: String, vararg projection: String) = provider.query(
        Uri.parse("content://$appId.$authority"), arrayOf(*projection), null, null, null,
    )

    private fun assertLogsKeepSecrets() {
        val logs = ShadowLog.getLogs()
        assertTrue("the flows above log something", logs.isNotEmpty())
        for (item in logs) {
            assertFalse("logged content: ${item.msg}", item.msg.contains(secret))
            assertNull("logged a stack trace: ${item.msg}", item.throwable)
            if (item.type >= Log.WARN) {
                assertFalse("a caller's package at ${item.type}: ${item.msg}", item.msg.contains(client))
            }
        }
    }

    @Test
    fun signingRequestsDoNotLogTheEvent() {
        grants(grant("sign_event", kind = 1))

        query("SIGN_EVENT", """{"kind":1,"content":"$secret","tags":[],"created_at":1700000000}""", "", pubKey)
        query("SIGN_EVENT", """{"kind":"$secret"}""", "", pubKey)

        assertLogsKeepSecrets()
    }

    @Test
    fun encryptionAndDecryptionDoNotLogPlaintextOrCiphertext() {
        grants(grant("nip44_encrypt"), grant("nip44_decrypt"), grant("nip04_decrypt"), grant("decrypt_zap_event"))

        query("NIP44_ENCRYPT", secret, otherPubKey, pubKey)
        query("NIP44_DECRYPT", "$secret-not-ciphertext", otherPubKey, pubKey)
        query("NIP04_DECRYPT", "$secret?iv=$secret", otherPubKey, pubKey)
        query("DECRYPT_ZAP_EVENT", """{"content":"$secret","tags":[["P","$secret"]]""", "", pubKey)

        assertLogsKeepSecrets()
    }

    @Test
    fun malformedGrantsDoNotLogGrantData() {
        Nip55PermissionMirror(context).syncGrants("""[{"packageName":"$secret"""")
        Nip55PermissionMirror(context).syncGrants("""[{"packageName":"$secret"}, "$secret"]""")
        Nip55PermissionMirror(context).deleteAllForPackage(client)

        assertLogsKeepSecrets()
    }

    @Test
    fun aWarningCarriesTheExceptionClassNotItsMessage() {
        val line = DiogelLog.line("decrypt failed", IllegalArgumentException(secret))

        assertEquals("decrypt failed (IllegalArgumentException)", line)
        assertEquals("plain", DiogelLog.line("plain", null))
    }

    @Test
    fun onlyDiogelLogWritesToTheSystemLog() {
        val sources = File("src/main/kotlin/io/diogel/symudol").listFiles { f -> f.extension == "kt" }
        assertNotNull("run from android/app", sources)
        // Everything that reaches logcat: R8 strips only Log.v/d/i, and stack traces quote messages.
        val direct = Regex("""\bLog\.(v|d|i|w|e|wtf|println)\(|\.printStackTrace\(|\bSystem\.(out|err)\b""")
        val offenders = sources!!.filter { it.name != "DiogelLog.kt" && direct.containsMatchIn(it.readText()) }

        assertEquals("call DiogelLog instead of android.util.Log", emptyList<String>(), offenders.map { it.name })
    }
}
