package io.diogel.symudol

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * A vault wipe (diogel-io/symudol#20) leaves nothing the ContentProvider could act on: no grant
 * and no active pubkey.
 */
@RunWith(RobolectricTestRunner::class)
class Nip55PermissionMirrorWipeTest {
    private val identity = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    private val client = "com.example.client"
    // A grant without a certificate matches no caller (#84).
    private val clientCert = "AA:BB:CC"
    private val noInputs = Nip55PermissionMirror.ScopeInputs(null, null, null)

    private lateinit var context: Context
    private lateinit var mirror: Nip55PermissionMirror

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        mirror = Nip55PermissionMirror(context)
        val grant = JSONObject()
            .put("id", "grant-1")
            .put("identityPubkey", identity)
            .put("packageName", client)
            .put("certificateSha256", clientCert)
            .put("scope", JSONObject().put("type", "get_public_key"))
            .put("decision", "allow")
        mirror.syncGrants(JSONArray().put(grant).toString())
        mirror.setActiveIdentityPubkey(identity)
    }

    @After
    fun tearDown() {
        mirror.wipe()
    }

    @Test
    fun wipe_clearsGrantsAndActivePubkey() {
        assertTrue(mirror.rememberedDecision(client, "get_public_key", identity, noInputs, clientCert) == "allow")

        assertTrue(mirror.wipe())

        assertTrue(mirror.listGrants().isEmpty())
        assertFalse(mirror.rememberedDecision(client, "get_public_key", identity, noInputs, clientCert) == "allow")
        assertNull(mirror.getActiveIdentityPubkey())
    }

    @Test
    fun wipe_isVisibleToANewMirrorInstance() {
        mirror.wipe()

        // MainActivity and the ContentProvider each make their own instance.
        val other = Nip55PermissionMirror(context)
        assertTrue(other.listGrants().isEmpty())
        assertNull(other.getActiveIdentityPubkey())
    }

    @Test
    fun wipe_onEmptyMirror_succeeds() {
        mirror.wipe()

        assertTrue(mirror.wipe())
    }
}
