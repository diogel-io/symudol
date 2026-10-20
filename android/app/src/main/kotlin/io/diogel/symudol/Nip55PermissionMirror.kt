package io.diogel.symudol

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Mirrors NIP-55 permission grants from the Dart side into SharedPreferences
 * so that [Nip55ContentProvider] can check remembered permissions synchronously
 * without going through the Flutter engine.
 *
 * The Dart side writes grants here via [syncGrants] (called through MethodChannel)
 * whenever a grant is saved, deleted, or modified.
 *
 * Thread safety: all reads/writes go through [SharedPreferences] which is
 * thread-safe for commit() on the main thread. ContentProvider.query() runs
 * on the caller's thread, so we use apply() for writes (async, safe) and
 * read from the in-memory cache that SharedPreferences maintains.
 */
class Nip55PermissionMirror(private val context: Context) {
    companion object {
        private const val TAG = "Diogel-PermMirror"
        private const val PREFS_NAME = "nip55_permission_grants_v2"

        /**
         * Remembered rejects from before the mirror, still read by
         * [Nip55ContentProvider]. Nothing writes it any more; only [wipe] clears it.
         */
        internal const val LEGACY_PREFS_NAME = "nip55_provider_permissions_v1"
        private const val KEY_GRANTS = "grants"
        private const val KEY_ACTIVE_IDENTITY_PUBKEY = "active_identity_pubkey"

        /** A grant's certificate when Dart could not read the caller's: matches no caller. */
        internal const val UNRESOLVED_CERTIFICATE = "unresolved"

        /**
         * Normalizes a relay URL for consistent storage and matching.
         * Trims whitespace, lowercases, strips trailing slash.
         * Must match [Nip55ApprovalPolicy._normalizeRelayUrl] on the Dart side.
         */
        fun normalizeRelayUrl(url: String?): String? {
            if (url.isNullOrBlank()) return null
            var normalized = url.trim().lowercase()
            if (normalized.endsWith("/")) normalized = normalized.dropLast(1)
            return normalized.ifEmpty { null }
        }

        /**
         * Whether any of [grants] is a remembered [decision] ("allow" or
         * "reject") for this caller, method and identity. Pure, so the matching
         * the ContentProvider relies on is tested directly.
         */
        internal fun matches(
            grants: List<Grant>,
            decision: String,
            callerPackage: String?,
            method: String,
            identityPubkey: String,
            eventKind: Int? = null,
            peerPubkey: String? = null,
            relayUrl: String? = null,
            callerCertSha256: String? = null,
            nowMs: Long = System.currentTimeMillis(),
        ): Boolean {
            if (callerPackage.isNullOrBlank()) return false
            return grants.any { grant ->
                !grant.isExpired(nowMs) &&
                grant.decision == decision &&
                grant.packageName == callerPackage &&
                grant.identityPubkey == identityPubkey &&
                certificateMatches(grant, callerCertSha256) &&
                scopeMatches(grant, method, eventKind, peerPubkey, relayUrl)
            }
        }

        // ── Scope matching ───────────────────────────────────────────────────

        /**
         * Matches grant scope to the requested method/kind/peerPubkey.
         *
         * Rules (must match Dart Nip55PermissionScope.matches and Nip55ApprovalPolicy):
         * - SignEventScope with kind=null (broad, "any kind") never matches an
         *   allow: every such signature is reviewed in the app. It still matches a
         *   reject, so a remembered refusal covers every kind. Matching a broad
         *   allow here let this ContentProvider sign any kind in the background
         *   with no screen, while the Dart policy sent it to review
         *   (diogel-io/symudol#5).
         * - SignEventScope with kind=K matches sign_event for kind K
         * - Nip44Encrypt/Decrypt with peerPubkey=null matches any peerPubkey
         * - Nip44Encrypt/Decrypt with peerPubkey=P matches only peerPubkey P
         * - Same for Nip04*
         * - GetPublicKeyScope, SignMessageScope, DecryptZapEventScope match by type only
         */
        internal fun scopeMatches(
            grant: Grant,
            method: String,
            eventKind: Int?,
            peerPubkey: String?,
            relayUrl: String? = null,
        ): Boolean {
            val grantScope = grant.scopeType
            return when (method) {
                "get_public_key" -> grantScope == "get_public_key"
                "sign_message" -> grantScope == "sign_message"
                "sign_event" -> when {
                    grantScope != "sign_event" -> false
                    grant.scopeKind == null && grant.decision == "allow" -> false
                    grant.scopeKind != null && grant.scopeKind != eventKind -> false
                    // Relay URL matching for kind 22242 (NIP-42 relay auth):
                    // A relay-specific grant only covers that relay; null = wildcard.
                    grant.scopeRelayUrl != null && normalizeRelayUrl(grant.scopeRelayUrl) != normalizeRelayUrl(relayUrl) -> false
                    else -> true
                }
                "nip44_encrypt" -> when {
                    grantScope != "nip44_encrypt" -> false
                    grant.scopePeerPubkey == null -> true  // wildcard: any peer
                    grant.scopePeerPubkey == peerPubkey -> true
                    else -> false
                }
                "nip44_decrypt" -> when {
                    grantScope != "nip44_decrypt" -> false
                    grant.scopePeerPubkey == null -> true
                    grant.scopePeerPubkey == peerPubkey -> true
                    else -> false
                }
                "nip04_encrypt" -> when {
                    grantScope != "nip04_encrypt" -> false
                    grant.scopePeerPubkey == null -> true
                    grant.scopePeerPubkey == peerPubkey -> true
                    else -> false
                }
                "nip04_decrypt" -> when {
                    grantScope != "nip04_decrypt" -> false
                    grant.scopePeerPubkey == null -> true
                    grant.scopePeerPubkey == peerPubkey -> true
                    else -> false
                }
                "decrypt_zap_event" -> when {
                    // NIP-57 zap receipts are NIP-04 encrypted to the recipient's pubkey.
                    // If the user trusts an app to decrypt their DMs, they trust it
                    // to decrypt zap receipts too. So nip04_decrypt/nip44_decrypt grants
                    // also satisfy decrypt_zap_event — but the scopePeerPubkey constraint
                    // from the decrypt grant still applies for cross-scope matches.
                    grantScope == "decrypt_zap_event" -> true
                    grantScope == "nip04_decrypt" -> grant.scopePeerPubkey == null || grant.scopePeerPubkey == peerPubkey
                    grantScope == "nip44_decrypt" -> grant.scopePeerPubkey == null || grant.scopePeerPubkey == peerPubkey
                    else -> false
                }
                else -> false
            }
        }

        internal fun certificateMatches(grant: Grant, callerCertSha256: String?): Boolean {
            // If the grant has no certificate recorded, it matches any caller
            if (grant.certificateSha256 == null) return true
            // Fail closed: if the grant requires a cert but we can't determine
            // the caller's certificate, deny the match. This ensures native
            // auto-approve is at least as strict as the Dart approval policy.
            if (callerCertSha256 == null) return false
            return grant.certificateSha256 == callerCertSha256
        }
    }

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // ── Grant model ──────────────────────────────────────────────────────

