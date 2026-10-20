package io.diogel.symudol

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * Runs the shared NIP-55 permission cases (`test/features/nip55/fixtures/permission_matching_cases.json`)
 * through the matching the ContentProvider uses: grant parsing, its scope inputs and
 * [Nip55PermissionMirror.decide]. The Dart Nip55ApprovalPolicy runs the same file, so a change to
 * one matcher without the other fails one of the two (diogel-io/symudol#17).
 */
class Nip55PermissionParityTest {
    private val table: JSONObject by lazy {
        JSONObject(File(projectRoot(), "test/features/nip55/fixtures/permission_matching_cases.json").readText())
    }

    /** Gradle runs unit tests from android/app; the fixture lives beside the Dart tests. */
    private fun projectRoot(): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "pubspec.yaml").exists()) dir = dir.parentFile
        return checkNotNull(dir) { "no pubspec.yaml above ${System.getProperty("user.dir")}" }
    }

    private fun JSONObject.stringOrNull(key: String): String? =
        if (!has(key) || isNull(key)) null else getString(key)

    @Test
    fun everyCaseMatchesItsExpectedDecision() {
        val cases = table.getJSONArray("cases")
        val identity = table.getString("activeIdentity")
        val ownPackage = table.getString("ownPackage")
        val failures = mutableListOf<String>()
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            val request = case.getJSONObject("request")
            val method = request.getString("method")
            val grants = Nip55PermissionMirror.parseGrants(case.getJSONArray("grants").toString())
            assertEquals("${case.getString("id")}: every grant parses", case.getJSONArray("grants").length(), grants.size)
            val inputs = Nip55PermissionMirror.scopeInputs(
                method,
                request.optJSONObject("eventJson")?.toString(),
                request.stringOrNull("peerPubkey"),
            )
            val decision = Nip55PermissionMirror.decide(
                grants, ownPackage, request.stringOrNull("packageName"), method, identity, inputs,
                request.stringOrNull("certificateSha256"),
            ) ?: "none"
            val expected = case.getString("expected")
            if (decision != expected) failures += "${case.getString("id")}: expected $expected, got $decision"
        }
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    @Test
    fun caseIdsAreUniqueAndOutcomesKnown() {
        val cases = table.getJSONArray("cases")
        val ids = (0 until cases.length()).map { cases.getJSONObject(it).getString("id") }
        assertEquals("duplicate case ids", ids.size, ids.toSet().size)
        for (i in 0 until cases.length()) {
            val expected = cases.getJSONObject(i).getString("expected")
            assertTrue("${ids[i]}: unknown outcome $expected", expected in setOf("allow", "reject", "none"))
        }
    }

    /**
     * A new scope type needs cases before either matcher can claim to handle it. The types are
     * the ones Dart's Nip55PermissionScope.fromJson reads, taken from its source, plus the
     * "unsupported" fallback, since Dart writes every grant this side reads.
     */
    @Test
    fun everyScopeTypeHasACase() {
        val source = File(projectRoot(), "lib/features/nip55/domain/nip55_permission_scope.dart").readText()
        val fromJson = source.substring(
            source.indexOf("static Nip55PermissionScope fromJson"),
            source.indexOf("_ => UnsupportedScope("),
        )
        val scopeTypes = Regex("'([a-z0-9_]+)' =>").findAll(fromJson).map { it.groupValues[1] }.toSet() + "unsupported"
        assertTrue("found the scope types in fromJson", scopeTypes.size > 5)
        val cases = table.getJSONArray("cases")
        val covered = mutableSetOf<String>()
        for (i in 0 until cases.length()) {
            val grants = cases.getJSONObject(i).getJSONArray("grants")
            for (g in 0 until grants.length()) covered += grants.getJSONObject(g).getJSONObject("scope").getString("type")
        }
        assertEquals(scopeTypes, covered)
    }
}
