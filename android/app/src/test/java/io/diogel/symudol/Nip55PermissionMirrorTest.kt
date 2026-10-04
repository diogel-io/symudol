package io.diogel.symudol

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject

private typealias Grant = Nip55PermissionMirror.Grant

/**
 * Unit tests for Nip55PermissionMirror's grant matching.
 *
 * They drive the real matching in [Nip55PermissionMirror.Companion] (pure: no
 * SharedPreferences, no Context), the code the ContentProvider relies on. They
 * used to test a copy of it, which could not catch a bug in the shipped matcher:
 * the copy asserted that a broad sign_event allow matches any kind, the bug
 * fixed in diogel-io/symudol#5.
 */
class Nip55PermissionMirrorTest {

    private fun scopeMatches(
        grant: Grant,
        method: String,
        eventKind: Int?,
        peerPubkey: String?,
        relayUrl: String? = null,
    ): Boolean = Nip55PermissionMirror.scopeMatches(grant, method, eventKind, peerPubkey, relayUrl)

    private fun certificateMatches(grant: Grant, callerCertSha256: String?): Boolean =
        Nip55PermissionMirror.certificateMatches(grant, callerCertSha256)

    // ── Helpers ──────────────────────────────────────────────────────────

    private val identity = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789" // 64-char hex pubkey
    private val peerA = "aaaa11110000000000000000000000000000000000000000000000000000000000" // 64-char peer pubkey
    private val peerB = "bbbb22220000000000000000000000000000000000000000000000000000000000"

    private fun makeGrant(
        scopeType: String,
        scopeKind: Int? = null,
        scopePeerPubkey: String? = null,
        packageName: String = "com.example.app",
        decision: String = "allow",
        identityPubkey: String = identity,
        certificateSha256: String? = null,
        expiresAtMillis: Long? = null,
        scopeRelayUrl: String? = null,
    ) = Grant(
        id = "grant-${scopeType}",
        identityPubkey = identityPubkey,
        packageName = packageName,
        certificateSha256 = certificateSha256,
        scopeType = scopeType,
        scopeKind = scopeKind,
        scopePeerPubkey = scopePeerPubkey,
        scopeRelayUrl = scopeRelayUrl,
        decision = decision,
        expiresAtMillis = expiresAtMillis,
    )

    // ════════════════════════════════════════════════════════════════════
    //  SCOPE MATCHING TESTS
    // ════════════════════════════════════════════════════════════════════

    // ── get_public_key ──────────────────────────────────────────────────

    @Test
    fun testGetPublicKey_exactMatch() {
        val grant = makeGrant(scopeType = "get_public_key")
        assertTrue(scopeMatches(grant, "get_public_key", null, null))
    }

    @Test
    fun testGetPublicKey_noOtherMatch() {
        val grant = makeGrant(scopeType = "get_public_key")
        assertFalse(scopeMatches(grant, "sign_event", null, null))
        assertFalse(scopeMatches(grant, "nip04_decrypt", null, null))
        assertFalse(scopeMatches(grant, "nip44_encrypt", null, null))
    }

    // ── sign_message ────────────────────────────────────────────────────

    @Test
    fun testSignMessage_exactMatch() {
        val grant = makeGrant(scopeType = "sign_message")
        assertTrue(scopeMatches(grant, "sign_message", null, null))
    }

    @Test
    fun testSignMessage_noOtherMatch() {
        val grant = makeGrant(scopeType = "sign_message")
        assertFalse(scopeMatches(grant, "sign_event", null, null))
        assertFalse(scopeMatches(grant, "get_public_key", null, null))
    }

    // ── sign_event ─────────────────────────────────────────────────────

    @Test
    fun testSignEvent_broadAllowMatchesNoKind() {
        // #5: a broad allow ("sign any kind") is never auto-approved here, so
        // the ContentProvider cannot sign in the background without review.
        val grant = makeGrant(scopeType = "sign_event", scopeKind = null, decision = "allow")
        assertFalse(scopeMatches(grant, "sign_event", 1, null))
        assertFalse(scopeMatches(grant, "sign_event", 22242, null))
        assertFalse(scopeMatches(grant, "sign_event", 0, null))
    }

    @Test
    fun testSignEvent_broadRejectStillMatchesEveryKind() {
        // A remembered refusal covering every kind is safe, and is kept.
        val grant = makeGrant(scopeType = "sign_event", scopeKind = null, decision = "reject")
        assertTrue(scopeMatches(grant, "sign_event", 1, null))
        assertTrue(scopeMatches(grant, "sign_event", 0, null))
    }

