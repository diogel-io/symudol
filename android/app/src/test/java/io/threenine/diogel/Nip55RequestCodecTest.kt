package io.threenine.diogel

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Nip55RequestCodec: projection parsing, npub decoding,
 * current-user index selection, peer pubkey normalization, and rejected cursor
 * column values.
 *
 * These tests run on the JVM without Android SDK dependencies.
 */
class Nip55RequestCodecTest {

    // ── Known NIP-19 test vector ─────────────────────────────────────────
    // npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6
    // = hex 3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d
    private val knownHexPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
    private val knownNpub = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"

    // ════════════════════════════════════════════════════════════════════
    //  normalizeHexOrNpub
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun normalize_null_returnsNull() {
        assertNull(Nip55RequestCodec.normalizeHexOrNpub(null))
    }

    @Test
    fun normalize_blank_returnsNull() {
        assertNull(Nip55RequestCodec.normalizeHexOrNpub(""))
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("   "))
    }

    @Test
    fun normalize_lowercase64HexPubkey_returnsSame() {
        val hex = "a".repeat(64)
        assertEquals(hex, Nip55RequestCodec.normalizeHexOrNpub(hex))
    }

    @Test
    fun normalize_uppercase64HexPubkey_returnsLowercase() {
        val upper = "A".repeat(64)
        val expected = "a".repeat(64)
        assertEquals(expected, Nip55RequestCodec.normalizeHexOrNpub(upper))
    }

    @Test
    fun normalize_mixedCase64HexPubkey_returnsLowercase() {
        val mixed = "aAbBcCdDeEfF".repeat(4) + "0011223344556677"
        assertEquals(64, mixed.length)
        val result = Nip55RequestCodec.normalizeHexOrNpub(mixed)
        assertNotNull(result)
        assertEquals(mixed.lowercase(), result)
    }

    @Test
    fun normalize_validNpub_returnsHex() {
        val result = Nip55RequestCodec.normalizeHexOrNpub(knownNpub)
        assertEquals(knownHexPubkey, result)
    }

    @Test
    fun normalize_npubWithUpperCaseLetters_accepted() {
        // NIP-19 npub strings are lowercase by convention but normalization
        // should handle uppercase gracefully.
        val upper = knownNpub.uppercase()
        val result = Nip55RequestCodec.normalizeHexOrNpub(upper)
        assertEquals(knownHexPubkey, result)
    }

    @Test
    fun normalize_invalidNpub_returnsNull() {
        // Invalid characters in bech32 data section
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("npub1invalidXXXXXX"))
    }

    @Test
    fun normalize_nprofile_returnsNull() {
        // Only npub is accepted; nprofile and other NIP-19 entity types are rejected
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("nprofile1qqsfwl40"))
    }

    @Test
    fun normalize_nonsense_returnsNull() {
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("not-a-pubkey"))
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("abcdef")) // too short for hex64
    }

    @Test
    fun normalize_hex63chars_returnsNull() {
        // 63 chars is one short of a valid 64-char pubkey
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("a".repeat(63)))
    }

    @Test
    fun normalize_hex65chars_returnsNull() {
        // 65 chars is too long
        assertNull(Nip55RequestCodec.normalizeHexOrNpub("a".repeat(65)))
    }

    // ════════════════════════════════════════════════════════════════════
    //  currentUserFromProjection
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun currentUser_getPublicKey_alwaysNull() {
        // Amethyst/Quartz probes with ["login"] — must never forward to Dart
        assertNull(Nip55RequestCodec.currentUserFromProjection(arrayOf("login"), "get_public_key"))
        assertNull(Nip55RequestCodec.currentUserFromProjection(arrayOf(knownHexPubkey), "get_public_key"))
        assertNull(Nip55RequestCodec.currentUserFromProjection(null, "get_public_key"))
    }

    @Test
    fun currentUser_signEvent_legacyFormat_readsIndex1() {
        // Legacy: [eventJson, currentUserHex]
        val proj = arrayOf("{}", knownHexPubkey)
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "sign_event"))
    }

    @Test
    fun currentUser_signEvent_darkWispFormat_prefersIndex2() {
        // Dark-Wisp: [eventJson, "", npub] — blank index 1, current_user in index 2
        val proj = arrayOf("{}", "", knownNpub)
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "sign_event"))
    }

    @Test
    fun currentUser_signEvent_index2NonBlank_takesIndex2OverIndex1() {
        val anotherHex = "b".repeat(64)
        val proj = arrayOf("{}", anotherHex, knownHexPubkey)
        // Both present — prefer index 2
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "sign_event"))
    }

    @Test
    fun currentUser_signEvent_blankIndex2_fallsBackToIndex1() {
        val proj = arrayOf("{}", knownHexPubkey, "")
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "sign_event"))
    }

    @Test
    fun currentUser_decryptZapEvent_darkWispFormat() {
        val proj = arrayOf("{}", "", knownNpub)
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "decrypt_zap_event"))
    }

    @Test
    fun currentUser_signEvent_npubAtIndex2_decodestoHex() {
        val proj = arrayOf("{}", "", knownNpub)
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "sign_event"))
    }

    @Test
    fun currentUser_nip04Decrypt_readsIndex2() {
        // Crypto methods: [payload, peerPubkey, currentUser]
        val proj = arrayOf("ciphertext", "b".repeat(64), knownHexPubkey)
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj, "nip04_decrypt"))
    }

    @Test
    fun currentUser_nullProjection_returnsNull() {
        assertNull(Nip55RequestCodec.currentUserFromProjection(null, "sign_event"))
    }

    @Test
    fun currentUser_noMethod_readsIndex2() {
        val proj = arrayOf("{}", "b".repeat(64), knownHexPubkey)
        assertEquals(knownHexPubkey, Nip55RequestCodec.currentUserFromProjection(proj))
    }

    // ════════════════════════════════════════════════════════════════════
    //  peerPubkeyFromProjection
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun peerPubkey_hexAtIndex1_returnsNormalized() {
        val proj = arrayOf("payload", knownHexPubkey)
        assertEquals(knownHexPubkey, Nip55RequestCodec.peerPubkeyFromProjection(proj))
    }

    @Test
    fun peerPubkey_npubAtIndex1_decodestoHex() {
        val proj = arrayOf("payload", knownNpub)
        assertEquals(knownHexPubkey, Nip55RequestCodec.peerPubkeyFromProjection(proj))
    }

    @Test
    fun peerPubkey_blankIndex1_returnsNull() {
        val proj = arrayOf("payload", "")
        assertNull(Nip55RequestCodec.peerPubkeyFromProjection(proj))
    }

    @Test
    fun peerPubkey_nullProjection_returnsNull() {
        assertNull(Nip55RequestCodec.peerPubkeyFromProjection(null))
    }

    @Test
    fun peerPubkey_invalidValue_returnsNull() {
        val proj = arrayOf("payload", "not-a-pubkey")
        assertNull(Nip55RequestCodec.peerPubkeyFromProjection(proj))
    }

    // ════════════════════════════════════════════════════════════════════
    //  rejectedCursor — column contract (JVM-safe; data-access stubs with
    //  isReturnDefaultValues=true; full cursor-value tests are in androidTest)
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun rejectedCursor_noReason_doesNotThrow() {
        // Verifies rejectedCursor() constructs without crash on JVM.
        val cursor = Nip55RequestCodec.rejectedCursor()
        assertNotNull(cursor)
    }

    @Test
    fun rejectedCursor_withReason_doesNotThrow() {
        val cursor = Nip55RequestCodec.rejectedCursor("User denied sign_event")
        assertNotNull(cursor)
    }

    @Test
    fun rejectedCursor_blankReason_doesNotThrow() {
        val cursor = Nip55RequestCodec.rejectedCursor("  ")
        assertNotNull(cursor)
    }

    @Test
    fun rejectedCursor_defaultReasonToken_doesNotThrow() {
        val cursor = Nip55RequestCodec.rejectedCursor("rejected")
        assertNotNull(cursor)
    }
}
