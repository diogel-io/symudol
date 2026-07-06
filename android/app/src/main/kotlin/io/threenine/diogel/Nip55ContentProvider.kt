package io.threenine.diogel

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.util.Log
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

class Nip55ContentProvider : ContentProvider() {
    companion object {
        private val certificateCache = ConcurrentHashMap<String, String>()
        private const val TAG = "Diogel-ContentProvider"
    }

    private lateinit var permissionMirror: Nip55PermissionMirror
    private var _secp256k1Tested = false

    override fun onCreate(): Boolean {
        permissionMirror = Nip55PermissionMirror(context ?: return false)
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        if (!Nip55RequestCodec.isSupportedAuthority(uri.authority)) return null

        val method = Nip55RequestCodec.methodFor(uri) ?: return null
        val callerPackage = callingPackage()
        val callerCertSha256 = resolveSigningCertificateSha256(callerPackage)
        Log.d(TAG, "query: method=$method caller=$callerPackage authority=${uri.authority}")

        // Run secp256k1 self-test once (lazy)
        if (!_secp256k1Tested) {
            _secp256k1Tested = true
            Secp256k1.selfTest()
        }

        // PING is treated as a stateless capability probe — always returns pong
        if (method == "ping") {
            return Nip55RequestCodec.operationResultCursor("pong")
        }

        // ── Resolve active identity pubkey ─────────────────────────────────
        // CryptoBridge has the in-memory pubkey if vault is unlocked and key synced.
        // Otherwise, fall back to the persisted identity pubkey from PermMirror.
        // The persisted pubkey is enough for permission checking but NOT for
        // native crypto (we need the private key for that).
        val activePubkey = Nip55CryptoBridge.activePublicKey
            ?: permissionMirror.getActiveIdentityPubkey()

        // Decrypt operations (nip04_decrypt, nip44_decrypt) now require a remembered
        // allow grant — they fall through to the standard permission path below.
        // This prevents background plaintext exposure without explicit user approval.
        // Vault-locked decrypt returns null (standard path handles that via activePubkey check).

        var nativeCryptoFellThrough = false

        if (activePubkey != null && callerPackage != null) {
            // Determine scope parameters for permission matching
            val eventJson = if (method == "sign_event") {
                Nip55RequestCodec.eventJsonFromProjection(projection)
            } else null

            val eventKind = eventJson?.let { json ->
                try { org.json.JSONObject(json).optInt("kind") } catch (_: Exception) { null }
            }

            // Extract relay URL for kind 22242 (NIP-42 relay auth) — needed for
            // relay-specific grant matching. Normalized to match the Dart side.
            val relayUrl = if (eventKind == 22242) {
                eventJson?.let { json ->
                    try {
                        val tagsArray = org.json.JSONObject(json).optJSONArray("tags")
                        var relay: String? = null
                        if (tagsArray != null) {
                            for (i in 0 until tagsArray.length()) {
                                val tag = tagsArray.optJSONArray(i)
                                if (tag != null && tag.length() >= 2 && tag.optString(0) == "relay") {
                                    relay = Nip55PermissionMirror.normalizeRelayUrl(tag.optString(1))
                                    break
                                }
                            }
                        }
                        relay
                    } catch (_: Exception) { null }
                }
            } else null

            val peerPubkey = when (method) {
                "nip04_encrypt", "nip04_decrypt", "nip44_encrypt", "nip44_decrypt" ->
                    Nip55RequestCodec.peerPubkeyFromProjection(projection)
                else -> null
            }

            // Check remembered REJECT first — immediate hard no
            if (permissionMirror.hasRememberedReject(
                    callerPackage, method, activePubkey,
                    eventKind = eventKind,
                    peerPubkey = peerPubkey,
                    relayUrl = relayUrl,
                    callerCertSha256 = callerCertSha256,
                )
            ) {
                Log.d(TAG, "query: remembered reject for $callerPackage/$method")
                return Nip55RequestCodec.rejectedCursor()
            }

            // Check remembered ALLOW — if found, try native crypto first.
            // If native crypto returns null (method not yet supported natively),
            // fall through to the Flutter bridge path rather than returning null
            // (which causes the client to send an Intent).
            if (permissionMirror.hasRememberedAllow(
                    callerPackage, method, activePubkey,
                    eventKind = eventKind,
                    peerPubkey = peerPubkey,
                    relayUrl = relayUrl,
                    callerCertSha256 = callerCertSha256,
                )
            ) {
                Log.d(TAG, "query: remembered allow for $callerPackage/$method — performing native crypto")
                val nativeResult = performNativeCrypto(method, projection, activePubkey)
                if (nativeResult != null) return nativeResult
                // Native crypto not available for this method — fall through to bridge
                nativeCryptoFellThrough = true
                Log.d(TAG, "query: native crypto unavailable for $method, falling through to Flutter bridge")
            }
        }

        // ── Also check legacy SharedPreferences reject store ──────────────
        // (kept for backward compatibility during migration)
        if (hasLegacyRememberedReject(callerPackage, method)) {
            Log.d(TAG, "query: legacy remembered reject for $callerPackage/$method")
            return Nip55RequestCodec.rejectedCursor()
        }

        // ── Decide: bridge to Flutter or return null ──────────────────────
        //
        // We reach here when:
        // 1. Native crypto returned null (method not yet supported natively)
        // 2. No remembered permission at all
        //
        // Returning null causes the client to fall back to Intent prompts.
        // For case 1, we delegate to the Flutter bridge which can
        // handle it without UI prompts.
        // For case 2, we return null (legitimate first-time request).
        if (!hasRequiredProjection(method, projection)) return null

        val shouldBridge = when {
            // Native crypto fell through (remembered allow but method not native yet)
            nativeCryptoFellThrough -> true
            // No remembered grant, vault locked — can't bridge
            activePubkey == null -> false
            // No remembered grant, vault unlocked — legitimate first-time request
            else -> false
        }

        if (!shouldBridge) return null

        val result = Nip55ProviderBridge.query(providerArguments(method, projection, callerPackage))
            ?: return null

        val rejected = result["rejected"]?.toString()
        if (!rejected.isNullOrBlank()) return Nip55RequestCodec.rejectedCursor(rejected)

        val operationResult = result["result"]?.toString() ?: return null
        if (method == "sign_event") {
            val eventJson = result["event"]?.toString() ?: return null
            return Nip55RequestCodec.signEventCursor(operationResult, eventJson)
        }
        return Nip55RequestCodec.operationResultCursor(operationResult)
    }

