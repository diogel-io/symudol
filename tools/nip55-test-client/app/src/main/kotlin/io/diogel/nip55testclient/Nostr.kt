package io.diogel.nip55testclient

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** NIP-01 helpers, free of Android APIs so the JVM tests can run them. */
object Nostr {
    /** A valid secp256k1 x-only public key (the generator's x), used as the encryption peer. */
    const val PEER_PUBKEY = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    fun isHex(value: String?, length: Int): Boolean =
        value != null && value.length == length && value.all { it in '0'..'9' || it in 'a'..'f' }

    /** An unsigned event for Symudol to complete and sign. */
    fun unsignedEvent(kind: Int, content: String, createdAt: Long): String =
        JSONObject()
            .put("kind", kind)
            .put("content", content)
            .put("tags", JSONArray())
            .put("created_at", createdAt)
            .toString()

    /**
     * The NIP-01 serialisation an event id is the sha256 of: `[0,pubkey,created_at,kind,tags,content]`.
     * Sent as a `sign_message` it must be refused, or it would sign an event (#8).
     */
    fun serialise(pubkey: String, createdAt: Long, kind: Int, tags: List<List<String>>, content: String): String {
        val tagsJson = tags.joinToString(",", "[", "]") { tag -> tag.joinToString(",", "[", "]") { quote(it) } }
        return "[0,${quote(pubkey)},$createdAt,$kind,$tagsJson,${quote(content)}]"
    }

    fun sha256Hex(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /**
     * Why [eventJson] is not an event signed by [pubkey] with [kind] and [content], or null when
     * it is. Checks the shape and that the id is the hash of the fields; it does not verify the
     * Schnorr signature, which Symudol's vault service already does before returning it.
     */
    fun signedEventProblem(eventJson: String?, pubkey: String, kind: Int, content: String): String? {
        if (eventJson.isNullOrBlank()) return "no event returned"
        val event = try {
            JSONObject(eventJson)
        } catch (_: Exception) {
            return "event is not JSON"
        }
        val id = event.optString("id")
        val sig = event.optString("sig")
        val eventPubkey = event.optString("pubkey")
        return when {
            eventPubkey != pubkey -> "event pubkey $eventPubkey is not the active identity"
            event.optInt("kind", -1) != kind -> "event kind ${event.opt("kind")} is not $kind"
            event.optString("content") != content -> "event content changed"
            !isHex(id, 64) -> "event id is not 64 hex"
            !isHex(sig, 128) -> "event sig is not 128 hex"
            computedId(event) != id -> "event id is not the hash of its fields"
            else -> null
        }
    }

    private fun computedId(event: JSONObject): String? = try {
        val tagsJson = event.getJSONArray("tags")
        val tags = (0 until tagsJson.length()).map { i ->
            val tag = tagsJson.getJSONArray(i)
            (0 until tag.length()).map { j -> tag.getString(j) }
        }
        sha256Hex(
            serialise(
                event.getString("pubkey"),
                event.getLong("created_at"),
                event.getInt("kind"),
                tags,
                event.getString("content"),
            ),
        )
    } catch (_: Exception) {
        null
    }

    /** A JSON string with NIP-01's escaping: only these characters are escaped. */
    private fun quote(value: String): String {
        val out = StringBuilder("\"")
        for (c in value) {
            when (c) {
                '\n' -> out.append("\\n")
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> out.append(c)
            }
        }
        return out.append('"').toString()
    }
}
