package io.diogel.symudol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Release builds hide NIP-46 (#26), so their manifest drops what only NIP-46 uses (#39): the
 * camera, the foreground service and its notification. Google Play then asks for no
 * foreground-service declaration and lists no camera permission. Delete this test with
 * src/release/AndroidManifest.xml when NIP-46 ships in release builds.
 */
class ReleaseManifestTest {
    private val androidNs = "http://schemas.android.com/apk/res/android"
    private val toolsNs = "http://schemas.android.com/tools"

    private fun parse(path: String): Element {
        val file = File(path)
        assertTrue("run from android/app: $path", file.exists())
        return DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(file).documentElement
    }

    private fun Element.children(tag: String): List<Element> {
        val nodes = getElementsByTagName(tag)
        return (0 until nodes.length).map { nodes.item(it) as Element }
    }

    private fun Element.removedNames(tag: String): Set<String> = children(tag)
        .filter { it.getAttributeNS(toolsNs, "node") == "remove" }
        .map { it.getAttributeNS(androidNs, "name") }
        .toSet()

    @Test
    fun releaseRemovesTheNip46Permissions() {
        val removed = parse("src/release/AndroidManifest.xml").removedNames("uses-permission")

        assertEquals(
            setOf(
                "android.permission.CAMERA",
                "android.permission.FOREGROUND_SERVICE",
                "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
                "android.permission.POST_NOTIFICATIONS",
            ),
            removed,
        )
    }

    @Test
    fun releaseRemovesTheNip46ForegroundService() {
        val removed = parse("src/release/AndroidManifest.xml").removedNames("service")

        assertEquals(setOf(".Nip46ForegroundService"), removed)
    }

    @Test
    fun releaseKeepsInternet() {
        val release = parse("src/release/AndroidManifest.xml")
        val main = parse("src/main/AndroidManifest.xml")

        assertTrue(
            "release does not remove INTERNET",
            "android.permission.INTERNET" !in release.removedNames("uses-permission"),
        )
        assertTrue(
            "main declares INTERNET",
            main.children("uses-permission").any { it.getAttributeNS(androidNs, "name") == "android.permission.INTERNET" },
        )
    }

    @Test
    fun everyRemovedServiceIsDeclaredInMain() {
        val declared = parse("src/main/AndroidManifest.xml").children("service")
            .map { it.getAttributeNS(androidNs, "name") }
            .toSet()

        for (name in parse("src/release/AndroidManifest.xml").removedNames("service")) {
            assertTrue("$name is declared in src/main", name in declared)
        }
    }
}
