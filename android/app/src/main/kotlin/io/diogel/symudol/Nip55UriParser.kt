package io.diogel.symudol

import android.net.Uri

object Nip55UriParser {
    private val controlQueryKeys = setOf(
        "type",
        "id",
        "current_user",
        "pubkey",
        "permissions",
        "callbackUrl",
        "returnType",
        "compressionType",
        "iv",
    )

    fun content(uri: Uri, method: String? = null, useControlQuery: Boolean = true): String? {
        val raw = uri.schemeSpecificPart ?: return null
        if (raw.isBlank()) return null
        val queryStart = if (useControlQuery) controlQueryStart(raw) else -1
        val withoutQuery = if (queryStart >= 0) raw.substring(0, queryStart) else raw
        val normalized = withoutQuery.removePrefix("//")
        if (normalized.isBlank()) return null
        return try {
            val decodedPayload = Uri.decode(normalized)
            val rawIv = rawQueryParameter(uri, "iv")
            if (method == "nip04_decrypt" && !rawIv.isNullOrBlank()) {
                "$decodedPayload?iv=${Uri.decode(rawIv)}"
            } else {
                decodedPayload
            }
        } catch (_: Exception) {
            null
        }
    }

    fun queryParameter(uri: Uri, name: String): String? {
        return queryParameters(uri)[name]
    }

    fun queryParameters(uri: Uri): Map<String, String> {
        val query = queryString(uri) ?: return emptyMap()
        if (query.isBlank()) return emptyMap()
        return try {
            Uri.parse("https://diogel.invalid/?$query")
                .queryParameterNames
                .associateWith { name ->
                    Uri.parse("https://diogel.invalid/?$query").getQueryParameter(name).orEmpty()
                }
        } catch (_: Exception) {
            parseQueryStrictly(query)
        }
    }

    private fun rawQueryParameter(uri: Uri, name: String): String? {
        val query = queryString(uri) ?: return null
        query.split('&').forEach { pair ->
            if (pair.isBlank()) return@forEach
            val key = pair.substringBefore('=')
            if (Uri.decode(key) == name) {
                return pair.substringAfter('=', "")
            }
        }
        return null
    }

    private fun queryString(uri: Uri): String? {
        if (uri.isHierarchical) {
            return uri.encodedQuery
        }
        val raw = uri.schemeSpecificPart ?: return null
        val marker = controlQueryStart(raw)
        if (marker < 0 || marker == raw.lastIndex) return null
        return raw.substring(marker + 1)
    }

    private fun controlQueryStart(raw: String): Int {
        var marker = raw.indexOf('?')
        while (marker >= 0 && marker < raw.lastIndex) {
            if (containsControlQueryKey(raw.substring(marker + 1))) {
                return marker
            }
            marker = raw.indexOf('?', marker + 1)
        }
        return -1
    }

    private fun containsControlQueryKey(query: String): Boolean {
        query.split('&').forEach { pair ->
            if (pair.isBlank()) return@forEach
            val key = pair.substringBefore('=')
            try {
                if (controlQueryKeys.contains(Uri.decode(key))) return true
            } catch (_: Exception) {
                // Ignore malformed keys and keep scanning.
            }
        }
        return false
    }

    private fun parseQueryStrictly(query: String): Map<String, String> {
        val params = linkedMapOf<String, String>()
        query.split('&').forEach { pair ->
            if (pair.isBlank()) return@forEach
            val key = pair.substringBefore('=')
            val value = pair.substringAfter('=', "")
            try {
                params[Uri.decode(key)] = Uri.decode(value)
            } catch (_: Exception) {
                // Drop malformed parameter rather than crashing the caller path.
            }
        }
        return params
    }
}
