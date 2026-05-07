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
        if (original?.action != Intent.ACTION_VIEW || original.data?.scheme != "nostrsigner") {
            finish()
            return
        }

        val token = "nip55-${System.currentTimeMillis()}-${System.identityHashCode(original)}"
        requestToken = token
        Nip55BridgeRegistry.register(token, this)

        val callerPackage = callingPackage ?: original.`package`
        val originalData = original.data!!
        val originalTypeExtra = original.getStringExtra("type")
        val originalType = originalTypeExtra ?: Nip55UriParser.queryParameter(originalData, "type")
        val shouldUseControlQueryForContent = originalTypeExtra == null || originalType == "nip04_decrypt"
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            // Keep this bridge activity alive because it owns the caller's Activity result.
            // CLEAR_TOP would destroy/unregister the bridge when Diogel is already open,
            // which leaves the caller waiting until its NIP-55 timeout. NEW_TASK keeps
            // Diogel's Flutter UI in Diogel's own task instead of putting it inside the
            // caller app's task; otherwise moveTaskToBack can background the caller.
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("requestToken", token)
            putExtra("type", originalType)
            putExtra("content", original.getStringExtra("content") ?: Nip55UriParser.content(originalData, originalType, shouldUseControlQueryForContent))
            putExtra("id", original.getStringExtra("id") ?: Nip55UriParser.queryParameter(originalData, "id"))
            putExtra("current_user", original.getStringExtra("current_user") ?: Nip55UriParser.queryParameter(originalData, "current_user"))
            putExtra("pubkey", original.getStringExtra("pubkey") ?: original.getStringExtra("pubKey") ?: Nip55UriParser.queryParameter(originalData, "pubkey"))
            putExtra("permissions", original.getStringExtra("permissions") ?: Nip55UriParser.queryParameter(originalData, "permissions"))
            putExtra("callbackUrl", original.getStringExtra("callbackUrl") ?: Nip55UriParser.queryParameter(originalData, "callbackUrl"))
            putExtra("returnType", original.getStringExtra("returnType") ?: Nip55UriParser.queryParameter(originalData, "returnType"))
            putExtra("compressionType", original.getStringExtra("compressionType") ?: Nip55UriParser.queryParameter(originalData, "compressionType"))
            putExtra("isBrowserFlow", original.hasCategory(Intent.CATEGORY_BROWSABLE))
            putExtra("callingPackage", callerPackage)
            putExtra("callerAppLabel", resolveAppLabel(callerPackage))
            putExtra("callerCertificateSha256", resolveSigningCertificateSha256(callerPackage))
            putExtra("referrer", referrer?.toString())
            putExtra("intentPackage", original.`package`)
            putExtra("sourceHint", callerPackage ?: referrer?.host)
            putExtra("dataUri", original.data?.toString())
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
            val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            digest.joinToString(":") { byte -> "%02X".format(byte) }
        } catch (_: Exception) {
            null
        }
    }
}
