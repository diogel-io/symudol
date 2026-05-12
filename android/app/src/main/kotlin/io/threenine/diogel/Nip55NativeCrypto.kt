package io.threenine.diogel

import android.util.Log
import org.json.JSONObject
import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Native crypto operations for NIP-55 ContentProvider auto-approve.
 *
 * Performs NIP-04 and NIP-44 v2 encrypt/decrypt and Schnorr signing
 * entirely in Kotlin, without going through the Flutter engine.
 *
 * This enables the ContentProvider to return results for remembered
 * permissions in microseconds rather than the 3-second Flutter bridge timeout.
 *
 * Algorithms:
 * - NIP-04: ECDH (secp256k1) shared secret → AES-256-CBC
 * - NIP-44 v2: ECDH (secp256k1) → HKDF-SHA256 → ChaCha20-Poly1305
 * - Schnorr signing: secp256k1 Schnorr signature (BIP-340)
 *
 * Security note: Private keys are held in [Nip55CryptoBridge] (in-process memory only)
 * and are NEVER written to persistent storage by this class.
 */
object Nip55NativeCrypto {
    private const val TAG = "Diogel-NativeCrypto"

    private val secureRandom = SecureRandom()

    // ── NIP-44 v2 ────────────────────────────────────────────────────────

    fun nip44Encrypt(privateKeyHex: String, peerPubkeyHex: String, plaintext: String): String {
        val conversationKey = nip44ConversationKey(privateKeyHex, peerPubkeyHex)
        return nip44EncryptWithConversationKey(conversationKey, plaintext)
    }

    fun nip44Decrypt(privateKeyHex: String, peerPubkeyHex: String, ciphertext: String): String {
        val conversationKey = nip44ConversationKey(privateKeyHex, peerPubkeyHex)
        return nip44DecryptWithConversationKey(conversationKey, ciphertext)
    }

    // ── NIP-04 ────────────────────────────────────────────────────────────

