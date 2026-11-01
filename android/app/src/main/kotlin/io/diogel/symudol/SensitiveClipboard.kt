package io.diogel.symudol

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import java.security.MessageDigest

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

    private val handler = Handler(Looper.getMainLooper())
    private var pendingClear: Runnable? = null

    /**
     * Throws [IllegalStateException] when there is no clipboard, so a caller never reports a copy that didn't happen.
     *
     * With [clearAfterMs], the clip is cleared after that delay, such as for an exported nsec (#24). A newer copy
     * cancels the clear. Android 10+ lets a background app neither read the clipboard nor hear of changes, so when
     * the clip can't be read the clear goes ahead: clearing the user's own later copy is better than leaving a key on
     * the clipboard. The delay runs in this process, so if Android kills it first the clip stays until the system
     * clears it.
     */
    fun copy(context: Context, label: String, text: String, clearAfterMs: Long? = null) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: throw IllegalStateException("no clipboard service")
        clipboard.setPrimaryClip(clip(label, text))
        // Only a copy that happened replaces the earlier one, and its clear.
        pendingClear?.let(handler::removeCallbacks)
        pendingClear = null
        if (clearAfterMs == null || clearAfterMs <= 0) return
        // A digest, so the text itself isn't kept until the clear.
        val digest = sha256(text)
        val clear = Runnable {
            pendingClear = null
            clearIfStillOurs(clipboard, digest)
        }
        pendingClear = clear
        handler.postDelayed(clear, clearAfterMs)
    }

    private fun clearIfStillOurs(clipboard: ClipboardManager, digest: ByteArray) {
        val current = try {
            clipboard.primaryClip?.getItemAt(0)?.text?.toString()
        } catch (e: Exception) {
            null
        }
        // Readable and replaced by something else: that copy isn't ours to clear.
        if (current != null && !MessageDigest.isEqual(sha256(current), digest)) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(clip("", ""))
            }
        } catch (e: Exception) {
            DiogelLog.w("SensitiveClipboard", "clear: clipboard clear failed", e)
        }
    }

    private fun sha256(text: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
}
