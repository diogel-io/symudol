package io.threenine.diogel

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import java.security.MessageDigest

class Nip55BridgeActivity : Activity() {
    private var requestToken: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val original = intent
        if (original?.action != Intent.ACTION_VIEW || original.data?.scheme != "nostrsigner") {
            finish()
            return
        }

        val token = "nip55-${System.currentTimeMillis()}-${System.identityHashCode(this)}"
        requestToken = token
        Nip55BridgeRegistry.register(token, this)

        val callerPackage = callingPackage ?: original.`package`
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("requestToken", token)
            putExtra("type", original.getStringExtra("type") ?: Nip55UriParser.queryParameter(original.data!!, "type"))
            putExtra("content", original.getStringExtra("content") ?: Nip55UriParser.content(original.data!!))
            putExtra("id", original.getStringExtra("id") ?: Nip55UriParser.queryParameter(original.data!!, "id"))
            putExtra("current_user", original.getStringExtra("current_user") ?: Nip55UriParser.queryParameter(original.data!!, "current_user"))
            putExtra("pubkey", original.getStringExtra("pubkey") ?: Nip55UriParser.queryParameter(original.data!!, "pubkey"))
            putExtra("permissions", original.getStringExtra("permissions") ?: Nip55UriParser.queryParameter(original.data!!, "permissions"))
            putExtra("callbackUrl", original.getStringExtra("callbackUrl") ?: Nip55UriParser.queryParameter(original.data!!, "callbackUrl"))
            putExtra("returnType", original.getStringExtra("returnType") ?: Nip55UriParser.queryParameter(original.data!!, "returnType"))
            putExtra("compressionType", original.getStringExtra("compressionType") ?: Nip55UriParser.queryParameter(original.data!!, "compressionType"))
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