    @Test
    fun testSignEvent_specificKindMatchesOnlyThatKind() {
        val grant = makeGrant(scopeType = "sign_event", scopeKind = 1)
        assertTrue(scopeMatches(grant, "sign_event", 1, null))
        assertFalse(scopeMatches(grant, "sign_event", 22242, null))
        assertFalse(scopeMatches(grant, "sign_event", 0, null))
    }

    @Test
    fun testSignEvent_kind22242() {
        val grant = makeGrant(scopeType = "sign_event", scopeKind = 22242)
        assertTrue(scopeMatches(grant, "sign_event", 22242, null))
        assertFalse(scopeMatches(grant, "sign_event", 1, null))
    }

    @Test
    fun testSignEvent_noMatchForOtherMethods() {
        val grant = makeGrant(scopeType = "sign_event", scopeKind = null)
        assertFalse(scopeMatches(grant, "get_public_key", null, null))
        assertFalse(scopeMatches(grant, "nip04_decrypt", null, null))
    }

    // ── nip04_encrypt / nip04_decrypt ───────────────────────────────────

    @Test
    fun testNip04Encrypt_wildcardPeer() {
        val grant = makeGrant(scopeType = "nip04_encrypt", scopePeerPubkey = null)
        assertTrue(scopeMatches(grant, "nip04_encrypt", null, peerA))
        assertTrue(scopeMatches(grant, "nip04_encrypt", null, peerB))
        assertTrue(scopeMatches(grant, "nip04_encrypt", null, null))
    }

    @Test
    fun testNip04Encrypt_specificPeer() {
        val grant = makeGrant(scopeType = "nip04_encrypt", scopePeerPubkey = peerA)
        assertTrue(scopeMatches(grant, "nip04_encrypt", null, peerA))
        assertFalse(scopeMatches(grant, "nip04_encrypt", null, peerB))
    }

    @Test
    fun testNip04Decrypt_wildcardPeer() {
        val grant = makeGrant(scopeType = "nip04_decrypt", scopePeerPubkey = null)
        assertTrue(scopeMatches(grant, "nip04_decrypt", null, peerA))
        assertTrue(scopeMatches(grant, "nip04_decrypt", null, peerB))
    }

    @Test
    fun testNip04Decrypt_specificPeer() {
        val grant = makeGrant(scopeType = "nip04_decrypt", scopePeerPubkey = peerA)
        assertTrue(scopeMatches(grant, "nip04_decrypt", null, peerA))
        assertFalse(scopeMatches(grant, "nip04_decrypt", null, peerB))
    }

    // ── nip44_encrypt / nip44_decrypt ────────────────────────────────────

    @Test
    fun testNip44Encrypt_wildcardPeer() {
        val grant = makeGrant(scopeType = "nip44_encrypt", scopePeerPubkey = null)
        assertTrue(scopeMatches(grant, "nip44_encrypt", null, peerA))
        assertTrue(scopeMatches(grant, "nip44_encrypt", null, peerB))
    }

    @Test
    fun testNip44Encrypt_specificPeer() {
        val grant = makeGrant(scopeType = "nip44_encrypt", scopePeerPubkey = peerA)
        assertTrue(scopeMatches(grant, "nip44_encrypt", null, peerA))
        assertFalse(scopeMatches(grant, "nip44_encrypt", null, peerB))
    }

    @Test
    fun testNip44Decrypt_wildcardPeer() {
        val grant = makeGrant(scopeType = "nip44_decrypt", scopePeerPubkey = null)
        assertTrue(scopeMatches(grant, "nip44_decrypt", null, peerA))
        assertTrue(scopeMatches(grant, "nip44_decrypt", null, peerB))
    }

    @Test
    fun testNip44Decrypt_specificPeer() {
        val grant = makeGrant(scopeType = "nip44_decrypt", scopePeerPubkey = peerA)
        assertTrue(scopeMatches(grant, "nip44_decrypt", null, peerA))
        assertFalse(scopeMatches(grant, "nip44_decrypt", null, peerB))
    }

    // ── Cross-scope: nip04/nip44 decrypt also satisfies decrypt_zap_event ─