    data class Grant(
        val id: String,
        val identityPubkey: String,
        val packageName: String?,
        val certificateSha256: String?,
        val scopeType: String,          // "get_public_key", "sign_event", "nip44_decrypt", etc.
        val scopeKind: Int?,            // null for non-sign_event scopes; event kind for sign_event
        val scopePeerPubkey: String?,   // null for peer-agnostic scopes
        val scopeRelayUrl: String?,     // relay URL for kind 22242 (NIP-42); null = wildcard
        val decision: String,           // "allow", "reject", "ask"
        val expiresAtMillis: Long?,     // null = never expires
    ) {
        fun isExpired(nowMs: Long = System.currentTimeMillis()): Boolean {
            return expiresAtMillis != null && expiresAtMillis!! <= nowMs
        }
    }

    // ── Read grants ──────────────────────────────────────────────────────

    /** Grants for this app itself are never kept or matched: they would serve any caller (#11). */
    fun listGrants(): List<Grant> {
        val raw = prefs.getString(KEY_GRANTS, null) ?: return emptyList()
        return parseGrants(raw).filter { it.packageName != context.packageName }
    }

    /**
     * Check whether a remembered [allow] grant exists for the given
     * (caller, method, identity) combination.
     *
     * Matching rules (must match the Dart [Nip55ApprovalPolicy]):
     * - packageName must match exactly
     * - identityPubkey must match the active identity
     * - scope must match (see [scopeMatches] for wildcard rules)
     * - decision must be "allow"
     * - grant must not be expired
     */
    fun hasRememberedAllow(
        callerPackage: String?,
        method: String,
        identityPubkey: String,
        eventKind: Int? = null,
        peerPubkey: String? = null,
        relayUrl: String? = null,
        callerCertSha256: String? = null,
    ): Boolean {
        if (callerPackage == context.packageName) return false
        return matches(
            listGrants(), "allow", callerPackage, method, identityPubkey,
            eventKind, peerPubkey, relayUrl, callerCertSha256, System.currentTimeMillis(),
        )
    }

