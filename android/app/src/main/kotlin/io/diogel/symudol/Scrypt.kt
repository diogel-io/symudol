package io.diogel.symudol

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * scrypt (RFC 7914) for the vault backup's NIP-49 keys (#25).
 *
 * Dart's pure scrypt takes 12–14 s at NIP-49's `log_n` 16 on a low-end phone; this runs the same
 * function on the JVM, off the main thread. The Dart side falls back to its own implementation
 * where this channel is missing, so tests and other platforms still work.
 */
object Scrypt {
    const val CHANNEL = "io.diogel.symudol/scrypt"
    private const val TAG = "Scrypt"

    /** The largest cost accepted, so a hostile backup can't ask for gigabytes (`log_n` 20). */
    private const val MAX_N = 1 shl 20

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Handles `derive` on [CHANNEL]: password, salt, n, r, p and dkLen in, the key out. */
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "derive") return result.notImplemented()
        val password = call.argument<ByteArray>("password")
        val salt = call.argument<ByteArray>("salt")
        val n = call.argument<Int>("n")
        val r = call.argument<Int>("r")
        val p = call.argument<Int>("p")
        val dkLen = call.argument<Int>("dkLen")
        if (password == null || salt == null || n == null || r == null || p == null || dkLen == null) {
            return result.error("INVALID_ARGS", "password, salt, n, r, p and dkLen required", null)
        }
        executor.execute {
            try {
                val started = System.nanoTime()
                val key = derive(password, salt, n, r, p, dkLen)
                DiogelLog.d(TAG) { "derive n=$n took ${(System.nanoTime() - started) / 1_000_000} ms" }
                mainHandler.post { result.success(key) }
            } catch (e: IllegalArgumentException) {
                mainHandler.post { result.error("INVALID_ARGS", e.message, null) }
            } catch (e: OutOfMemoryError) {
                mainHandler.post { result.error("OUT_OF_MEMORY", "scrypt needs more memory", null) }
            } finally {
                password.fill(0)
            }
        }
    }

    /** scrypt([password], [salt], [n], [r], [p]) as [dkLen] bytes. */
    fun derive(password: ByteArray, salt: ByteArray, n: Int, r: Int, p: Int, dkLen: Int): ByteArray {
        require(n > 1 && n and (n - 1) == 0 && n <= MAX_N) { "n must be a power of two up to $MAX_N" }
        require(r in 1..32 && p in 1..16 && dkLen in 1..1024) { "r, p or dkLen out of range" }
        val blockBytes = 128 * r
        val b = pbkdf2Sha256(password, salt, p * blockBytes)
        val x = IntArray(32 * r)
        val v = IntArray(32 * r * n)
        val buffers = Buffers(r)
        for (i in 0 until p) {
            romix(b, i * blockBytes, r, n, x, v, buffers)
        }
        val key = pbkdf2Sha256(password, b, dkLen)
        b.fill(0)
        x.fill(0)
        v.fill(0)
        return key
    }

    /** Working space reused by every BlockMix and Salsa20/8, so a derivation allocates once. */
    private class Buffers(r: Int) {
        val y = IntArray(32 * r)
        val t = IntArray(16)
        val salsa = IntArray(16)
    }

    /** RFC 7914 §5: scryptROMix on the block of [b] at [offset], in place. */
    private fun romix(b: ByteArray, offset: Int, r: Int, n: Int, x: IntArray, v: IntArray, buffers: Buffers) {
        val words = 32 * r
        for (k in 0 until words) {
            val o = offset + k * 4
            x[k] = (b[o].toInt() and 0xff) or
                ((b[o + 1].toInt() and 0xff) shl 8) or
                ((b[o + 2].toInt() and 0xff) shl 16) or
                ((b[o + 3].toInt() and 0xff) shl 24)
        }
        for (i in 0 until n) {
            System.arraycopy(x, 0, v, i * words, words)
            blockMix(x, buffers, r)
        }
        for (i in 0 until n) {
            // Integerify: the first word of the last 64-byte block, mod n.
            val j = x[(2 * r - 1) * 16] and (n - 1)
            val base = j * words
            for (k in 0 until words) x[k] = x[k] xor v[base + k]
            blockMix(x, buffers, r)
        }
        for (k in 0 until words) {
            val o = offset + k * 4
            b[o] = x[k].toByte()
            b[o + 1] = (x[k] ushr 8).toByte()
            b[o + 2] = (x[k] ushr 16).toByte()
            b[o + 3] = (x[k] ushr 24).toByte()
        }
    }

    /** RFC 7914 §4: scryptBlockMix with Salsa20/8, in place on [b]. */
    private fun blockMix(b: IntArray, buffers: Buffers, r: Int) {
        val t = buffers.t
        val y = buffers.y
        System.arraycopy(b, (2 * r - 1) * 16, t, 0, 16)
        for (i in 0 until 2 * r) {
            for (k in 0 until 16) t[k] = t[k] xor b[i * 16 + k]
            salsa208(t, buffers.salsa)
            // Even blocks go to the first half, odd ones to the second.
            val target = if (i % 2 == 0) (i / 2) * 16 else (r + i / 2) * 16
            System.arraycopy(t, 0, y, target, 16)
        }
        System.arraycopy(y, 0, b, 0, 32 * r)
    }

    /** RFC 7914 §3: the Salsa20/8 core, in place on [b], using [x] as working space. */
    private fun salsa208(b: IntArray, x: IntArray) {
        System.arraycopy(b, 0, x, 0, 16)
        for (round in 0 until 4) {
            x[4] = x[4] xor Integer.rotateLeft(x[0] + x[12], 7)
            x[8] = x[8] xor Integer.rotateLeft(x[4] + x[0], 9)
            x[12] = x[12] xor Integer.rotateLeft(x[8] + x[4], 13)
            x[0] = x[0] xor Integer.rotateLeft(x[12] + x[8], 18)
            x[9] = x[9] xor Integer.rotateLeft(x[5] + x[1], 7)
            x[13] = x[13] xor Integer.rotateLeft(x[9] + x[5], 9)
            x[1] = x[1] xor Integer.rotateLeft(x[13] + x[9], 13)
            x[5] = x[5] xor Integer.rotateLeft(x[1] + x[13], 18)
            x[14] = x[14] xor Integer.rotateLeft(x[10] + x[6], 7)
            x[2] = x[2] xor Integer.rotateLeft(x[14] + x[10], 9)
            x[6] = x[6] xor Integer.rotateLeft(x[2] + x[14], 13)
            x[10] = x[10] xor Integer.rotateLeft(x[6] + x[2], 18)
            x[3] = x[3] xor Integer.rotateLeft(x[15] + x[11], 7)
            x[7] = x[7] xor Integer.rotateLeft(x[3] + x[15], 9)
            x[11] = x[11] xor Integer.rotateLeft(x[7] + x[3], 13)
            x[15] = x[15] xor Integer.rotateLeft(x[11] + x[7], 18)
            x[1] = x[1] xor Integer.rotateLeft(x[0] + x[3], 7)
            x[2] = x[2] xor Integer.rotateLeft(x[1] + x[0], 9)
            x[3] = x[3] xor Integer.rotateLeft(x[2] + x[1], 13)
            x[0] = x[0] xor Integer.rotateLeft(x[3] + x[2], 18)
            x[6] = x[6] xor Integer.rotateLeft(x[5] + x[4], 7)
            x[7] = x[7] xor Integer.rotateLeft(x[6] + x[5], 9)
            x[4] = x[4] xor Integer.rotateLeft(x[7] + x[6], 13)
            x[5] = x[5] xor Integer.rotateLeft(x[4] + x[7], 18)
            x[11] = x[11] xor Integer.rotateLeft(x[10] + x[9], 7)
            x[8] = x[8] xor Integer.rotateLeft(x[11] + x[10], 9)
            x[9] = x[9] xor Integer.rotateLeft(x[8] + x[11], 13)
            x[10] = x[10] xor Integer.rotateLeft(x[9] + x[8], 18)
            x[12] = x[12] xor Integer.rotateLeft(x[15] + x[14], 7)
            x[13] = x[13] xor Integer.rotateLeft(x[12] + x[15], 9)
            x[14] = x[14] xor Integer.rotateLeft(x[13] + x[12], 13)
            x[15] = x[15] xor Integer.rotateLeft(x[14] + x[13], 18)
        }
        for (k in 0 until 16) b[k] += x[k]
    }

    /** PBKDF2-HMAC-SHA256 with one iteration, as scrypt uses it, on raw password bytes. */
    private fun pbkdf2Sha256(password: ByteArray, salt: ByteArray, length: Int): ByteArray {
        // An empty password is valid scrypt input, but SecretKeySpec refuses an empty key; HMAC
        // pads keys with zeros, so one zero byte is the same key.
        val mac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(if (password.isEmpty()) ByteArray(1) else password, "HmacSHA256"))
        }
        val out = ByteArray(length)
        var block = 1
        var written = 0
        while (written < length) {
            mac.update(salt)
            mac.update(byteArrayOf((block ushr 24).toByte(), (block ushr 16).toByte(), (block ushr 8).toByte(), block.toByte()))
            val u = mac.doFinal()
            val count = minOf(u.size, length - written)
            System.arraycopy(u, 0, out, written, count)
            written += count
            block++
        }
        return out
    }
}