    @Test
    fun testDecryptZapEvent_directScope() {
        val grant = makeGrant(scopeType = "decrypt_zap_event")
        assertTrue(scopeMatches(grant, "decrypt_zap_event", null, null))
    }

    @Test
    fun testDecryptZapEvent_nip04DecryptSatisfies() {
        // Cross-scope: nip04_decrypt grant should satisfy decrypt_zap_event
        val grant = makeGrant(scopeType = "nip04_decrypt", scopePeerPubkey = null)
        assertTrue(scopeMatches(grant, "decrypt_zap_event", null, peerA))
    }

    @Test
    fun testDecryptZapEvent_nip44DecryptSatisfies() {
        // Cross-scope: nip44_decrypt grant should satisfy decrypt_zap_event
        val grant = makeGrant(scopeType = "nip44_decrypt", scopePeerPubkey = null)
        assertTrue(scopeMatches(grant, "decrypt_zap_event", null, peerA))
    }

    @Test
    fun testDecryptZapEvent_specificPeerNip04DecryptSatisfiesOnlyThatPeer() {
        // The shipped matcher keeps a decrypt grant's peer for zap receipts.
        // The copy this test used to exercise ignored it, so it asserted
        // behaviour the ContentProvider never had. (Dart ignores the peer here;
        // Kotlin is the stricter side. Symudol saves decrypt grants with no
        // peer, so the two agree in practice.)
        val grant = makeGrant(scopeType = "nip04_decrypt", scopePeerPubkey = peerA)
        assertTrue(scopeMatches(grant, "decrypt_zap_event", null, peerA))
        assertFalse(scopeMatches(grant, "decrypt_zap_event", null, peerB))
    }

    @Test
    fun testDecryptZapEvent_signEventDoesNotSatisfy() {
        val grant = makeGrant(scopeType = "sign_event", scopeKind = null)
        assertFalse(scopeMatches(grant, "decrypt_zap_event", null, null))
    }

    @Test
    fun testDecryptZapEvent_nip04EncryptDoesNotSatisfy() {
        // nip04_encrypt should NOT satisfy decrypt_zap_event
        val grant = makeGrant(scopeType = "nip04_encrypt", scopePeerPubkey = null)
        assertFalse(scopeMatches(grant, "decrypt_zap_event", null, null))
    }

    @Test
    fun testDecryptZapEvent_nip44EncryptDoesNotSatisfy() {
        val grant = makeGrant(scopeType = "nip44_encrypt", scopePeerPubkey = null)
        assertFalse(scopeMatches(grant, "decrypt_zap_event", null, null))
    }

    // ── No cross-scope contamination ────────────────────────────────────

    @Test
    fun testNoCrossContamination_nip04DecryptDoesNotMatchNip04Encrypt() {
        val grant = makeGrant(scopeType = "nip04_decrypt", scopePeerPubkey = null)
        assertFalse(scopeMatches(grant, "nip04_encrypt", null, peerA))
    }

    @Test
    fun testNoCrossContamination_nip44DecryptDoesNotMatchNip44Encrypt() {
        val grant = makeGrant(scopeType = "nip44_decrypt", scopePeerPubkey = null)
        assertFalse(scopeMatches(grant, "nip44_encrypt", null, peerA))
    }

    @Test
    fun testNoCrossContamination_nip04EncryptDoesNotMatchNip04Decrypt() {
        val grant = makeGrant(scopeType = "nip04_encrypt", scopePeerPubkey = null)
        assertFalse(scopeMatches(grant, "nip04_decrypt", null, peerA))
    }

    @Test
    fun testNoCrossContamination_signEventDoesNotMatchSignMessage() {
        val grant = makeGrant(scopeType = "sign_event", scopeKind = null)
        assertFalse(scopeMatches(grant, "sign_message", null, null))
    }

    @Test
    fun testNoCrossContamination_getPublicKeyDoesNotMatchSignEvent() {
        val grant = makeGrant(scopeType = "get_public_key")
        assertFalse(scopeMatches(grant, "sign_event", null, null))
    }

    // ── Unknown method returns false ────────────────────────────────────

    @Test
    fun testUnknownMethodReturnsFalse() {
        val grant = makeGrant(scopeType = "get_public_key")
        assertFalse(scopeMatches(grant, "unknown_method", null, null))
    }

