package io.diogel.nip55testclient

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri

/** How the client reaches Symudol: the NIP-55 intent and the ContentProvider. */
object Signer {
    const val PACKAGE = "io.diogel.symudol"

    /**
     * A `nostrsigner:` request, built the way Amethyst builds it: the content goes in the URI
     * unencoded, and the rest in extras.
     */
    fun intent(type: String, content: String, extras: Map<String, String?> = emptyMap()): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:$content")).apply {
            setPackage(PACKAGE)
            putExtra("type", type)
            extras.forEach { (key, value) -> if (value != null) putExtra(key, value) }
        }

    fun authority(method: String): String = "$PACKAGE.${method.uppercase()}"
}

/** What the ContentProvider answered. */
sealed interface ProviderAnswer {
    /** No cursor: the client is expected to fall back to the intent. */
    data object None : ProviderAnswer

    data class Rejected(val value: String?) : ProviderAnswer

    data class Answered(val result: String, val event: String?) : ProviderAnswer

    data class Error(val message: String) : ProviderAnswer
}

/** Queries one NIP-55 method. Blocks: call it off the main thread. */
fun ContentResolver.queryNip55(method: String, projection: Array<String>): ProviderAnswer {
    val cursor = try {
        query(Uri.parse("content://${Signer.authority(method)}"), projection, "1", null, null)
    } catch (e: Exception) {
        return ProviderAnswer.Error("${e.javaClass.simpleName}: ${e.message}")
    } ?: return ProviderAnswer.None
    return cursor.use {
        if (!it.moveToFirst()) return@use ProviderAnswer.None
        val rejected = it.getColumnIndex("rejected")
        if (rejected >= 0) return@use ProviderAnswer.Rejected(it.getString(rejected))
        val result = it.getColumnIndex("result")
        if (result < 0) return@use ProviderAnswer.None
        val event = it.getColumnIndex("event")
        ProviderAnswer.Answered(it.getString(result), if (event >= 0) it.getString(event) else null)
    }
}

fun ProviderAnswer.describe(): String = when (this) {
    ProviderAnswer.None -> "no answer"
    is ProviderAnswer.Rejected -> "rejected ($value)"
    is ProviderAnswer.Answered -> "answered"
    is ProviderAnswer.Error -> "error: $message"
}
