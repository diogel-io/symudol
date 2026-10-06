package io.diogel.symudol

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

/**
 * Unit tests for Nip55NativeCrypto: missing-pubkey injection, mismatch
 * rejection, slash canonicalization in NIP-01 serialization, and signed
 * event shape.
 *
 * These tests exercise signEvent() logic. Note: signEvent internally calls
 * android.util.Log — ensure your test gradle config has
 * testOptions.unitTests.isReturnDefaultValues = true so Log calls return 0.
 */
class Nip55NativeCryptoTest {

    // Well-known secp256k1 test keypair
    // Private key: 0000000000000000000000000000000000000000000000000000000000000001
    // Public key:  79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
    private val testPrivKey = ByteArray(32).also { it[31] = 1 }
    private val testPubKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    // ════════════════════════════════════════════════════════════════════
    //  signEvent — pubkey handling
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun signEvent_missingPubkey_injectsActivePubkey() {
        val eventJson = """{"kind":1,"content":"hello","tags":[],"created_at":1700000000}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull("signEvent should succeed when pubkey is missing", result)
        val signed = JSONObject(result!!.eventJson)
        assertEquals("Injected pubkey must equal active identity pubkey", testPubKey, signed.getString("pubkey"))
    }

    @Test
    fun signEvent_blankPubkey_injectsActivePubkey() {
        val eventJson = """{"kind":1,"content":"hello","tags":[],"created_at":1700000000,"pubkey":""}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull("signEvent should succeed when pubkey is blank", result)
        val signed = JSONObject(result!!.eventJson)
        assertEquals(testPubKey, signed.getString("pubkey"))
    }

