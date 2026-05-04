package io.threenine.diogel

import android.database.MatrixCursor
import android.net.Uri

object Nip55RequestCodec {
    const val AUTHORITY_SIGN_EVENT = "io.threenine.diogel.SIGN_EVENT"
    const val AUTHORITY_NIP44_ENCRYPT = "io.threenine.diogel.NIP44_ENCRYPT"
    const val AUTHORITY_NIP44_DECRYPT = "io.threenine.diogel.NIP44_DECRYPT"
    const val AUTHORITY_NIP04_ENCRYPT = "io.threenine.diogel.NIP04_ENCRYPT"
    const val AUTHORITY_NIP04_DECRYPT = "io.threenine.diogel.NIP04_DECRYPT"
    const val AUTHORITY_DECRYPT_ZAP_EVENT = "io.threenine.diogel.DECRYPT_ZAP_EVENT"

    private val supportedAuthorities = setOf(
        AUTHORITY_SIGN_EVENT,
        AUTHORITY_NIP44_ENCRYPT,
        AUTHORITY_NIP44_DECRYPT,
        AUTHORITY_NIP04_ENCRYPT,
        AUTHORITY_NIP04_DECRYPT,
        AUTHORITY_DECRYPT_ZAP_EVENT,
    )

    fun isSupportedAuthority(authority: String?): Boolean {
        return authority != null && supportedAuthorities.contains(authority)
    }

    fun methodFor(uri: Uri): String? {
        return when (uri.authority) {
            AUTHORITY_SIGN_EVENT -> "sign_event"
            AUTHORITY_NIP44_ENCRYPT -> "nip44_encrypt"
            AUTHORITY_NIP44_DECRYPT -> "nip44_decrypt"
            AUTHORITY_NIP04_ENCRYPT -> "nip04_encrypt"
            AUTHORITY_NIP04_DECRYPT -> "nip04_decrypt"
            AUTHORITY_DECRYPT_ZAP_EVENT -> "decrypt_zap_event"
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

    fun currentUserFromProjection(projection: Array<out String>?): String? {
        return projection?.getOrNull(2)?.takeIf { it.isNotBlank() }
    }

    fun zapCurrentUserFromProjection(projection: Array<out String>?): String? {
        return projection?.getOrNull(1)?.takeIf { it.isNotBlank() }
            ?: currentUserFromProjection(projection)
    }

    fun rejectedCursor(reason: String = "rejected"): MatrixCursor {
        return MatrixCursor(arrayOf("rejected")).apply {
            addRow(arrayOf(reason))
        }
    }

    fun signEventCursor(signature: String, eventJson: String): MatrixCursor {
        return MatrixCursor(arrayOf("result", "event")).apply {
            addRow(arrayOf(signature, eventJson))
        }
    }

    fun operationResultCursor(result: String): MatrixCursor {
        return MatrixCursor(arrayOf("result")).apply {
            addRow(arrayOf(result))
        }
    }
}
