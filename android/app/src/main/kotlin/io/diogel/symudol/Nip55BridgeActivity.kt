package io.diogel.symudol

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.security.MessageDigest

class Nip55BridgeActivity : Activity() {
    private var requestToken: String? = null

    companion object {
        // ── Certificate SHA-256 cache ────────────────────────────────────
        // PackageManager.getPackageInfo(GET_SIGNING_CERTIFICATES) is a binder
        // call that takes 1-5 ms. Cache per-package on first lookup; certificates
        // don't change at runtime without reinstalling the app.
        // Accessed only from the main thread (Activity lifecycle), so HashMap is safe.
        private val certCache = HashMap<String, String?>()

        // ── Foreground request rate limiter ───────────────────────────────
        // Prevents abusive clients from spamming the approval UI. Keyed by
        // callerPackage|method and optionally |kind for sign_event. Each entry
        // stores a list of timestamps (epoch ms); old entries are pruned on access.
        //
        // Policy:
        //   get_public_key: 5 per 30 s (login picker retries should not fail)
        //   all others:     3 per 30 s
        private const val WINDOW_MS = 30_000L
        private const val DEFAULT_BURST = 3
        private const val GET_PUBLIC_KEY_BURST = 5
        private val rateBuckets = LinkedHashMap<String, ArrayDeque<Long>>(16, 0.75f, true)

        /**
         * Returns true if the request should be rate-limited. Advances the
         * window counter for the key.
         *
         * Thread safety: [rateBuckets] is accessed without synchronization.
         * This is safe because [isRateLimited] is only called from
         * [handleNip55Intent], which is invoked by [onCreate] and [onNewIntent]
         * — both are main-thread Activity lifecycle callbacks. If this function
         * is ever called from a background thread, it must be synchronized.
         */
        internal fun isRateLimited(callerPackage: String?, method: String?, kind: Int?): Boolean {
            val bucket = buildKey(callerPackage, method, kind)
            val nowMs = System.currentTimeMillis()
            val timestamps = rateBuckets.getOrPut(bucket) { ArrayDeque() }
            // Drop entries outside the window
            while (timestamps.isNotEmpty() && nowMs - timestamps.first() > WINDOW_MS) {
                timestamps.removeFirst()
            }
            val burst = if (method == "get_public_key") GET_PUBLIC_KEY_BURST else DEFAULT_BURST
            if (timestamps.size >= burst) return true
            timestamps.addLast(nowMs)
            // Evict LRU entries if the map grows large (shouldn't happen in normal use)
            if (rateBuckets.size > 64) {
                rateBuckets.entries.iterator().also { it.next(); it.remove() }
            }
            return false
        }

        private fun buildKey(callerPackage: String?, method: String?, kind: Int?): String {
            val base = "${callerPackage ?: "unknown"}|${method ?: "unknown"}"
            return if (kind != null) "$base|$kind" else base
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNip55Intent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNip55Intent(intent)
    }

    private fun handleNip55Intent(original: Intent?) {
        if (original?.action != Intent.ACTION_VIEW || original.data?.scheme != getString(R.string.scheme_nostrsigner)) {
            finish()
            return
        }

        val callerPackage = callingPackage ?: original.`package`
        val originalData = original.data!!
        val originalTypeExtra = original.getStringExtra(getString(R.string.key_type))
        val method = originalTypeExtra ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_type))

        // ── Rate limit ──────────────────────────────────────────────────
        // Extract event kind for sign_event keying (best-effort, no throw).
        val eventKind: Int? = if (method == "sign_event") {
            try {
                val contentRaw = original.getStringExtra(getString(R.string.key_content))
                    ?: Nip55UriParser.content(originalData, method, true)
                if (!contentRaw.isNullOrBlank()) org.json.JSONObject(contentRaw).optInt("kind").let { if (it == 0 && !contentRaw.contains('"' + "kind" + '"')) null else it } else null
            } catch (_: Exception) { null }
        } else null