    // ════════════════════════════════════════════════════════════════════
    //  CERTIFICATE MATCHING TESTS
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun testCertificateMatches_grantHasNoCert_alwaysMatches() {
        val grant = makeGrant(scopeType = "get_public_key", certificateSha256 = null)
        assertTrue(certificateMatches(grant, "abc123"))
        assertTrue(certificateMatches(grant, null))
    }

    @Test
    fun testCertificateMatches_grantHasCert_callerHasMatchingCert() {
        val grant = makeGrant(scopeType = "get_public_key", certificateSha256 = "abc123")
        assertTrue(certificateMatches(grant, "abc123"))
    }

    @Test
    fun testCertificateMatches_grantHasCert_callerHasMismatchedCert() {
        val grant = makeGrant(scopeType = "get_public_key", certificateSha256 = "abc123")
        assertFalse(certificateMatches(grant, "xyz789"))
    }

    @Test
    fun testCertificateMatches_grantHasCert_callerHasNoCert_failClosed() {
        val grant = makeGrant(scopeType = "get_public_key", certificateSha256 = "abc123")
        // If the grant requires a cert but caller cert is unavailable, deny.
        // This is the "fail-closed" behavior from the code review.
        assertFalse(certificateMatches(grant, null))
    }

    // ════════════════════════════════════════════════════════════════════
    //  EXPIRY TESTS
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun testGrantNotExpired_noExpiry() {
        val grant = makeGrant(scopeType = "get_public_key", expiresAtMillis = null)
        assertFalse(grant.isExpired(System.currentTimeMillis()))
    }

    @Test
    fun testGrantNotExpired_futureExpiry() {
        val future = System.currentTimeMillis() + 3600000 // 1 hour from now
        val grant = makeGrant(scopeType = "get_public_key", expiresAtMillis = future)
        assertFalse(grant.isExpired(System.currentTimeMillis()))
    }

    @Test
    fun testGrantExpired_pastExpiry() {
        val past = System.currentTimeMillis() - 1000 // 1 second ago
        val grant = makeGrant(scopeType = "get_public_key", expiresAtMillis = past)
        assertTrue(grant.isExpired(System.currentTimeMillis()))
    }

    @Test
    fun testGrantExpired_exactlyAtExpiry() {
        val expiry = 1000L
        val grant = makeGrant(scopeType = "get_public_key", expiresAtMillis = expiry)
        // At the exact expiry time, the grant is expired (<=)
        assertTrue(grant.isExpired(expiry))
    }

    // ════════════════════════════════════════════════════════════════════
    //  INTEGRATION-STYLE: hasRememberedAllow with multiple grants
    // ════════════════════════════════════════════════════════════════════

    /**
     * Simulates hasRememberedAllow logic without Android SharedPreferences.
     */
    private fun hasRememberedAllow(
        grants: List<Grant>,
        callerPackage: String?,
        method: String,
        identityPubkey: String,
        eventKind: Int? = null,
        peerPubkey: String? = null,
        callerCertSha256: String? = null,
    ): Boolean = Nip55PermissionMirror.matches(
        grants, "allow", callerPackage, method, identityPubkey,
        eventKind = eventKind, peerPubkey = peerPubkey, callerCertSha256 = callerCertSha256,
    )

    private fun hasRememberedReject(
        grants: List<Grant>,
        callerPackage: String?,
        method: String,
        identityPubkey: String,
        eventKind: Int? = null,
    ): Boolean = Nip55PermissionMirror.matches(
        grants, "reject", callerPackage, method, identityPubkey, eventKind = eventKind,
    )

