package io.threenine.androidiogel

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

class Nip55ContentProvider : ContentProvider() {
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

        // Safe WP5 MVP: do not launch UI, do not duplicate key handling native-side,
        // and do not sign while the Flutter/vault policy path is unavailable.
        // Returning null is the NIP-55-compatible response for "no remembered permission".
        if (method == "sign_event") {
            val eventJson = Nip55RequestCodec.eventJsonFromProjection(projection)
            val currentUser = Nip55RequestCodec.currentUserFromProjection(projection)
            if (eventJson.isNullOrBlank() || currentUser.isNullOrBlank()) return null
        }
        return null
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
}
