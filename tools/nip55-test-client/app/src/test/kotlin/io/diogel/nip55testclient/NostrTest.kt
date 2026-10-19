package io.diogel.nip55testclient

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NostrTest {
    private val pubkey = "a".repeat(64)

    private fun signed(kind: Int = 1, content: String = "hello", tags: List<List<String>> = emptyList()): JSONObject {
        val createdAt = 1_700_000_000L
        val id = Nostr.sha256Hex(Nostr.serialise(pubkey, createdAt, kind, tags, content))
        return JSONObject()
            .put("id", id)
            .put("pubkey", pubkey)
            .put("created_at", createdAt)
            .put("kind", kind)
            .put("tags", JSONArray(tags.map { JSONArray(it) }))
            .put("content", content)
            .put("sig", "b".repeat(128))
    }

    @Test
    fun `serialise is the NIP-01 id array`() {
        assertEquals(
            """[0,"$pubkey",1700000000,1,[["e","x"],["p","y"]],"hi"]""",
            Nostr.serialise(pubkey, 1_700_000_000, 1, listOf(listOf("e", "x"), listOf("p", "y")), "hi"),
        )
    }

    @Test
    fun `serialise escapes only what NIP-01 escapes`() {
        assertEquals(
            """[0,"$pubkey",1,1,[],"a\nb\"c\\d\re\tf\bg\fh/é"]""",
            Nostr.serialise(pubkey, 1, 1, emptyList(), "a\nb\"c\\d\re\tf\bg\u000Ch/é"),
        )
    }

    @Test
    fun `zapRequest is a kind 9734 addressed by its p tag`() {
        val zap = JSONObject(Nostr.zapRequest(pubkey, "cipher?iv=abc", 1_700_000_000))

        assertEquals(9734, zap.getInt("kind"))
        assertEquals("cipher?iv=abc", zap.getString("content"))
        assertEquals("p", zap.getJSONArray("tags").getJSONArray(0).getString(0))
        assertEquals(pubkey, zap.getJSONArray("tags").getJSONArray(0).getString(1))
    }

    @Test
    fun `sha256Hex matches a known digest`() {
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            Nostr.sha256Hex("abc"),
        )
    }

    @Test
    fun `a well-formed signed event has no problem`() {
        assertNull(Nostr.signedEventProblem(signed().toString(), pubkey, 1, "hello"))
        val tagged = signed(tags = listOf(listOf("t", "nostr"))).toString()
        assertNull(Nostr.signedEventProblem(tagged, pubkey, 1, "hello"))
    }

    @Test
    fun `a tampered or wrong event is a problem`() {
        val event = signed()
        assertEquals("no event returned", Nostr.signedEventProblem(null, pubkey, 1, "hello"))
        assertEquals("event is not JSON", Nostr.signedEventProblem("{", pubkey, 1, "hello"))
        assertEquals(
            "event id is not the hash of its fields",
            Nostr.signedEventProblem(JSONObject(event.toString()).put("created_at", 1).toString(), pubkey, 1, "hello"),
        )
        assertTrue(Nostr.signedEventProblem(event.toString(), "c".repeat(64), 1, "hello")!!.contains("not the active identity"))
        assertEquals("event kind 1 is not 7", Nostr.signedEventProblem(event.toString(), pubkey, 7, "hello"))
        assertEquals("event content changed", Nostr.signedEventProblem(event.toString(), pubkey, 1, "bye"))
        assertEquals(
            "event sig is not 128 hex",
            Nostr.signedEventProblem(JSONObject(event.toString()).put("sig", "zz").toString(), pubkey, 1, "hello"),
        )
    }

    @Test
    fun `isHex wants lowercase hex of the exact length`() {
        assertTrue(Nostr.isHex("0123456789abcdef", 16))
        assertFalse(Nostr.isHex("0123456789ABCDEF", 16))
        assertFalse(Nostr.isHex("abc", 4))
        assertFalse(Nostr.isHex(null, 0))
    }

    @Test
    fun `an unsigned event carries the kind, content and an integer created_at`() {
        val event = JSONObject(Nostr.unsignedEvent(9999, "x", 42))
        assertEquals(9999, event.getInt("kind"))
        assertEquals("x", event.getString("content"))
        assertEquals(42L, event.get("created_at").toString().toLong())
        assertEquals(0, event.getJSONArray("tags").length())
    }

    @Test
    fun `the event serialisation sent to sign_message is what Symudol refuses`() {
        // Symudol's rule (isNostrEventSerialisation, #8): a six-element JSON array starting with 0.
        val message = JSONArray(Nostr.serialise(pubkey, 1, 1, emptyList(), "x"))
        assertEquals(6, message.length())
        assertEquals(0, message.getInt(0))
    }
}
