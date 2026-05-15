package io.threenine.diogel

import android.database.MatrixCursor
import android.net.Uri

object Nip55RequestCodec {
    const val AUTHORITY_SIGN_EVENT = "io.threenine.diogel.SIGN_EVENT"
    const val AUTHORITY_SIGN_MESSAGE = "io.threenine.diogel.SIGN_MESSAGE"
    const val AUTHORITY_NIP44_ENCRYPT = "io.threenine.diogel.NIP44_ENCRYPT"
    const val AUTHORITY_NIP44_DECRYPT = "io.threenine.diogel.NIP44_DECRYPT"
    const val AUTHORITY_NIP04_ENCRYPT = "io.threenine.diogel.NIP04_ENCRYPT"
    const val AUTHORITY_NIP04_DECRYPT = "io.threenine.diogel.NIP04_DECRYPT"
    const val AUTHORITY_DECRYPT_ZAP_EVENT = "io.threenine.diogel.DECRYPT_ZAP_EVENT"
    const val AUTHORITY_GET_PUBLIC_KEY = "io.threenine.diogel.GET_PUBLIC_KEY"
    const val AUTHORITY_PING = "io.threenine.diogel.PING"

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
