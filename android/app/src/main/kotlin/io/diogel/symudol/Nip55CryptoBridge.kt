package io.diogel.symudol

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log

/**
 * In-memory bridge that holds the active identity's private key
 * while the vault is unlocked.
 *
 * Flutter writes the key here via MethodChannel when the vault unlocks,
 * and clears it when the vault locks. The ContentProvider reads from here
 * to perform crypto operations without going through Flutter.
 *
 * Security (diogel-io/symudol#9):
 * - The key lives in process memory only while the vault is unlocked.
 * - It is NEVER written to persistent storage (SharedPreferences, files, etc.).
 * - It is held as raw bytes, which [clearActiveKey] zeroes, never as a String.
 * - It is cleared when the vault locks, when MainActivity is destroyed, and at
 *   the lock deadline set while the app is in the background. The deadline is
 *   kept here, so it holds without the Flutter engine: a timer clears the key,
 *   and every read checks the deadline in case the timer has not run.
 * - The key is only used inside [withActiveKey], so it can't be cleared mid-use.
 */
object Nip55CryptoBridge {
    private const val TAG = "Diogel-CryptoBridge"

    /** Monotonic time for the lock deadline, in milliseconds. Tests replace it. */
    @Volatile
    var clock: () -> Long = { SystemClock.elapsedRealtime() }

    private val lock = Any()
    private var privateKey: ByteArray? = null
    private var publicKey: String? = null
    private var localId: String? = null
    private var lockAtMs: Long? = null

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val expireTask = Runnable { expireIfDue() }

    val activePublicKey: String? get() = synchronized(lock) { if (isLiveLocked()) publicKey else null }
    val activeLocalId: String? get() = synchronized(lock) { if (isLiveLocked()) localId else null }
    val hasActiveKey: Boolean get() = synchronized(lock) { isLiveLocked() }

    /**
     * Set the active identity's keys. Called from Flutter via MethodChannel
     * when the vault is unlocked. [privateKey] is copied: the caller should
     * zero its own array.
     */
    fun setActiveKey(privateKey: ByteArray, publicKey: String, localId: String) {
        require(privateKey.size == 32) { "privateKey must be 32 bytes" }
        synchronized(lock) {
            clearLocked()
            this.privateKey = privateKey.copyOf()
            this.publicKey = publicKey
            this.localId = localId
        }
        Log.d(TAG, "Active key set: pubkey=${publicKey.take(8)}...")
    }

    /**
     * Runs [block] with the active private key, or returns null when there is
     * none: locked, cleared, or past the lock deadline. [block] must not keep
     * the array.
     */
    fun <T> withActiveKey(block: (ByteArray) -> T?): T? = synchronized(lock) {
        if (!isLiveLocked()) return null
        block(privateKey!!)
    }

    /**
     * Clear the key at [delayMs] from now unless [clearLockDeadline] is called
     * first. Set by Flutter when the app goes to the background.
     */
    fun setLockDeadline(delayMs: Long) {
        synchronized(lock) { lockAtMs = clock() + delayMs.coerceAtLeast(0) }
        try {
            mainHandler.removeCallbacks(expireTask)
            mainHandler.postDelayed(expireTask, delayMs.coerceAtLeast(0))
        } catch (e: RuntimeException) {
            // No main looper (plain JVM tests): the deadline check on read still applies.
            Log.w(TAG, "setLockDeadline: no timer, the deadline is checked on read")
        }
        Log.d(TAG, "Lock deadline set: ${delayMs}ms")
    }

    /** The app is back in the foreground: no deadline. */
    fun clearLockDeadline() {
        synchronized(lock) { lockAtMs = null }
        try {
            mainHandler.removeCallbacks(expireTask)
        } catch (_: RuntimeException) {
        }
    }

    /**
     * Zero and drop the active keys. Called when the vault locks, when
     * MainActivity is destroyed, and at the lock deadline.
     */
    fun clearActiveKey() {
        synchronized(lock) { clearLocked() }
        Log.d(TAG, "Active key cleared")
    }

    private fun expireIfDue() {
        synchronized(lock) { isLiveLocked() }
    }

    /** Whether there is a usable key; clears it once the deadline has passed. */
    private fun isLiveLocked(): Boolean {
        val deadline = lockAtMs
        if (deadline != null && clock() >= deadline) {
            Log.d(TAG, "Lock deadline passed: clearing the active key")
            clearLocked()
            return false
        }
        return privateKey != null && publicKey != null
    }

    private fun clearLocked() {
        privateKey?.fill(0)
        privateKey = null
        publicKey = null
        localId = null
        lockAtMs = null
    }
}
