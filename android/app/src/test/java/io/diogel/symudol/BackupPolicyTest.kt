package io.diogel.symudol

import android.content.Context
import android.content.pm.ApplicationInfo
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Nothing Symudol stores leaves the phone through backup or device transfer (SR-22, #15).
 * allowBackup="false" covers Android 11 and below; on Android 12+ the data-extraction rules must
 * also exclude everything, because allowBackup does not stop device-to-device transfer.
 */
@RunWith(RobolectricTestRunner::class)
class BackupPolicyTest {
    private val allDomains = setOf(
        "root", "file", "database", "sharedpref", "external",
        "device_root", "device_file", "device_database", "device_sharedpref",
    )

    @Test
    fun backupIsOff() {
        val info = ApplicationProvider.getApplicationContext<Context>().applicationInfo

        assertEquals("allowBackup is false", 0, info.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
    }

    @Test
    fun theManifestPointsAtTheRules() {
        val manifest = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val application = manifest.getElementsByTagName("application").item(0) as Element

        assertEquals(
            "@xml/data_extraction_rules",
            application.getAttributeNS("http://schemas.android.com/apk/res/android", "dataExtractionRules"),
        )
    }

    @Test
    fun cloudBackupAndDeviceTransferExcludeEverything() {
        val rules = File("src/main/res/xml/data_extraction_rules.xml")
        assertTrue("run from android/app", rules.exists())
        val root = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(rules).documentElement

        for (section in listOf("cloud-backup", "device-transfer")) {
            val element = root.getElementsByTagName(section).item(0) as Element?
            assertTrue("$section is present", element != null)
            assertEquals("$section includes nothing", 0, element!!.getElementsByTagName("include").length)
            val excludes = element.getElementsByTagName("exclude")
            val excluded = (0 until excludes.length).map { excludes.item(it) as Element }
                .filter { it.getAttribute("path") == "." }
                .map { it.getAttribute("domain") }
                .toSet()
            assertEquals("$section excludes every domain", allDomains, excluded)
        }
    }
}