        if (isRateLimited(callerPackage, method, eventKind)) {
            val rejectedIntent = Intent().apply {
                val incomingId = original.getStringExtra(getString(R.string.key_id))
                    ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_id))
                putExtra(getString(R.string.key_rejected), "rate_limited")
                if (incomingId != null) putExtra(getString(R.string.key_id), incomingId)
            }
            setResult(RESULT_CANCELED, rejectedIntent)
            finish()
            return
        }

        // Unguessable: the token is the only thing MainActivity accepts a request by (#7).
        val token = Nip55Handoff.newToken(getString(R.string.token_prefix_bridge))
        requestToken = token
        Nip55BridgeRegistry.register(token, this)
        val shouldUseControlQueryForContent = originalTypeExtra == null || method == getString(R.string.method_nip04_decrypt)
        // The whole request, with the caller as Android reports it, stays in this process.
        // MainActivity reads it from Nip55Handoff and never from intent extras, which any app
        // could set (#7).
        Nip55Handoff.register(token, mapOf(
            "requestToken" to token,
            "bridgeToken" to token,
            "type" to method,
            "content" to (original.getStringExtra(getString(R.string.key_content)) ?: Nip55UriParser.content(originalData, method, shouldUseControlQueryForContent)),
            "id" to (original.getStringExtra(getString(R.string.key_id)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_id))),
            "currentUser" to (original.getStringExtra(getString(R.string.key_current_user)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_current_user))),
            "pubkey" to (original.getStringExtra(getString(R.string.key_pubkey)) ?: original.getStringExtra(getString(R.string.key_pubkey_alt)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_pubkey))),
            "permissions" to (original.getStringExtra(getString(R.string.key_permissions)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_permissions))),
            "callbackUrl" to (original.getStringExtra(getString(R.string.key_callback_url)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_callback_url))),
            "returnType" to (original.getStringExtra(getString(R.string.key_return_type)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_return_type))),
            "compressionType" to (original.getStringExtra(getString(R.string.key_compression_type)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_compression_type))),
            "isBrowserFlow" to original.hasCategory(Intent.CATEGORY_BROWSABLE),
            "callingPackage" to callerPackage,
            "callerAppLabel" to resolveAppLabel(callerPackage),
            "callerCertificateSha256" to resolveSigningCertificateSha256(callerPackage),
            "referrer" to referrer?.toString(),
            "intentPackage" to original.`package`,
            "sourceHint" to (callerPackage ?: referrer?.host),
            "dataUri" to original.data?.toString(),
        ))
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            // Keep this bridge activity alive because it owns the caller's Activity result.
            // CLEAR_TOP would destroy/unregister the bridge when Diogel is already open,
            // which leaves the caller waiting until its NIP-55 timeout. NEW_TASK keeps
            // Diogel's Flutter UI in Diogel's own task instead of putting it inside the
            // caller app's task; otherwise moveTaskToBack can background the caller.
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            // Only the token: MainActivity reads the request from Nip55Handoff (#7).
            putExtra(getString(R.string.key_request_token), token)
        }
        startActivity(mainIntent)
        // If Flutter is already alive, deliver directly as a fallback after asking
        // Android to bring Diogel forward. REORDER_TO_FRONT is not guaranteed to
        // call onNewIntent for an existing activity, but delivering before the
        // startActivity handoff can leave the request waiting in a background UI.
        Handler(Looper.getMainLooper()).postDelayed({
            MainActivity.deliverNip55BridgeIntent(mainIntent)
        }, 150L)
    }

    override fun onDestroy() {
        requestToken?.let { Nip55BridgeRegistry.unregister(it) }
        super.onDestroy()
    }

    fun complete(resultIntent: Intent) {
        setResult(RESULT_OK, resultIntent)
        finish()
    }

    fun reject(resultIntent: Intent) {
        setResult(RESULT_CANCELED, resultIntent)
        finish()
    }

    private fun resolveAppLabel(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveSigningCertificateSha256(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        if (certCache.containsKey(packageName)) return certCache[packageName]
        val result = try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
                info.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                info.signatures
            }
            val signature = signatures?.firstOrNull() ?: return null
            val digest = MessageDigest.getInstance(getString(R.string.digest_sha256)).digest(signature.toByteArray())
            digest.joinToString(getString(R.string.separator_colon)) { byte -> getString(R.string.format_hex_byte).format(byte) }
        } catch (_: Exception) {
            null
        }
        certCache[packageName] = result
        return result
    }
}