    // ── Native crypto operations ─────────────────────────────────────────

    /**
     * Perform crypto operations natively using the in-memory key from
     * [Nip55CryptoBridge]. This avoids the Flutter MethodChannel bridge
     * entirely and runs in microseconds.
     *
     * Currently supported native operations:
     * - get_public_key: returns the active pubkey
     * - nip44_decrypt/nip44_encrypt: native ECDH + ChaCha20-Poly1305
     * - nip04_decrypt/nip04_encrypt: native ECDH + AES-256-CBC
     *
     * Operations that fall back to the Flutter bridge:
     * - sign_event: requires exact NIP-01 JSON serialization + BIP-340 Schnorr
     * - sign_message: requires Schnorr signing
     * - decrypt_zap_event: complex NIP-57 logic
     *
     * These will be migrated to native once the Schnorr implementation
     * is validated against the test vectors.
     */
    private fun performNativeCrypto(
        method: String,
        projection: Array<out String>?,
        activePubkey: String,
    ): Cursor? {
        val privateKey = Nip55CryptoBridge.activePrivateKey
        if (privateKey == null) {
            Log.w(TAG, "performNativeCrypto: no active private key, falling back to bridge")
            return null
        }

        return try {
            when (method) {
                "get_public_key" -> {
                    Nip55RequestCodec.operationResultCursor(activePubkey)
                }
                "nip44_decrypt" -> {
                    val ciphertext = Nip55RequestCodec.payloadFromProjection(projection) ?: return null
                    val peerPubkey = Nip55RequestCodec.peerPubkeyFromProjection(projection) ?: return null
                    val plaintext = Nip55NativeCrypto.nip44Decrypt(privateKey, peerPubkey, ciphertext)
                    Nip55RequestCodec.operationResultCursor(plaintext)
                }
                "nip44_encrypt" -> {
                    val plaintext = Nip55RequestCodec.payloadFromProjection(projection) ?: return null
                    val peerPubkey = Nip55RequestCodec.peerPubkeyFromProjection(projection) ?: return null
                    val ciphertext = Nip55NativeCrypto.nip44Encrypt(privateKey, peerPubkey, plaintext)
                    Nip55RequestCodec.operationResultCursor(ciphertext)
                }
                "nip04_decrypt" -> {
                    val ciphertext = Nip55RequestCodec.payloadFromProjection(projection) ?: return null
                    val peerPubkey = Nip55RequestCodec.peerPubkeyFromProjection(projection) ?: return null
                    val plaintext = Nip55NativeCrypto.nip04Decrypt(privateKey, peerPubkey, ciphertext)
                    Nip55RequestCodec.operationResultCursor(plaintext)
                }
                "nip04_encrypt" -> {
                    val plaintext = Nip55RequestCodec.payloadFromProjection(projection) ?: return null
                    val peerPubkey = Nip55RequestCodec.peerPubkeyFromProjection(projection) ?: return null
                    val ciphertext = Nip55NativeCrypto.nip04Encrypt(privateKey, peerPubkey, plaintext)
                    Nip55RequestCodec.operationResultCursor(ciphertext)
                }
                // sign_event and sign_message: native Schnorr signing.
                // Previously disabled due to invalid signatures caused by a bug
                // in the secp256k1 point doubling formula (divided by y instead of 2y).
                // That bug has been fixed — re-enabling native signing.
                "sign_message" -> {
                    val message = Nip55RequestCodec.payloadFromProjection(projection) ?: return null
                    val signature = Nip55NativeCrypto.signMessage(privateKey, message)
                    Nip55RequestCodec.operationResultCursor(signature)
                }
                "sign_event" -> {
                    val eventJson = Nip55RequestCodec.eventJsonFromProjection(projection) ?: return null
                    val result = Nip55NativeCrypto.signEvent(privateKey, eventJson, activePubkey)
                    if (result != null) {
                        Nip55RequestCodec.signEventCursor(result.signature, result.eventJson)
                    } else {
                        Log.w(TAG, "performNativeCrypto: signEvent returned null (pubkey mismatch?), falling back")
                        null
                    }
                }
                "decrypt_zap_event" -> {
                    // NIP-57 private zap: the payload is the full zap request event JSON.
                    // We parse it, extract the P tag (sender pubkey) and decrypt
                    // the content field using NIP-04.
                    val eventJson = Nip55RequestCodec.eventJsonFromProjection(projection) ?: return null
                    val result = Nip55NativeCrypto.decryptZapEvent(privateKey, eventJson)
                    if (result != null) {
                        Nip55RequestCodec.operationResultCursor(result)
                    } else {
                        Log.w(TAG, "performNativeCrypto: decryptZapEvent failed, falling back")
                        null
                    }
                }
                else -> null
            }
        } catch (e: Exception) {
            Log.e(TAG, "performNativeCrypto: failed for method=$method", e)
            // On crypto failure, fall back to bridge rather than crashing
            null
        }
    }

