package io.threenine.diogel

import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

class Nip55ContentProvider : ContentProvider() {
    companion object {
        private val certificateCache = ConcurrentHashMap<String, String>()
    }
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        if (!Nip55RequestCodec.isSupportedAuthority(uri.authority)) return null

        val method = Nip55RequestCodec.methodFor(uri) ?: return null
        val callerPackage = callingPackage()
        if (hasRememberedReject(callerPackage, method)) {
            return Nip55RequestCodec.rejectedCursor()
        }

        if (!hasRequiredProjection(method, projection)) return null

        // Fast-path ping without engaging the bridge
        if (method == "ping") {
            return Nip55RequestCodec.operationResultCursor("pong")
        }

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

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    private fun callingPackage(): String? {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            callingPackage
        } else {
            null
        }
    }

    private fun hasRememberedReject(packageName: String?, method: String): Boolean {
        if (packageName.isNullOrBlank()) return false
        val preferences = context?.getSharedPreferences("nip55_provider_permissions_v1", 0)
            ?: return false
        return preferences.getString("$packageName:$method", null) == "reject"
    }

    private fun hasRequiredProjection(method: String, projection: Array<out String>?): Boolean {
        return when (method) {
            "ping" -> true
            "get_public_key" -> true
            "sign_event" -> {
                !Nip55RequestCodec.eventJsonFromProjection(projection).isNullOrBlank() &&
                    !Nip55RequestCodec.currentUserFromProjection(projection).isNullOrBlank()
            }
            "nip04_encrypt",
            "nip04_decrypt",
            "nip44_encrypt",
            "nip44_decrypt" -> {
                !Nip55RequestCodec.payloadFromProjection(projection).isNullOrBlank() &&
                    !Nip55RequestCodec.peerPubkeyFromProjection(projection).isNullOrBlank() &&
                    !Nip55RequestCodec.currentUserFromProjection(projection).isNullOrBlank()
            }
            "decrypt_zap_event" -> {
                !Nip55RequestCodec.payloadFromProjection(projection).isNullOrBlank() &&
                    !Nip55RequestCodec.zapCurrentUserFromProjection(projection).isNullOrBlank()
            }
            else -> false
        }
    }

    private fun providerArguments(
        method: String,
        projection: Array<out String>?,
        callerPackage: String?
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
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection)
            }
            "get_public_key" -> {
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection)
            }
            "nip04_encrypt",
            "nip04_decrypt",
            "nip44_encrypt",
            "nip44_decrypt" -> {
                args["content"] = Nip55RequestCodec.payloadFromProjection(projection)
                args["pubkey"] = Nip55RequestCodec.peerPubkeyFromProjection(projection)
                args["currentUser"] = Nip55RequestCodec.currentUserFromProjection(projection)
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
        certificateCache[packageName]?.let { return it }
        val packageManager = context?.packageManager ?: return null
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
            val cert = digest.joinToString(":") { byte -> "%02X".format(byte) }
            certificateCache[packageName] = cert
            cert
        } catch (_: Exception) {
            null
        }
    }
}