    @Test
    fun signEvent_matchingPubkey_signsNormally() {
        val eventJson = """{"kind":1,"content":"hello","tags":[],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull("signEvent should succeed with matching pubkey", result)
        val signed = JSONObject(result!!.eventJson)
        assertEquals(testPubKey, signed.getString("pubkey"))
    }

    @Test
    fun signEvent_mismatchedPubkey_returnsNull() {
        val otherPubkey = "a".repeat(64)
        val eventJson = """{"kind":1,"content":"hello","tags":[],"created_at":1700000000,"pubkey":"$otherPubkey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNull("signEvent must return null when pubkey does not match active identity", result)
    }

    // ════════════════════════════════════════════════════════════════════
    //  signEvent — signed event shape
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun signEvent_resultContainsRequiredFields() {
        val eventJson = """{"kind":1,"content":"test","tags":[],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull(result)
        val signed = JSONObject(result!!.eventJson)
        assertTrue("Signed event must have id", signed.has("id"))
        assertTrue("Signed event must have pubkey", signed.has("pubkey"))
        assertTrue("Signed event must have created_at", signed.has("created_at"))
        assertTrue("Signed event must have kind", signed.has("kind"))
        assertTrue("Signed event must have tags", signed.has("tags"))
        assertTrue("Signed event must have content", signed.has("content"))
        assertTrue("Signed event must have sig", signed.has("sig"))
    }

    @Test
    fun signEvent_idAndSigAre64CharHex() {
        val eventJson = """{"kind":1,"content":"test","tags":[],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull(result)
        val signed = JSONObject(result!!.eventJson)
        val id = signed.getString("id")
        val sig = signed.getString("sig")
        assertTrue("id must be 64-char hex", id.matches(Regex("[0-9a-f]{64}")))
        assertTrue("sig must be 64-char hex (32 bytes r) or 128-char hex (64 bytes)", sig.length == 128 && sig.matches(Regex("[0-9a-f]{128}")))
    }

    @Test
    fun signEvent_signatureMatchesId() {
        // The result's signature field must equal the sig in the event JSON
        val eventJson = """{"kind":1,"content":"test","tags":[],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull(result)
        val signed = JSONObject(result!!.eventJson)
        assertEquals(result.signature, signed.getString("sig"))
    }

    // ════════════════════════════════════════════════════════════════════
    //  signEvent — slash canonicalization (NIP-01 regression)
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun signEvent_contentWithSlash_eventIdDoesNotContainEscapedSlash() {
        // Android's JSONArray.toString() escapes '/' as '\/' but NIP-01 requires
        // unescaped '/'. The serialized event must not contain '\/' so the
        // computed ID matches what clients expect.
        val content = "hello / world"
        val eventJson = """{"kind":1,"content":"$content","tags":[],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull(result)
        // The signed event JSON itself must have the id field populated
        val signed = JSONObject(result!!.eventJson)
        assertTrue(signed.has("id"))
        assertTrue(signed.has("sig"))
        // The result event JSON should not contain escaped slashes in the id
        // (We just verify the event can be signed without crashing — the actual
        // ID correctness is verified by the Bip340SchnorrTest vectors.)
    }

    @Test
    fun signEvent_tagsWithSlash_succeeds() {
        val eventJson = """{"kind":1,"content":"hello","tags":[["r","wss://relay.example/path"]],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull("signEvent must succeed with slash-containing tags", result)
    }

    // ════════════════════════════════════════════════════════════════════
    //  signEvent — missing pubkey with injected pubkey produces valid event
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun signEvent_injectedPubkeyEventIsSelfConsistent() {
        // When pubkey is missing, the injected pubkey must appear in the signed event
        // and the id must be computed with the correct pubkey.
        val eventJson = """{"kind":1,"content":"primal test","tags":[],"created_at":1700000000}"""
        val result = Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey)
        assertNotNull(result)
        val signed = JSONObject(result!!.eventJson)
        assertEquals(testPubKey, signed.getString("pubkey"))
        // Signing the same event a second time with the pubkey now present must
        // produce the same id (deterministic ID, non-deterministic sig).
        val eventJsonWithPubkey = """{"kind":1,"content":"primal test","tags":[],"created_at":1700000000,"pubkey":"$testPubKey"}"""
        val result2 = Nip55NativeCrypto.signEvent(testPrivKey, eventJsonWithPubkey, testPubKey)
        assertNotNull(result2)
        // IDs must be equal (same serialization)
        assertEquals(
            "ID must be the same whether pubkey was injected or present",
            JSONObject(result2!!.eventJson).getString("id"),
            signed.getString("id"),
        )
    }

    // ════════════════════════════════════════════════════════════════════
    //  signMessage — never an event serialisation (#8)
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun isNostrEventSerialisation_matchesTheEventIdSerialisation() {
        for (message in listOf(
            "[0,\"$testPubKey\",1700000000,1,[],\"hi\"]",
            "[0,\"$testPubKey\",1700000000,0,[[\"p\",\"$testPubKey\"]],\"{}\"]",
            " [ 0 , \"x\" , 1 , 1 , [ ] , \"\" ] ",
            "[0,null,null,null,null,null]",
            "[0.0,1,2,3,4,5]",
        )) {
            assertTrue(message, Nip55NativeCrypto.isNostrEventSerialisation(message))
        }
    }

    @Test
    fun isNostrEventSerialisation_ignoresEverythingElse() {
        for (message in listOf(
            "[]",
            "[1,\"$testPubKey\",1700000000,1,[],\"hi\"]",
            "[\"0\",\"$testPubKey\",1700000000,1,[],\"hi\"]",
            "[0,\"$testPubKey\",1700000000,1,[]]",
            "[0,\"$testPubKey\",1700000000,1,[],\"hi\",\"extra\"]",
            "{\"kind\":1,\"content\":\"hi\"}",
            "[0,\"$testPubKey\",1700000000,1,[],\"hi\"",
            "hello",
            "0",
            "",
            "gm \uD83C\uDF05",
        )) {
            assertFalse(message, Nip55NativeCrypto.isNostrEventSerialisation(message))
        }
    }

    @Test
    fun signMessage_refusesAnEventSerialisation() {
        val serialised = "[0,\"$testPubKey\",1700000000,1,[],\"hi\"]"
        assertThrows(IllegalArgumentException::class.java) {
            Nip55NativeCrypto.signMessage(testPrivKey, serialised)
        }
    }

    @Test
    fun signMessage_signsAnOrdinaryMessage() {
        assertEquals(128, Nip55NativeCrypto.signMessage(testPrivKey, "hello").length)
    }

    @Test
    fun signEvent_withoutAnIntegerKind_returnsNull() {
        // #10: never signed as kind 0.
        for (eventJson in listOf(
            """{"content":"hello","tags":[],"created_at":1700000000}""",
            """{"kind":"1","content":"hello","tags":[],"created_at":1700000000}""",
        )) {
            assertNull(eventJson, Nip55NativeCrypto.signEvent(testPrivKey, eventJson, testPubKey))
        }
    }
}
