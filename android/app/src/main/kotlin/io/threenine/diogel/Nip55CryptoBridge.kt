package io.threenine.diogel

import android.util.Log

/**
 * In-memory bridge that holds the active identity's private key
 * while the vault is unlocked.
 *
 * Flutter writes the key here via MethodChannel when the vault unlocks,
 * and clears it when the vault locks. The ContentProvider reads from here
 * to perform crypto operations without going through Flutter.
 *
 * Security:
 * - The key lives in process memory only while the vault is unlocked.
 * - It is NEVER written to persistent storage (SharedPreferences, files, etc.).
 * - When the vault locks, [clearActiveKey] zeroes the string reference.
 * - The ContentProvider checks [hasActiveKey] before attempting crypto.
 */
object Nip55CryptoBridge {
    private const val TAG = "Diogel-CryptoBridge"

    @Volatile
    private var _activePrivateKey: String? = null

    @Volatile
    private var _activePublicKey: String? = null

    @Volatile
    private var _activeLocalId: String? = null

    val activePrivateKey: String? get() = _activePrivateKey
    val activePublicKey: String? get() = _activePublicKey
    val activeLocalId: String? get() = _activeLocalId
    val hasActiveKey: Boolean get() = _activePrivateKey != null && _activePublicKey != null

    /**
     * Set the active identity's keys. Called from Flutter via MethodChannel
     * when the vault is unlocked.
     */
    fun setActiveKey(privateKey: String, publicKey: String, localId: String) {
        _activePrivateKey = privateKey
        _activePublicKey = publicKey
        _activeLocalId = localId
        Log.d(TAG, "Active key set: pubkey=${publicKey.take(8)}...")
    }

    /**
     * Clear the active keys. Called from Flutter when the vault locks
     * or the app goes to background with auto-lock.
     */
    /**
     * Clear the active keys. Called from Flutter when the vault locks
     * or the app goes to background with auto-lock.
     *
     * Note: JVM [String] objects are immutable — the underlying char array cannot
     * be explicitly zeroed. Nulling the reference makes the String eligible for GC,
     * but key material may linger in memory until the collector runs. A future
     * improvement is to store the private key as [CharArray] or [ByteArray] so it
     * can be zeroed before release; that change requires updating all callers in
     * [Nip55NativeCrypto] as well.
     */
    fun clearActiveKey() {
        _activePrivateKey = null
        _activePublicKey = null
        _activeLocalId = null
        Log.d(TAG, "Active key cleared")
    }
}