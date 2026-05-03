package io.threenine.androidiogel

import android.net.Uri

object Nip55UriParser {
    fun content(uri: Uri): String? {
        val raw = uri.schemeSpecificPart ?: return null
        if (raw.isBlank()) return null
        val withoutQuery = raw.substringBefore("?")
        val normalized = withoutQuery.removePrefix("//")
        if (normalized.isBlank()) return null
        return try {
            Uri.decode(normalized)
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

    private fun queryString(uri: Uri): String? {
        if (uri.isHierarchical) {
            return uri.encodedQuery
        }
        val raw = uri.schemeSpecificPart ?: return null
        val marker = raw.indexOf('?')
        if (marker < 0 || marker == raw.lastIndex) return null
        return raw.substring(marker + 1)
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