    @Test
    fun testHasRememberedAllow_basicAllow() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app")
        )
        assertTrue(hasRememberedAllow(grants, "com.example.app", "get_public_key", identity))
    }

    @Test
    fun testHasRememberedAllow_wrongPackage() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app")
        )
        assertFalse(hasRememberedAllow(grants, "com.other.app", "get_public_key", identity))
    }

    @Test
    fun testHasRememberedAllow_wrongIdentity() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app", identityPubkey = identity)
        )
        assertFalse(hasRememberedAllow(grants, "com.example.app", "get_public_key", "different_identity"))
    }

    @Test
    fun testHasRememberedAllow_rejectDoesNotMatch() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app", decision = "reject")
        )
        assertFalse(hasRememberedAllow(grants, "com.example.app", "get_public_key", identity))
    }

    @Test
    fun testHasRememberedAllow_expiredGrantDoesNotMatch() {
        val past = System.currentTimeMillis() - 1000
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app", expiresAtMillis = past)
        )
        assertFalse(hasRememberedAllow(grants, "com.example.app", "get_public_key", identity))
    }

    @Test
    fun testHasRememberedAllow_crossScopeDecryptZap() {
        // A nip04_decrypt grant should auto-approve decrypt_zap_event
        val grants = listOf(
            makeGrant(scopeType = "nip04_decrypt", scopePeerPubkey = null, packageName = "com.example.app")
        )
        assertTrue(hasRememberedAllow(grants, "com.example.app", "decrypt_zap_event", identity))
    }

    @Test
    fun testHasRememberedAllow_crossScopeNip44DecryptZap() {
        val grants = listOf(
            makeGrant(scopeType = "nip44_decrypt", scopePeerPubkey = null, packageName = "com.example.app")
        )
        assertTrue(hasRememberedAllow(grants, "com.example.app", "decrypt_zap_event", identity))
    }

    @Test
    fun testHasRememberedAllow_signEventBroadNeverAllows() {
        // #5: the path the ContentProvider takes. A broad allow grant, as an
        // app could get from one remembered get_public_key approval, must not
        // let any kind be signed in the background.
        val grants = listOf(
            makeGrant(scopeType = "sign_event", scopeKind = null, packageName = "com.example.app")
        )
        for (kind in listOf(0, 1, 3, 5, 9734, 22242)) {
            assertFalse("kind $kind", hasRememberedAllow(grants, "com.example.app", "sign_event", identity, eventKind = kind))
        }
    }

    @Test
    fun testHasRememberedReject_signEventBroadRejectsEveryKind() {
        val grants = listOf(
            makeGrant(scopeType = "sign_event", scopeKind = null, packageName = "com.example.app", decision = "reject")
        )
        assertTrue(hasRememberedReject(grants, "com.example.app", "sign_event", identity, eventKind = 0))
        assertTrue(hasRememberedReject(grants, "com.example.app", "sign_event", identity, eventKind = 1))
    }

    @Test
    fun testHasRememberedAllow_signEventSpecificKind() {
        val grants = listOf(
            makeGrant(scopeType = "sign_event", scopeKind = 1, packageName = "com.example.app")
        )
        assertTrue(hasRememberedAllow(grants, "com.example.app", "sign_event", identity, eventKind = 1))
        assertFalse(hasRememberedAllow(grants, "com.example.app", "sign_event", identity, eventKind = 22242))
    }

    @Test
    fun testHasRememberedAllow_nullPackageFails() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app")
        )
        assertFalse(hasRememberedAllow(grants, null, "get_public_key", identity))
    }

    @Test
    fun testHasRememberedAllow_emptyPackageFails() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app")
        )
        assertFalse(hasRememberedAllow(grants, "", "get_public_key", identity))
    }

    @Test
    fun testHasRememberedAllow_multipleGrants_firstWins() {
        val grants = listOf(
            makeGrant(scopeType = "sign_event", scopeKind = 1, packageName = "com.example.app"),
            makeGrant(scopeType = "sign_event", scopeKind = null, packageName = "com.example.app"),
        )
        // Kind=1 matches, so this should pass
        assertTrue(hasRememberedAllow(grants, "com.example.app", "sign_event", identity, eventKind = 1))
        // The broad grant alongside covers nothing more (#5).
        assertFalse(hasRememberedAllow(grants, "com.example.app", "sign_event", identity, eventKind = 22242))
    }

    @Test
    fun testHasRememberedAllow_certRequired_callerCertUnavailable_failClosed() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app", certificateSha256 = "abc123")
        )
        // Grant requires a cert, but caller has no cert → fail closed
        assertFalse(hasRememberedAllow(grants, "com.example.app", "get_public_key", identity, callerCertSha256 = null))
    }

    @Test
    fun testHasRememberedAllow_certRequired_callerCertMatches() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app", certificateSha256 = "abc123")
        )
        assertTrue(hasRememberedAllow(grants, "com.example.app", "get_public_key", identity, callerCertSha256 = "abc123"))
    }

    @Test
    fun testHasRememberedAllow_certRequired_callerCertMismatch() {
        val grants = listOf(
            makeGrant(scopeType = "get_public_key", packageName = "com.example.app", certificateSha256 = "abc123")
        )
        assertFalse(hasRememberedAllow(grants, "com.example.app", "get_public_key", identity, callerCertSha256 = "xyz"))
    }
}