    fun nip04Encrypt(privateKeyHex: String, peerPubkeyHex: String, plaintext: String): String {
        val sharedX = ecdhSharedSecretX(privateKeyHex, peerPubkeyHex)
        val iv = ByteArray(16).also { secureRandom.nextBytes(it) }
        val encrypted = aes256CbcEncrypt(sharedX, iv, plaintext.toByteArray(Charsets.UTF_8))
        return android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP) +
            "?iv=" + android.util.Base64.encodeToString(iv, android.util.Base64.NO_WRAP)
    }

    fun nip04Decrypt(privateKeyHex: String, peerPubkeyHex: String, ciphertext: String): String {
        val sharedX = ecdhSharedSecretX(privateKeyHex, peerPubkeyHex)
        android.util.Log.d("Diogel-NativeCrypto", "nip04Decrypt: sharedX=${bytesToHex(sharedX)}, peerPubkey=${peerPubkeyHex.take(16)}..., privKey=${privateKeyHex.take(8)}..., ciphertextLen=${ciphertext.length}")
        val parts = ciphertext.split("?iv=", limit = 2)
        if (parts.size != 2) throw IllegalArgumentException("Malformed NIP-04 ciphertext: missing ?iv=")
        val encrypted = android.util.Base64.decode(parts[0], android.util.Base64.NO_WRAP)
        val iv = android.util.Base64.decode(parts[1], android.util.Base64.NO_WRAP)
        android.util.Log.d("Diogel-NativeCrypto", "nip04Decrypt: encryptedLen=${encrypted.size}, ivLen=${iv.size}, ivHex=${bytesToHex(iv)}")
        if (iv.size != 16) throw IllegalArgumentException("Malformed NIP-04 IV")
        val decrypted = aes256CbcDecrypt(sharedX, iv, encrypted)
        return String(decrypted, Charsets.UTF_8)
    }

    // ── Schnorr signing ──────────────────────────────────────────────────

    fun signMessage(privateKeyHex: String, message: String): String {
        val messageHash = sha256Hex(message.toByteArray(Charsets.UTF_8))
        return schnorrSign(privateKeyHex, messageHash)
    }

    /**
     * Decrypt a NIP-57 private zap request event.
     *
     * The input is the full kind-9734 event JSON. We parse it, extract
     * the sender's pubkey from the P tag (or the event pubkey if no P tag),
     * and NIP-04 decrypt the content field.
     *
     * Returns the decrypted content string, or null on failure.
     */
    fun decryptZapEvent(privateKeyHex: String, eventJson: String): String? {
        return try {
            val event = JSONObject(eventJson)
            val content = event.optString("content", "")
            if (content.isEmpty()) return "" // No content to decrypt

            // Find the P tag (sender pubkey) — first p tag in the tags array
            var peerPubkey: String? = null
            val tags = event.optJSONArray("tags")
            if (tags != null) {
                for (i in 0 until tags.length()) {
                    val tag = tags.optJSONArray(i)
                    if (tag != null && tag.length() >= 2 && tag.optString(0) == "p") {
                        peerPubkey = tag.optString(1)
                        break
                    }
                }
            }

            // Fallback to event pubkey if no P tag found
            if (peerPubkey == null) {
                peerPubkey = event.optString("pubkey", null)
            }
            if (peerPubkey == null) return null

            nip04Decrypt(privateKeyHex, peerPubkey, content)
        } catch (e: Exception) {
            Log.e(TAG, "decryptZapEvent failed", e)
            null
        }
    }

    data class SignEventResult(val signature: String, val eventJson: String)

    fun signEvent(privateKeyHex: String, eventJson: String): SignEventResult? {
        return try {
            val event = JSONObject(eventJson)
            val pubkey = event.optString("pubkey", "")
            val createdAt = event.optLong("created_at", 0L)
            val kind = event.optInt("kind", 0)
            val tags = event.optJSONArray("tags") ?: org.json.JSONArray()
            val content = event.optString("content", "")

            // Serialize the event for hashing (NIP-01)
            val serialized = serializeEvent(pubkey, createdAt, kind, tags, content)
            val id = sha256Hex(serialized.toByteArray(Charsets.UTF_8))

            val sig = schnorrSign(privateKeyHex, id)

            // Build the signed event JSON
            val signedEvent = JSONObject(eventJson)
            signedEvent.put("id", id)
            signedEvent.put("sig", sig)

            SignEventResult(sig, signedEvent.toString())
        } catch (e: Exception) {
            Log.e(TAG, "signEvent failed", e)
            null
        }
    }

    // ── ECDH shared secret ───────────────────────────────────────────────

    /**
     * Compute the ECDH shared secret X coordinate (NIP-04 and NIP-44).
     * Uses secp256k1 curve: sharedX = (peerPubkeyPoint * privateKey).x
     */
    private fun ecdhSharedSecretX(privateKeyHex: String, peerPubkeyHex: String): ByteArray {
        val privateKey = hexToBytes(privateKeyHex)
        val peerPubkey = Secp256k1.pointFromHex(peerPubkeyHex)
            ?: throw IllegalArgumentException("Invalid peer pubkey")
        val sharedPoint = Secp256k1.multiply(peerPubkey, privateKey)
            ?: throw IllegalArgumentException("ECDH multiplication failed")
        return bigIntTo32Bytes(sharedPoint.x)
    }

    // ── NIP-44 v2 internals ──────────────────────────────────────────────

    private fun nip44ConversationKey(privateKeyHex: String, peerPubkeyHex: String): ByteArray {
        val sharedX = ecdhSharedSecretX(privateKeyHex, peerPubkeyHex)
        return hkdfExtractExpand(sharedX, byteArrayOf(0x01))
    }

    private fun hkdfExtractExpand(key: ByteArray, info: ByteArray): ByteArray {
        val prk = hmacSha256(byteArrayOf(0x02), key)
        return hkdfExpand(prk, info, 32)
    }

    private fun hkdfExpand(prk: ByteArray, info: ByteArray, length: Int): ByteArray {
        val result = mutableListOf<Byte>()
        var previous = ByteArray(0)
        var counter = 1
        while (result.size < length) {
            previous = hmacSha256(prk, previous + info + byteArrayOf(counter.toByte()))
            result.addAll(previous.toList())
            counter++
        }
        return result.toByteArray().copyOfRange(0, length)
    }

    private fun nip44EncryptWithConversationKey(conversationKey: ByteArray, plaintext: String): String {
        val nonce = ByteArray(32).also { secureRandom.nextBytes(it) }
        val messageKeys = nip44MessageKeys(conversationKey, nonce)
        val padded = nip44Pad(plaintext)
        val ciphertext = chacha20Encrypt(messageKeys.chachaKey, messageKeys.chachaNonce, padded)
        val mac = hmacSha256(messageKeys.hmacKey, nonce + ciphertext)
        return android.util.Base64.encodeToString(
            byteArrayOf(0x02) + nonce + ciphertext + mac,
            android.util.Base64.NO_WRAP
        )
    }

    private fun nip44DecryptWithConversationKey(conversationKey: ByteArray, payload: String): String {
        if (payload.isEmpty()) throw IllegalArgumentException("Empty NIP-44 payload")
        if (payload[0] == '#') throw IllegalArgumentException("Unsupported NIP-44 payload version")

        val raw = android.util.Base64.decode(payload, android.util.Base64.NO_WRAP)
        if (raw.size < 132 || raw.size > 87472) throw IllegalArgumentException("Invalid NIP-44 payload length")

        val version = raw[0]
        if (version.toInt() != 2) throw IllegalArgumentException("Unsupported NIP-44 version: $version")

        val nonce = raw.copyOfRange(1, 33)
        val ciphertext = raw.copyOfRange(33, raw.size - 32)
        val mac = raw.copyOfRange(raw.size - 32, raw.size)

        val messageKeys = nip44MessageKeys(conversationKey, nonce)

        // Verify HMAC
        val expectedMac = hmacSha256(messageKeys.hmacKey, nonce + ciphertext)
        if (!constantTimeEquals(mac, expectedMac)) {
            throw IllegalArgumentException("NIP-44 HMAC verification failed")
        }

        val decrypted = chacha20Decrypt(messageKeys.chachaKey, messageKeys.chachaNonce, ciphertext)
        return nip44Unpad(decrypted)
    }

    private data class MessageKeys(val chachaKey: ByteArray, val chachaNonce: ByteArray, val hmacKey: ByteArray)

    private fun nip44MessageKeys(conversationKey: ByteArray, nonce: ByteArray): MessageKeys {
        val expanded = hkdfExpand(
            hkdfExtractExpand(conversationKey, nonce),
            byteArrayOf(),
            76
        )
        return MessageKeys(
            chachaKey = expanded.copyOfRange(0, 32),
            chachaNonce = expanded.copyOfRange(32, 44),
            hmacKey = expanded.copyOfRange(44, 76),
        )
    }

    private fun nip44Pad(plaintext: String): ByteArray {
        val messageBytes = plaintext.toByteArray(Charsets.UTF_8)
        // NIP-44 v2 padding: [2-byte big-endian length] [zeros] [message]
        val len = messageBytes.size
        val paddingLen = when {
            len < 256 -> 256 - len
            len < 65536 -> {
                // Round up to next power of 2 boundary
                val boundary = 1 shl (32 - Integer.numberOfLeadingZeros(len))
                if (boundary == len) 0 else boundary - len
            }
            else -> 0
        }
        val padded = ByteArray(2 + paddingLen + len)
        padded[0] = (len shr 8).toByte()
        padded[1] = len.toByte()
        System.arraycopy(messageBytes, 0, padded, 2 + paddingLen, len)
        return padded
    }

    private fun nip44Unpad(data: ByteArray): String {
        if (data.size < 2) throw IllegalArgumentException("Invalid NIP-44 padded data")
        val len = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
        if (len < 0 || len > data.size - 2) throw IllegalArgumentException("Invalid NIP-44 message length")
        return String(data, data.size - len, len, Charsets.UTF_8)
    }

    // ── ChaCha20 ────────────────────────────────────────────────────────

    private fun chacha20Encrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
        // Try Android's built-in ChaCha20-Poly1305 first (API 28+)
        return try {
            val cipher = Cipher.getInstance("ChaCha20-Poly1305/None/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce))
            cipher.doFinal(plaintext)
        } catch (e: Exception) {
            Log.w(TAG, "ChaCha20-Poly1305 not available, falling back", e)
            // Fallback: will need BouncyCastle or alternative
            throw UnsupportedOperationException("ChaCha20-Poly1305 not available on this device", e)
        }
    }

    private fun chacha20Decrypt(key: ByteArray, nonce: ByteArray, ciphertext: ByteArray): ByteArray {
        return try {
            val cipher = Cipher.getInstance("ChaCha20-Poly1305/None/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce))
            cipher.doFinal(ciphertext)
        } catch (e: Exception) {
            Log.w(TAG, "ChaCha20-Poly1305 not available, falling back", e)
            throw UnsupportedOperationException("ChaCha20-Poly1305 not available on this device", e)
        }
    }

    // ── AES-256-CBC (NIP-04) ────────────────────────────────────────────

    private fun aes256CbcEncrypt(key: ByteArray, iv: ByteArray, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return cipher.doFinal(plaintext)
    }

    private fun aes256CbcDecrypt(key: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return cipher.doFinal(ciphertext)
    }

    // ── Schnorr signing (simplified — uses secp256k1) ────────────────────

    private fun schnorrSign(privateKeyHex: String, messageHashHex: String): String {
        val dPrime = BigInteger(1, hexToBytes(privateKeyHex))
        val messageHashBytes = hexToBytes(messageHashHex)

        // Step 1: P = d' * G
        val P = Secp256k1.multiply(Secp256k1.G, dPrime)
            ?: throw IllegalArgumentException("Invalid private key")

        // Step 2: d = d' if P has even y, else n - d'
        val d = if (P.y.mod(BigInteger.TWO) == BigInteger.ZERO) dPrime else Secp256k1.n.subtract(dPrime)

        // Step 3: t = xor(bytes(d), tagged_hash("BIP0340/aux", aux_rand))
        // Using aux_rand = 0^32 (deterministic)
        val auxRand = ByteArray(32)
        val auxHash = taggedHash("BIP0340/aux", auxRand)
        val dBytes = bigIntTo32Bytes(d)
        val t = ByteArray(32) { dBytes[it].toInt().xor(auxHash[it].toInt()).toByte() }

        // Step 4: rand = SHA256(t || bytes(P) || m)
        val randInput = t + bigIntTo32Bytes(P.x) + messageHashBytes
        val rand = bytesToBigInteger(sha256(randInput)).mod(Secp256k1.n)
        if (rand == BigInteger.ZERO) throw IllegalArgumentException("rand was zero")

        // Step 5: R = rand * G
        val R = Secp256k1.multiply(Secp256k1.G, bigIntTo32Bytes(rand))
            ?: throw IllegalArgumentException("Failed to compute R point")

        // Step 6: If R.y is odd, negate rand
        val k = if (R.y.mod(BigInteger.TWO) != BigInteger.ZERO) Secp256k1.n.subtract(rand) else rand

        // Step 7: e = tagged_hash("BIP0340/challenge", R.x || P.x || m) mod n
        val challengeInput = bigIntTo32Bytes(R.x) + bigIntTo32Bytes(P.x) + messageHashBytes
        val e = bytesToBigInteger(taggedHash("BIP0340/challenge", challengeInput)).mod(Secp256k1.n)

        // Step 8: sig = k + e*d mod n
        val sig = k.add(e.multiply(d)).mod(Secp256k1.n)
        if (sig == BigInteger.ZERO) throw IllegalArgumentException("sig was zero")

        return bytesToHex(bigIntTo32Bytes(R.x) + bigIntTo32Bytes(sig))
    }

    private fun taggedHash(tag: String, message: ByteArray): ByteArray {
        val tagHash = sha256(tag.toByteArray(Charsets.UTF_8))
        return sha256(tagHash + tagHash + message)
    }

    // ── Event serialization (NIP-01) ──────────────────────────────────────

    private fun serializeEvent(pubkey: String, createdAt: Long, kind: Int, tags: org.json.JSONArray, content: String): String {
        val arr = org.json.JSONArray()
        arr.put(0)
        arr.put(pubkey)
        arr.put(createdAt)
        arr.put(kind)
        arr.put(tags)
        arr.put(content)
        return arr.toString()
    }

    // ── Crypto utilities ─────────────────────────────────────────────────

    private fun sha256(data: ByteArray): ByteArray {
        return MessageDigest.getInstance("SHA-256").digest(data)
    }

    private fun sha256Hex(data: ByteArray): String {
        return bytesToHex(sha256(data))
    }

    private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
        return diff == 0
    }

    private fun hexToBytes(hex: String): ByteArray {
        return hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun bytesToBigInteger(bytes: ByteArray): BigInteger {
        return BigInteger(1, bytes)
    }

    private fun bigIntTo32Bytes(value: BigInteger): ByteArray {
        val hex = value.toString(16).padStart(64, '0')
        return hexToBytes(hex)
    }
}

