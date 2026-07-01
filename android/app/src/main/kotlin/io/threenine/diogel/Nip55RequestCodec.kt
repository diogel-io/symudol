package io.threenine.diogel

import android.database.MatrixCursor
import android.net.Uri
import io.threenine.diogel.BuildConfig

object Nip55RequestCodec {
    // Authorities are derived from the installed application id so that debug,
    // release, and flavored builds all expose the correct content:// authority.
    // Clients (Amethyst, Quartz) build URIs as content://<signerPackage>.SIGN_EVENT;
    // using the selected signer's package name — this keeps that contract intact.
    val AUTHORITY_SIGN_EVENT = "${BuildConfig.APPLICATION_ID}.SIGN_EVENT"
    val AUTHORITY_SIGN_MESSAGE = "${BuildConfig.APPLICATION_ID}.SIGN_MESSAGE"
    val AUTHORITY_NIP44_ENCRYPT = "${BuildConfig.APPLICATION_ID}.NIP44_ENCRYPT"
    val AUTHORITY_NIP44_DECRYPT = "${BuildConfig.APPLICATION_ID}.NIP44_DECRYPT"
    val AUTHORITY_NIP04_ENCRYPT = "${BuildConfig.APPLICATION_ID}.NIP04_ENCRYPT"
    val AUTHORITY_NIP04_DECRYPT = "${BuildConfig.APPLICATION_ID}.NIP04_DECRYPT"
    val AUTHORITY_DECRYPT_ZAP_EVENT = "${BuildConfig.APPLICATION_ID}.DECRYPT_ZAP_EVENT"
    val AUTHORITY_GET_PUBLIC_KEY = "${BuildConfig.APPLICATION_ID}.GET_PUBLIC_KEY"
    val AUTHORITY_PING = "${BuildConfig.APPLICATION_ID}.PING"

    private val supportedAuthorities = setOf(
        AUTHORITY_SIGN_EVENT,
        AUTHORITY_SIGN_MESSAGE,
        AUTHORITY_NIP44_ENCRYPT,
        AUTHORITY_NIP44_DECRYPT,
        AUTHORITY_NIP04_ENCRYPT,
        AUTHORITY_NIP04_DECRYPT,
        AUTHORITY_DECRYPT_ZAP_EVENT,
        AUTHORITY_GET_PUBLIC_KEY,
        AUTHORITY_PING,
    )

    fun isSupportedAuthority(authority: String?): Boolean {
        return authority != null && supportedAuthorities.contains(authority)
    }

    fun methodFor(uri: Uri): String? {
        return when (uri.authority) {
            AUTHORITY_SIGN_EVENT -> "sign_event"
            AUTHORITY_SIGN_MESSAGE -> "sign_message"
            AUTHORITY_NIP44_ENCRYPT -> "nip44_encrypt"
            AUTHORITY_NIP44_DECRYPT -> "nip44_decrypt"
            AUTHORITY_NIP04_ENCRYPT -> "nip04_encrypt"
            AUTHORITY_NIP04_DECRYPT -> "nip04_decrypt"
            AUTHORITY_DECRYPT_ZAP_EVENT -> "decrypt_zap_event"
            AUTHORITY_GET_PUBLIC_KEY -> "get_public_key"
            AUTHORITY_PING -> "ping"
            else -> null
        }
    }

    fun eventJsonFromProjection(projection: Array<out String>?): String? {
        return projection?.firstOrNull()?.takeIf { it.isNotBlank() }
    }

    fun payloadFromProjection(projection: Array<out String>?): String? {
        return projection?.firstOrNull()?.takeIf { it.isNotBlank() }
    }

    fun peerPubkeyFromProjection(projection: Array<out String>?): String? {
        return projection?.getOrNull(1)?.takeIf { it.isNotBlank() }
    }

    fun currentUserFromProjection(projection: Array<out String>?, method: String? = null): String? {
        val index = when (method) {
            // Amethyst/Quartz probes GET_PUBLIC_KEY with projection ["login"].
            // That value is not a NIP-55 current_user pubkey, so never forward it
            // into Dart as currentUser or the parser will correctly reject it.
            "get_public_key" -> return null
            "sign_event", "sign_message", "decrypt_zap_event" -> 1
            else -> 2
        }
        return projection?.getOrNull(index)?.takeIf { it.isNotBlank() }
    }

    fun zapCurrentUserFromProjection(projection: Array<out String>?): String? {
        return currentUserFromProjection(projection, "decrypt_zap_event")
    }

    fun rejectedCursor(reason: String = "rejected"): MatrixCursor {
        return MatrixCursor(arrayOf("rejected")).apply {
            addRow(arrayOf(true))
        }
    }

    fun signEventCursor(signature: String, eventJson: String): MatrixCursor {
        return MatrixCursor(arrayOf("signature", "result", "event")).apply {
            addRow(arrayOf(signature, signature, eventJson))
        }
    }

    fun operationResultCursor(result: String): MatrixCursor {
        return MatrixCursor(arrayOf("signature", "result", "event")).apply {
            addRow(arrayOf(result, result, result))
        }
    }
}
