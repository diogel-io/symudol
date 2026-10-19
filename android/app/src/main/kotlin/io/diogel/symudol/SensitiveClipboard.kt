package io.diogel.symudol

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle

/**
 * The only way Symudol puts text on the clipboard (#94). Every clip is marked sensitive, so
 * Android 13+ shows a redacted preview instead of the text, and keyboards with a clipboard history
 * are asked not to keep it. NIP-55 results can be decrypted plaintext, and the NIP-46 bunker URI
 * carries the connection secret.
 */
internal object SensitiveClipboard {
    /** `ClipDescription.EXTRA_IS_SENSITIVE` (API 33); the same key works from API 24. */
    const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"

    fun clip(label: String, text: String): ClipData =
        ClipData.newPlainText(label, text).apply {
            description.extras = PersistableBundle().apply { putBoolean(EXTRA_IS_SENSITIVE, true) }
        }

    fun copy(context: Context, label: String, text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        clipboard.setPrimaryClip(clip(label, text))
    }
}