    /**
     * Check whether a remembered [reject] grant exists for the given
     * (caller, method, identity) combination.
     */
    fun hasRememberedReject(
        callerPackage: String?,
        method: String,
        identityPubkey: String,
        eventKind: Int? = null,
        peerPubkey: String? = null,
        relayUrl: String? = null,
        callerCertSha256: String? = null,
    ): Boolean {
        if (callerPackage == context.packageName) return false
        return matches(
            listGrants(), "reject", callerPackage, method, identityPubkey,
            eventKind, peerPubkey, relayUrl, callerCertSha256, System.currentTimeMillis(),
        )
    }

    // ── Active identity ──────────────────────────────────────────────────

    fun getActiveIdentityPubkey(): String? {
        return prefs.getString(KEY_ACTIVE_IDENTITY_PUBKEY, null)
    }

    fun setActiveIdentityPubkey(pubkey: String?) {
        if (pubkey != null) {
            prefs.edit().putString(KEY_ACTIVE_IDENTITY_PUBKEY, pubkey).apply()
        } else {
            prefs.edit().remove(KEY_ACTIVE_IDENTITY_PUBKEY).apply()
        }
    }

    // ── Write grants (called from Dart via MethodChannel) ────────────────

    /**
     * Replace the entire grant list. Called when the Dart side
     * saves/deletes/modifies any grant.
     */
    fun syncGrants(grantsJson: String) {
        // Validate by parsing — if it fails, don't write garbage.
        val grants = try {
            parseGrants(grantsJson)
        } catch (e: Exception) {
            DiogelLog.e(TAG, "syncGrants: invalid JSON, refusing to write", e)
            return
        }
        // Never keep a grant for this app itself (#11).
        val kept = grants.filter { it.packageName != context.packageName }
        val json = if (kept.size == grants.size) grantsJson else serializeGrants(kept)
        prefs.edit().putString(KEY_GRANTS, json).apply()
        DiogelLog.d(TAG) { "syncGrants: synced ${kept.size} grants" }
    }

    /**
     * Delete all grants for a specific package.
     */
    fun deleteAllForPackage(packageName: String) {
        val current = listGrants().filter { it.packageName != packageName }
        prefs.edit().putString(KEY_GRANTS, serializeGrants(current)).apply()
        DiogelLog.d(TAG) { "deleteAllForPackage: removed grants for $packageName, ${current.size} remaining" }
    }

