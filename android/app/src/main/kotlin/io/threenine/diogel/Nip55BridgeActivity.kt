package io.threenine.diogel

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

        val token = "${getString(R.string.token_prefix_bridge)}${System.currentTimeMillis()}-${System.identityHashCode(original)}"
        requestToken = token
        Nip55BridgeRegistry.register(token, this)

        val callerPackage = callingPackage ?: original.`package`
        val originalData = original.data!!
        val originalTypeExtra = original.getStringExtra(getString(R.string.key_type))
        val originalType = originalTypeExtra ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_type))
        val shouldUseControlQueryForContent = originalTypeExtra == null || originalType == getString(R.string.method_nip04_decrypt)
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            // Keep this bridge activity alive because it owns the caller's Activity result.
            // CLEAR_TOP would destroy/unregister the bridge when Diogel is already open,
            // which leaves the caller waiting until its NIP-55 timeout. NEW_TASK keeps
            // Diogel's Flutter UI in Diogel's own task instead of putting it inside the
            // caller app's task; otherwise moveTaskToBack can background the caller.
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(getString(R.string.key_request_token), token)
            putExtra(getString(R.string.key_type), originalType)
            putExtra(getString(R.string.key_content), original.getStringExtra(getString(R.string.key_content)) ?: Nip55UriParser.content(originalData, originalType, shouldUseControlQueryForContent))
            putExtra(getString(R.string.key_id), original.getStringExtra(getString(R.string.key_id)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_id)))
            putExtra(getString(R.string.key_current_user), original.getStringExtra(getString(R.string.key_current_user)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_current_user)))
            putExtra(getString(R.string.key_pubkey), original.getStringExtra(getString(R.string.key_pubkey)) ?: original.getStringExtra(getString(R.string.key_pubkey_alt)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_pubkey)))
            putExtra(getString(R.string.key_permissions), original.getStringExtra(getString(R.string.key_permissions)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_permissions)))
            putExtra(getString(R.string.key_callback_url), original.getStringExtra(getString(R.string.key_callback_url)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_callback_url)))
            putExtra(getString(R.string.key_return_type), original.getStringExtra(getString(R.string.key_return_type)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_return_type)))
            putExtra(getString(R.string.key_compression_type), original.getStringExtra(getString(R.string.key_compression_type)) ?: Nip55UriParser.queryParameter(originalData, getString(R.string.key_compression_type)))
            putExtra(getString(R.string.key_is_browser_flow), original.hasCategory(Intent.CATEGORY_BROWSABLE))
            putExtra(getString(R.string.key_calling_package), callerPackage)
            putExtra(getString(R.string.key_caller_app_label), resolveAppLabel(callerPackage))
            putExtra(getString(R.string.key_caller_certificate_sha256), resolveSigningCertificateSha256(callerPackage))
            putExtra(getString(R.string.key_referrer), referrer?.toString())
            putExtra(getString(R.string.key_intent_package), original.`package`)
            putExtra(getString(R.string.key_source_hint), callerPackage ?: referrer?.host)
            putExtra(getString(R.string.key_data_uri), original.data?.toString())
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
        return try {
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
    }
}
