package io.threenine.androidiogel

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
            action = Intent.ACTION_VIEW
            data = original.data
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("requestToken", token)
            putExtra("type", original.getStringExtra("type"))
            putExtra("id", original.getStringExtra("id"))
            putExtra("current_user", original.getStringExtra("current_user"))
            putExtra("pubkey", original.getStringExtra("pubkey"))
            putExtra("permissions", original.getStringExtra("permissions"))
            putExtra("isBrowserFlow", original.hasCategory(Intent.CATEGORY_BROWSABLE))
            putExtra("callingPackage", callerPackage)
            putExtra("callerAppLabel", resolveAppLabel(callerPackage))
            putExtra("callerCertificateSha256", resolveSigningCertificateSha256(callerPackage))
            putExtra("referrer", referrer?.toString())
            putExtra("intentPackage", original.`package`)
            putExtra("sourceHint", callerPackage ?: referrer?.host)
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
