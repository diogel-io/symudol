package io.diogel.symudol

import android.os.Looper
import android.os.SystemClock
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Duration

/**
 * The native copy of the private key (#9): held as bytes that are zeroed when
 * cleared, and cleared at the lock deadline without the Flutter engine.
 */
@RunWith(RobolectricTestRunner::class)
class Nip55CryptoBridgeTest {
    private val pubKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    private fun key() = ByteArray(32) { (it + 1).toByte() }

    private var now = 1_000_000L

    @Before
    fun setUp() {
        Nip55CryptoBridge.clock = { now }
    }

    @After
    fun tearDown() {
        Nip55CryptoBridge.clearActiveKey()
        Nip55CryptoBridge.clock = { SystemClock.elapsedRealtime() }
    }

    /** The array the bridge holds, captured for inspection only. */
    private fun heldKey(): ByteArray? = Nip55CryptoBridge.withActiveKey { it }

    @Test
    fun clearingZeroesTheKey() {
        Nip55CryptoBridge.setActiveKey(key(), pubKey, "local-1")
        val held = heldKey()!!

        Nip55CryptoBridge.clearActiveKey()

        assertTrue("every byte is zero", held.all { it == 0.toByte() })
        assertNull(heldKey())
        assertNull(Nip55CryptoBridge.activePublicKey)
        assertFalse(Nip55CryptoBridge.hasActiveKey)
    }

    @Test
    fun theKeyIsACopyOfTheCallersArray() {
        val callers = key()
        Nip55CryptoBridge.setActiveKey(callers, pubKey, "local-1")

        callers.fill(0)

        assertArrayEquals(key(), heldKey())
    }

    @Test
    fun settingANewKeyZeroesTheOldOne() {
        Nip55CryptoBridge.setActiveKey(key(), pubKey, "local-1")
        val old = heldKey()!!

        Nip55CryptoBridge.setActiveKey(ByteArray(32) { 9 }, pubKey, "local-2")

        assertTrue(old.all { it == 0.toByte() })
    }

    @Test
    fun theKeyIsUsableUntilTheDeadline() {
        Nip55CryptoBridge.setActiveKey(key(), pubKey, "local-1")
        Nip55CryptoBridge.setLockDeadline(60_000)

        now += 59_999
        assertNotNull(heldKey())

        now += 1
        assertNull("past the deadline", heldKey())
        assertNull(Nip55CryptoBridge.activePublicKey)
    }

    @Test
    fun theTimerClearsTheKeyAtTheDeadline() {
        Nip55CryptoBridge.setActiveKey(key(), pubKey, "local-1")
        val held = heldKey()!!
        Nip55CryptoBridge.setLockDeadline(60_000)

        now += 60_000
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(60_000))

        assertTrue("zeroed by the timer, before any read", held.all { it == 0.toByte() })
    }

    @Test
    fun clearingTheDeadlineKeepsTheKey() {
        Nip55CryptoBridge.setActiveKey(key(), pubKey, "local-1")
        Nip55CryptoBridge.setLockDeadline(60_000)

        Nip55CryptoBridge.clearLockDeadline()
        now += 120_000
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(120_000))

        assertArrayEquals(key(), heldKey())
    }

    @Test(expected = IllegalArgumentException::class)
    fun onlyA32ByteKeyIsAccepted() {
        Nip55CryptoBridge.setActiveKey(ByteArray(31), pubKey, "local-1")
    }
}