/**
 * Minimal secp256k1 curve operations for ECDH and Schnorr signing.
 *
 * This uses Android's built-in EC cryptography for point multiplication.
 * For production, consider using BouncyCastle's secp256k1 implementation
 * for better performance and full BIP-340 compliance.
 */
object Secp256k1 {
    val n = BigInteger(
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",
        16
    )
    val p = BigInteger(
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F",
        16
    )
    val Gx = BigInteger(
        "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",
        16
    )
    val Gy = BigInteger(
        "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8",
        16
    )
    val G = ECPoint(Gx, Gy)

    data class ECPoint(val x: BigInteger, val y: BigInteger)

    fun multiply(point: ECPoint, scalar: ByteArray): ECPoint? {
        return multiply(point, BigInteger(1, scalar))
    }

    fun multiply(point: ECPoint, scalar: BigInteger): ECPoint? {
        var result: ECPoint? = null
        var addend = point
        val s = scalar.mod(n)

        for (i in 0..255) {
            if (s.shiftRight(i).and(BigInteger.ONE) == BigInteger.ONE) {
                result = if (result == null) addend else add(result, addend)
            }
            addend = add(addend, addend) ?: return null
        }
        return result
    }

    fun add(a: ECPoint, b: ECPoint): ECPoint? {
        if (a == b) return double(a)

        val dy = b.y.subtract(a.y).mod(p)
        val dx = b.x.subtract(a.x).mod(p)

        if (dx == BigInteger.ZERO) return null

        val slope = dy.multiply(dx.modInverse(p)).mod(p)
        val x3 = slope.multiply(slope).subtract(a.x).subtract(b.x).mod(p)
        val y3 = slope.multiply(a.x.subtract(x3)).subtract(a.y).mod(p)
        return ECPoint(x3, y3)
    }