    /**
     * Clear all grants.
     */
    fun clearAll() {
        prefs.edit().remove(KEY_GRANTS).apply()
        DiogelLog.d(TAG) { "clearAll: all grants removed" }
    }

    /**
     * Erase everything this mirror keeps (grants and the active pubkey) and the
     * legacy preferences file, for a vault wipe (diogel-io/symudol#20). Uses
     * commit(), not apply(), so the data is gone when this returns.
     *
     * @return whether both files were written.
     */
    fun wipe(): Boolean {
        val mirrorCleared = prefs.edit().clear().commit()
        val legacyCleared = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
            .edit().clear().commit()
        DiogelLog.d(TAG) { "wipe: mirror=$mirrorCleared legacy=$legacyCleared" }
        return mirrorCleared && legacyCleared
    }

    // ── Serialization ────────────────────────────────────────────────────

    private fun parseGrants(json: String): List<Grant> {
        val array = JSONArray(json)
        val result = mutableListOf<Grant>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            try {
                result.add(parseGrant(obj))
            } catch (e: Exception) {
                DiogelLog.w(TAG, "parseGrants: skipping malformed grant at index $i", e)
            }
        }
        return result
    }

    /**
     * The string at [key], or null when it is missing or JSON null. Android's
     * `optString(key, null)` returns the string "null" for a JSON null, which Dart writes for
     * every unset field; read that way, no remembered sign_event or any-peer decrypt grant ever
     * matched (diogel-io/symudol#19).
     */
    private fun JSONObject.stringOrNull(key: String): String? =
        if (isNull(key)) null else getString(key)

    private fun parseGrant(obj: JSONObject): Grant {
        val scopeObj = obj.getJSONObject("scope")
        return Grant(
            id = obj.getString("id"),
            identityPubkey = obj.getString("identityPubkey"),
            packageName = obj.stringOrNull("packageName"),
            // Dart writes a JSON null when it could not read the caller's certificate. A null
            // here would match every certificate (certificateMatches), letting another app with
            // the same package name use the grant, so it stays a value no caller has
            // (REQ-NIP55-010).
            certificateSha256 = if (obj.has("certificateSha256")) {
                obj.stringOrNull("certificateSha256") ?: UNRESOLVED_CERTIFICATE
            } else {
                null
            },
            scopeType = scopeObj.getString("type"),
            scopeKind = scopeObj.optInt("kind", -1).let { if (it == -1) null else it },
            scopePeerPubkey = scopeObj.stringOrNull("peerPubkey"),
            scopeRelayUrl = scopeObj.stringOrNull("relayUrl"),
            decision = obj.getString("decision"),
            expiresAtMillis = obj.stringOrNull("expiresAt")?.let {
                // Parse ISO 8601 date to epoch millis
                try {
                    java.time.Instant.parse(it).toEpochMilli()
                } catch (_: Exception) {
                    null
                }
            },
        )
    }

    private fun serializeGrants(grants: List<Grant>): String {
        val array = JSONArray()
        for (grant in grants) {
            val scope = JSONObject().apply {
                put("type", grant.scopeType)
                grant.scopeKind?.let { put("kind", it) }
                grant.scopePeerPubkey?.let { put("peerPubkey", it) }
                grant.scopeRelayUrl?.let { put("relayUrl", it) }
            }
            val obj = JSONObject().apply {
                put("id", grant.id)
                put("identityPubkey", grant.identityPubkey)
                put("packageName", grant.packageName ?: JSONObject.NULL)
                put("certificateSha256", grant.certificateSha256 ?: JSONObject.NULL)
                put("scope", scope)
                put("decision", grant.decision)
                grant.expiresAtMillis?.let {
                    put("expiresAt", java.time.Instant.ofEpochMilli(it).toString())
                } ?: put("expiresAt", JSONObject.NULL)
            }
            array.put(obj)
        }
        return array.toString()
    }
}