    // ── Required ContentProvider overrides ───────────────────────────────

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    // ── Private helpers ──────────────────────────────────────────────────

    private fun callingPackage(): String? {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            callingPackage
        } else {
            null
        }
    }

    private fun hasLegacyRememberedReject(packageName: String?, method: String): Boolean {
        if (packageName.isNullOrBlank()) return false
        val preferences = context?.getSharedPreferences("nip55_provider_permissions_v1", 0)
            ?: return false
        return preferences.getString("$packageName:$method", null) == "reject"
    }

    private fun hasRequiredProjection(method: String, projection: Array<out String>?): Boolean {
        // currentUser is intentionally not required here — it is optional per NIP-55.
        // Clients that omit it (e.g. early Amethyst versions) will fall through to the
        // Flutter bridge which resolves identity from the active vault key. Requiring
        // currentUser here would block legitimate requests from clients that don't send it.
        return when (method) {
            "ping" -> true
            "get_public_key" -> true
            "sign_message" -> {
                !Nip55RequestCodec.payloadFromProjection(projection).isNullOrBlank()
            }
            "sign_event" -> {
                !Nip55RequestCodec.eventJsonFromProjection(projection).isNullOrBlank()
            }
            "nip04_encrypt", "nip04_decrypt", "nip44_encrypt", "nip44_decrypt" -> {
                !Nip55RequestCodec.payloadFromProjection(projection).isNullOrBlank() &&
                    !Nip55RequestCodec.peerPubkeyFromProjection(projection).isNullOrBlank()
            }
            "decrypt_zap_event" -> {
                !Nip55RequestCodec.payloadFromProjection(projection).isNullOrBlank()
            }
            else -> false
        }
    }

    private fun providerArguments(
        method: String,
        projection: Array<out String>?,
        callerPackage: String?,
    ): Map<String, Any?> {
        val requestToken = "provider-${System.currentTimeMillis()}-${System.identityHashCode(projection)}"
        val args = mutableMapOf<String, Any?>(
            "requestToken" to requestToken,
            "type" to method,
            "callingPackage" to callerPackage,
            "callerCertificateSha256" to resolveSigningCertificateSha256(callerPackage),
            "sourceHint" to callerPackage,
            "transport" to "content_provider"
        )
        when (method) {
            "sign_event" -> {
                args["content"] = Nip55RequestCodec.eventJsonFromProjection(projection)
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection, method)
            }
            "sign_message" -> {
                args["content"] = Nip55RequestCodec.payloadFromProjection(projection)
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection, method)
            }
            "get_public_key" -> {
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection, method)
            }
            "nip04_encrypt", "nip04_decrypt", "nip44_encrypt", "nip44_decrypt" -> {
                args["content"] = Nip55RequestCodec.payloadFromProjection(projection)
                args["pubkey"] = Nip55RequestCodec.peerPubkeyFromProjection(projection)
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection, method)
            }
            "decrypt_zap_event" -> {
                args["content"] = Nip55RequestCodec.payloadFromProjection(projection)
                args["currentUser"] = Nip55RequestCodec.zapCurrentUserFromProjection(projection)
            }
        }
        return args
    }

    private fun resolveSigningCertificateSha256(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        val packageManager = context?.packageManager ?: return null

        // Key the cache by package + version code so a package update
        // (which may change the signing certificate on re-key) invalidates
        // the cached value automatically.
        val versionCode = try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(packageName, 0).longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0).versionCode.toLong()
            }
        } catch (_: Exception) {
            return null
        }
        val cacheKey = "$packageName:$versionCode"
        certificateCache[cacheKey]?.let { return it }

        return try {
            val signatures = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                val info = packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                )
                info.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                info.signatures
            }
            val signature = signatures?.firstOrNull() ?: return null
            val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            val cert = digest.joinToString(":") { byte -> "%02X".format(byte) }
            certificateCache[cacheKey] = cert
            cert
        } catch (_: Exception) {
            null
        }
    }
}