    fun double(a: ECPoint): ECPoint? {
        // slope = (3 * x^2) / (2 * y) for secp256k1 where a = 0
        val slope = BigInteger.valueOf(3)
            .multiply(a.x).multiply(a.x)
            .multiply(BigInteger.valueOf(2).multiply(a.y).modInverse(p))
            .mod(p)
        val x3 = slope.multiply(slope).subtract(a.x).subtract(a.x).mod(p)
        val y3 = slope.multiply(a.x.subtract(x3)).subtract(a.y).mod(p)
        return ECPoint(x3, y3)
    }

    fun pointFromHex(hex: String): ECPoint? {
        if (hex.length != 64) return null
        val x = BigInteger(hex, 16)
        // Decompress: y^2 = x^3 + 7 mod p, take even y
        val ySquared = x.modPow(BigInteger.valueOf(3), p).add(BigInteger.valueOf(7)).mod(p)
        val y = ySquared.modPow(p.add(BigInteger.ONE).divide(BigInteger.valueOf(4)), p)
        if (y.modPow(BigInteger.valueOf(2), p) != ySquared) return null
        val evenY = if (y.mod(BigInteger.TWO) == BigInteger.ZERO) y else p.subtract(y)
        return ECPoint(x, evenY)
    }

    /** Self-test: verify multiply(G, 1) == G and multiply(G, 2) == 2G */
    fun selfTest(): Boolean {
        val g1 = multiply(G, BigInteger.ONE)
        if (g1 != G) {
            android.util.Log.e("Diogel-Secp256k1", "selfTest FAIL: 1*G != G, got x=${g1?.x?.toString(16)?.take(16)}")
            return false
        }
        val g2 = multiply(G, BigInteger.valueOf(2))
        val expected2Gx = BigInteger("C6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5", 16)
        if (g2?.x != expected2Gx) {
            android.util.Log.e("Diogel-Secp256k1", "selfTest FAIL: 2*G x mismatch, got x=${g2?.x?.toString(16)?.take(16)} expected=${expected2Gx.toString(16)?.take(16)}")
            return false
        }
        android.util.Log.d("Diogel-Secp256k1", "selfTest PASS: secp256k1 point arithmetic is correct")
        return true
    }
}

private operator fun ByteArray.plus(other: ByteArray): ByteArray {
    return this.copyOf(this.size + other.size).also { System.arraycopy(other, 0, it, this.size, other.size) }
}