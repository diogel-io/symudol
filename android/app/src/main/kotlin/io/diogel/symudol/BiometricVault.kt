package io.diogel.symudol

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Biometric unlock (diogel-io/symudol#23): an AES-256-GCM key in the Android Keystore wraps the
 * vault's DEK, and each use of the key needs a fresh strong biometric, checked by
 * [BiometricPrompt] with the key's cipher. The Keystore enforces the check; a yes from a dialog
 * is not enough.
 *
 * Adding a fingerprint, or removing the screen lock, invalidates the key for good. Dart then
 * turns biometric unlock off and the PIN still works.
 *
 * The DEK passes through here only in [wrap] and [unwrap], and the copies are zeroed once
 * handed over. Nothing about it is logged (SR-21).
 */
class BiometricVault(private val activity: FragmentActivity) {
    companion object {
        const val CHANNEL = "io.diogel.symudol/biometric"
        private const val TAG = "Diogel-BiometricVault"
        private const val KEYSTORE = "AndroidKeyStore"
        /** Each wrap gets its own key, `<prefix>.<time>`, so a cancelled turn-on keeps the old one. */
        private const val KEY_PREFIX = "symudol_biometric_dek_wrap"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128

        /** The Dart name for a [BiometricManager.canAuthenticate] result. */
        fun availabilityName(canAuthenticate: Int): String = when (canAuthenticate) {
            BiometricManager.BIOMETRIC_SUCCESS -> "available"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "noneEnrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "noHardware"
            else -> "unavailable"
        }

        /** Whether [alias] is one of the biometric keys, including the unsuffixed first one. */
        fun isBiometricAlias(alias: String): Boolean =
            alias == KEY_PREFIX || alias.startsWith("$KEY_PREFIX.")

        /**
         * Deletes each biometric key in [aliases] except [keep], going on past a key that can't
         * be deleted. Returns the aliases that are left behind.
         */
        fun deleteBiometricAliases(
            aliases: List<String>,
            keep: String?,
            delete: (String) -> Unit,
        ): List<String> = aliases
            .filter { isBiometricAlias(it) && it != keep }
            .filterNot { alias ->
                try {
                    delete(alias)
                    true
                } catch (e: Exception) {
                    false
                }
            }

        /** The error code Dart acts on for a [BiometricPrompt] error. */
        fun errorCodeFor(promptError: Int): String = when (promptError) {
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_CANCELED -> "cancelled"
            BiometricPrompt.ERROR_LOCKOUT,
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockedOut"
            BiometricPrompt.ERROR_NO_BIOMETRICS,
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "unavailable"
            else -> "failed"
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> result.success(availability(activity))
            "wrap" -> {
                val dek = call.argument<ByteArray>("dek")
                    ?: return result.error("INVALID_ARGS", "dek required", null)
                wrap(dek, result)
            }
            "unwrap" -> {
                val alias = call.argument<String>("alias")
                val iv = call.argument<ByteArray>("iv")
                val ciphertext = call.argument<ByteArray>("ciphertext")
                if (alias == null || !isBiometricAlias(alias) || iv == null || ciphertext == null) {
                    return result.error("INVALID_ARGS", "alias, iv and ciphertext required", null)
                }
                unwrap(alias, iv, ciphertext, result)
            }
            "deleteKey" -> {
                try {
                    deleteKeys()
                    result.success(null)
                } catch (e: Exception) {
                    DiogelLog.w(TAG, "deleteKey failed", e)
                    result.error("failed", "could not delete the key", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun availability(context: Context): String =
        availabilityName(BiometricManager.from(context).canAuthenticate(BIOMETRIC_STRONG))

    private fun wrap(dek: ByteArray, result: MethodChannel.Result) {
        // A new key beside the old one: the old wrap keeps working until this one succeeds.
        val alias = "$KEY_PREFIX.${System.currentTimeMillis()}"
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, createKey(alias)) }
        } catch (e: Exception) {
            dek.fill(0)
            deleteKeyQuietly(alias)
            DiogelLog.w(TAG, "wrap: could not create the key", e)
            return result.error("failed", "could not create the biometric key", null)
        }
        var wrapped = false
        authenticate(
            cipher,
            title = "Turn on biometric unlock",
            negative = "Cancel",
            result = result,
            onCleanup = {
                dek.fill(0)
                // Keep only the key that wrapped this DEK; on cancel or failure, only the old one.
                // The answer has gone to Dart, so a key left behind is only logged.
                if (wrapped) deleteOldKeysQuietly(alias) else deleteKeyQuietly(alias)
            },
        ) { authenticated ->
            val ciphertext = authenticated.doFinal(dek)
            wrapped = true
            result.success(
                mapOf("alias" to alias, "iv" to authenticated.iv, "ciphertext" to ciphertext),
            )
        }
    }

    private fun unwrap(alias: String, iv: ByteArray, ciphertext: ByteArray, result: MethodChannel.Result) {
        val cipher = try {
            val key = KeyStore.getInstance(KEYSTORE).apply { load(null) }
                .getKey(alias, null) as? SecretKey
                ?: return result.error("keyInvalidated", "the biometric key is gone", null)
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            return result.error("keyInvalidated", "the biometric key was invalidated", null)
        } catch (e: Exception) {
            DiogelLog.w(TAG, "unwrap: could not open the key", e)
            return result.error("failed", "could not open the biometric key", null)
        }
        authenticate(cipher, title = "Unlock Symudol", negative = "Use PIN", result = result) {
                authenticated ->
            val dek = authenticated.doFinal(ciphertext)
            // The codec copies the bytes during success(), so this copy can be cleared after.
            result.success(dek)
            dek.fill(0)
        }
    }

    private fun authenticate(
        cipher: Cipher,
        title: String,
        negative: String,
        result: MethodChannel.Result,
        onCleanup: () -> Unit = {},
        onAuthenticated: (Cipher) -> Unit,
    ) {
        var answered = false
        fun answer(block: () -> Unit) {
            if (answered) return
            answered = true
            try {
                block()
            } finally {
                onCleanup()
            }
        }

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                answer {
                    val authenticated = auth.cryptoObject?.cipher
                    if (authenticated == null) {
                        result.error("failed", "no cipher after authentication", null)
                        return@answer
                    }
                    try {
                        onAuthenticated(authenticated)
                    } catch (e: Exception) {
                        DiogelLog.w(TAG, "the cipher failed after authentication", e)
                        result.error("failed", "the biometric key could not be used", null)
                    }
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                answer { result.error(errorCodeFor(errorCode), errString.toString(), null) }
            }

            // A finger that didn't match: the prompt stays open for another try.
            override fun onAuthenticationFailed() {}
        }

        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setNegativeButtonText(negative)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        try {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) {
            DiogelLog.w(TAG, "could not show the biometric prompt", e)
            answer { result.error("failed", "could not show the biometric prompt", null) }
        }
    }

    private fun createKey(alias: String): SecretKey {
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Every use needs a fresh strong biometric; the screen-lock PIN doesn't count.
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            .apply { init(builder.build()) }
            .generateKey()
    }

    /** Deletes every biometric key: turning it off, or a wipe. Throws if any is left. */
    fun deleteKeys() {
        val left = deleteKeysExcept(null)
        if (left.isNotEmpty()) throw IllegalStateException("${left.size} biometric key(s) left")
    }

    private fun deleteKeysExcept(keep: String?): List<String> {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return deleteBiometricAliases(keyStore.aliases().toList(), keep) { keyStore.deleteEntry(it) }
    }

    private fun deleteOldKeysQuietly(keep: String) {
        try {
            val left = deleteKeysExcept(keep)
            if (left.isNotEmpty()) DiogelLog.w(TAG, "could not delete ${left.size} old biometric key(s)")
        } catch (e: Exception) {
            DiogelLog.w(TAG, "could not delete the old biometric keys", e)
        }
    }

    private fun deleteKeyQuietly(alias: String) {
        try {
            KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(alias)
        } catch (e: Exception) {
            DiogelLog.w(TAG, "could not delete an unused biometric key", e)
        }
    }
}
