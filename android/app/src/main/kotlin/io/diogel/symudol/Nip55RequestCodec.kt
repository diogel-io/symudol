package io.diogel.symudol

import android.database.MatrixCursor
import android.net.Uri
import io.diogel.symudol.BuildConfig

object Nip55RequestCodec {

    // ── Pubkey normalization ──────────────────────────────────────────────

    /**
     * Normalize a public key that may be either 64-char lowercase hex or an
     * NIP-19 npub1... bech32 string. Returns lowercase hex on success,
     * null for blank/invalid input.
     *
     * Only npub is accepted; nprofile, nevent, and other NIP-19 entity types
     * are rejected — NIP-55 pubkey fields are always plain public keys.
     */
    fun normalizeHexOrNpub(value: String?): String? {
        val trimmed = value?.trim()?.lowercase() ?: return null
        if (trimmed.isEmpty()) return null
        if (trimmed.length == 64 && trimmed.all { it in '0'..'9' || it in 'a'..'f' }) {
            return trimmed
        }
        if (trimmed.startsWith("npub1")) {
            return decodeNpub(trimmed)
        }
        return null
    }

    // Minimal bech32 decoder for npub only. Decodes the 32-byte public key
    // from an npub1... string without an external dependency.
    private fun decodeNpub(lower: String): String? {
        // npub bech32 = "npub" + "1" + <52 data chars> + <6 checksum chars> = 63 total
        if (!lower.startsWith("npub1")) return null
        val encoded = lower.substring(5) // drop "npub1"
        if (encoded.length < 7) return null // need at least some data + 6 checksum

        val charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        val decoded5 = mutableListOf<Int>()
        for (ch in encoded) {
            val idx = charset.indexOf(ch)
            if (idx < 0) return null
            decoded5.add(idx)
        }

        // Verify bech32 checksum before accepting the data.
        if (!bech32VerifyChecksum("npub", decoded5)) return null

        // Drop last 6 groups (checksum) to get data groups
        val dataGroups = decoded5.dropLast(6)

        // Convert 5-bit groups to 8-bit bytes
        val bytes = mutableListOf<Int>()
        var acc = 0
        var bits = 0
        for (v5 in dataGroups) {
            acc = (acc shl 5) or v5
            bits += 5
            while (bits >= 8) {
                bits -= 8
                bytes.add((acc shr bits) and 0xFF)
            }
        }
        // Remaining bits must be zero padding (not a full byte)
        if (bits >= 5 || (acc and ((1 shl bits) - 1)) != 0) return null
        if (bytes.size != 32) return null
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun bech32VerifyChecksum(hrp: String, data: List<Int>): Boolean {
        val values = buildList {
            hrp.forEach { add(it.code ushr 5) }
            add(0)
            hrp.forEach { add(it.code and 31) }
            addAll(data)
        }
        val gen = intArrayOf(0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3)
        var c = 1
        for (v in values) {
            val b = c ushr 25
            c = (c and 0x1ffffff) shl 5 xor v
            for (i in 0..4) {
                if ((b ushr i) and 1 != 0) c = c xor gen[i]
            }
        }
        return c == 1
    }

    // Authorities are derived from the installed application id so that debug,
    // release, and flavored builds all expose the correct content:// authority.
    // Clients (Amethyst, Quartz) build URIs as content://<signerPackage>.SIGN_EVENT;
    // using the selected signer's package name — this keeps that contract intact.
    val AUTHORITY_SIGN_EVENT = "${BuildConfig.APPLICATION_ID}.SIGN_EVENT"
    val AUTHORITY_SIGN_MESSAGE = "${BuildConfig.APPLICATION_ID}.SIGN_MESSAGE"
    val AUTHORITY_NIP44_ENCRYPT = "${BuildConfig.APPLICATION_ID}.NIP44_ENCRYPT"
    val AUTHORITY_NIP44_DECRYPT = "${BuildConfig.APPLICATION_ID}.NIP44_DECRYPT"
    val AUTHORITY_NIP04_ENCRYPT = "${BuildConfig.APPLICATION_ID}.NIP04_ENCRYPT"
    val AUTHORITY_NIP04_DECRYPT = "${BuildConfig.APPLICATION_ID}.NIP04_DECRYPT"
    val AUTHORITY_DECRYPT_ZAP_EVENT = "${BuildConfig.APPLICATION_ID}.DECRYPT_ZAP_EVENT"
    val AUTHORITY_GET_PUBLIC_KEY = "${BuildConfig.APPLICATION_ID}.GET_PUBLIC_KEY"
    val AUTHORITY_PING = "${BuildConfig.APPLICATION_ID}.PING"

    private val supportedAuthorities = setOf(
        AUTHORITY_SIGN_EVENT,
        AUTHORITY_SIGN_MESSAGE,
        AUTHORITY_NIP44_ENCRYPT,
        AUTHORITY_NIP44_DECRYPT,
        AUTHORITY_NIP04_ENCRYPT,
        AUTHORITY_NIP04_DECRYPT,
        AUTHORITY_DECRYPT_ZAP_EVENT,
        AUTHORITY_GET_PUBLIC_KEY,
        AUTHORITY_PING,
    )

    fun isSupportedAuthority(authority: String?): Boolean {
        return authority != null && supportedAuthorities.contains(authority)
    }

    fun methodFor(uri: Uri): String? {
        return when (uri.authority) {
            AUTHORITY_SIGN_EVENT -> "sign_event"
            AUTHORITY_SIGN_MESSAGE -> "sign_message"
            AUTHORITY_NIP44_ENCRYPT -> "nip44_encrypt"
            AUTHORITY_NIP44_DECRYPT -> "nip44_decrypt"
            AUTHORITY_NIP04_ENCRYPT -> "nip04_encrypt"
            AUTHORITY_NIP04_DECRYPT -> "nip04_decrypt"
            AUTHORITY_DECRYPT_ZAP_EVENT -> "decrypt_zap_event"
            AUTHORITY_GET_PUBLIC_KEY -> "get_public_key"
            AUTHORITY_PING -> "ping"
            else -> null
        }
    }

    fun eventJsonFromProjection(projection: Array<out String>?): String? {
        return projection?.firstOrNull()?.takeIf { it.isNotBlank() }
    }

    fun payloadFromProjection(projection: Array<out String>?): String? {
        return projection?.firstOrNull()?.takeIf { it.isNotBlank() }
    }

    fun peerPubkeyFromProjection(projection: Array<out String>?): String? {
        val raw = projection?.getOrNull(1)?.takeIf { it.isNotBlank() } ?: return null
        return normalizeHexOrNpub(raw)
    }

    fun currentUserFromProjection(projection: Array<out String>?, method: String? = null): String? {
        return when (method) {
            // Amethyst/Quartz probes GET_PUBLIC_KEY with projection ["login"].
            // That value is not a NIP-55 current_user pubkey, so never forward it
            // into Dart as currentUser or the parser will correctly reject it.
            "get_public_key" -> null
            "sign_event", "sign_message", "decrypt_zap_event" -> {
                // Dark-Wisp sends [payload, "", current_user] — prefer index 2 when
                // present and nonblank; fall back to index 1 for legacy [payload, current_user]
                val atTwo = projection?.getOrNull(2)?.takeIf { it.isNotBlank() }
                val atOne = projection?.getOrNull(1)?.takeIf { it.isNotBlank() }
                normalizeHexOrNpub(atTwo ?: atOne)
            }
            else -> normalizeHexOrNpub(projection?.getOrNull(2)?.takeIf { it.isNotBlank() })
        }
    }

    fun zapCurrentUserFromProjection(projection: Array<out String>?): String? {
        return currentUserFromProjection(projection, "decrypt_zap_event")
    }

    /**
     * Rejection cursor with no explicit reason — column value is boolean true.
     * Used for remembered rejects where the reason is implicit.
     */
    fun rejectedCursor(): MatrixCursor {
        return MatrixCursor(arrayOf("rejected")).apply {
            addRow(arrayOf(true))
        }
    }

    /**
     * Rejection cursor with an explicit reason string.
     * If [reason] is blank or the default "rejected", falls back to boolean true
     * so callers that only test for column presence keep working.
     */
    fun rejectedCursor(reason: String): MatrixCursor {
        val value: Any = if (reason.isBlank() || reason == "rejected") true else reason
        return MatrixCursor(arrayOf("rejected")).apply {
            addRow(arrayOf(value))
        }
    }

    fun signEventCursor(signature: String, eventJson: String): MatrixCursor {
        return MatrixCursor(arrayOf("signature", "result", "event")).apply {
            addRow(arrayOf(signature, signature, eventJson))
        }
    }

    fun operationResultCursor(result: String): MatrixCursor {
        // Non-signing operations return only "result" and "event" columns.
        // "signature" is intentionally absent — that column is only meaningful
        // for sign_event; placing a pubkey or plaintext there is semantically wrong.
        return MatrixCursor(arrayOf("result", "event")).apply {
            addRow(arrayOf(result, result))
        }
    }
}
