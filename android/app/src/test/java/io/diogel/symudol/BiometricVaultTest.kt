package io.diogel.symudol

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What Dart is told about the biometric sensor and the prompt (#23). The Keystore key itself
 * needs a device and is checked on the emulator.
 */
class BiometricVaultTest {
    @Test
    fun availabilityNamesMatchDart() {
        assertEquals("available", BiometricVault.availabilityName(BiometricManager.BIOMETRIC_SUCCESS))
        assertEquals(
            "noneEnrolled",
            BiometricVault.availabilityName(BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED),
        )
        assertEquals(
            "noHardware",
            BiometricVault.availabilityName(BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE),
        )
        assertEquals(
            "unavailable",
            BiometricVault.availabilityName(BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE),
        )
        assertEquals(
            "unavailable",
            BiometricVault.availabilityName(
                BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED,
            ),
        )
    }

    @Test
    fun aCancelledPromptIsNotAnError() {
        for (code in listOf(
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_CANCELED,
        )) {
            assertEquals("cancelled", BiometricVault.errorCodeFor(code))
        }
    }

    @Test
    fun theOsLockoutSendsTheUserToThePin() {
        assertEquals("lockedOut", BiometricVault.errorCodeFor(BiometricPrompt.ERROR_LOCKOUT))
        assertEquals(
            "lockedOut",
            BiometricVault.errorCodeFor(BiometricPrompt.ERROR_LOCKOUT_PERMANENT),
        )
    }

    @Test
    fun noSensorOrNoFingerprintIsUnavailable() {
        for (code in listOf(
            BiometricPrompt.ERROR_NO_BIOMETRICS,
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
        )) {
            assertEquals("unavailable", BiometricVault.errorCodeFor(code))
        }
    }

    @Test
    fun onlyBiometricKeysAreDeleted() {
        assertTrue(BiometricVault.isBiometricAlias("symudol_biometric_dek_wrap"))
        assertTrue(BiometricVault.isBiometricAlias("symudol_biometric_dek_wrap.1700000000000"))
        // flutter_secure_storage's own key, and anything else in the app's Keystore, stay.
        assertFalse(BiometricVault.isBiometricAlias("symudol_biometric_dek_wrapper"))
        assertFalse(BiometricVault.isBiometricAlias("FlutterSecureStoragePluginKey"))
    }

    @Test
    fun anythingElseFails() {
        assertEquals("failed", BiometricVault.errorCodeFor(BiometricPrompt.ERROR_TIMEOUT))
        assertEquals("failed", BiometricVault.errorCodeFor(BiometricPrompt.ERROR_VENDOR))
    }
}
