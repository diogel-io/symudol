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
 * - NIP-44 v2: ECDH (secp256k1) → HKDF-Extract("nip44-v2") → HKDF-Expand → ChaCha20 + HMAC-SHA256
 * - Schnorr signing: BIP-340 Schnorr signature (tagged hashes)
 *
 * Security note: Private keys are held in [Nip55CryptoBridge] (in-process memory only)
 * and are NEVER written to persistent storage by this class.
 * NO sensitive crypto material (shared secrets, private keys, IVs) is ever logged.
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
        val parts = ciphertext.split("?iv=", limit = 2)
        if (parts.size != 2) throw IllegalArgumentException("Malformed NIP-04 ciphertext: missing ?iv=")
        val encrypted = android.util.Base64.decode(parts[0], android.util.Base64.NO_WRAP)
        val iv = android.util.Base64.decode(parts[1], android.util.Base64.NO_WRAP)
        if (iv.size != 16) throw IllegalArgumentException("Malformed NIP-04 IV")
        val decrypted = aes256CbcDecrypt(sharedX, iv, encrypted)
        return String(decrypted, Charsets.UTF_8)
    }

    // ── Schnorr signing (BIP-340) ─────────────────────────────────────────

    /**
     * Sign an event. Enforces that the event's pubkey matches the active identity
     * to prevent signing events with a mismatched pubkey (which would produce
     * an invalid event: ID for one pubkey, signature from another key).
     *
     * @param privateKeyHex The active identity's private key
     * @param eventJson The event JSON (must have pubkey matching the private key)
     * @param activeIdentityPubkey The expected active identity pubkey (hex, 64 chars)
     * @return SignEventResult or null if pubkey mismatch / error
     */
    data class SignEventResult(val signature: String, val eventJson: String)

    fun signEvent(privateKeyHex: String, eventJson: String, activeIdentityPubkey: String): SignEventResult? {
        return try {
            val event = JSONObject(eventJson)
            val eventPubkey = event.optString("pubkey", "")

            // Fix #4: Enforce that the event pubkey matches the active identity.
            // This prevents signing events where the ID was computed for a different pubkey.
            if (eventPubkey != activeIdentityPubkey) {
                Log.w(TAG, "signEvent: pubkey mismatch — event has $eventPubkey but active identity is $activeIdentityPubkey")
                return null
            }

            val createdAt = event.optLong("created_at", 0L)
            val kind = event.optInt("kind", 0)
            val tags = event.optJSONArray("tags") ?: org.json.JSONArray()
            val content = event.optString("content", "")

            val serialized = serializeEvent(eventPubkey, createdAt, kind, tags, content)
            val id = sha256Hex(serialized.toByteArray(Charsets.UTF_8))

            val sig = schnorrSign(privateKeyHex, id)

            val signedEvent = JSONObject(eventJson)
            signedEvent.put("id", id)
            signedEvent.put("sig", sig)

            SignEventResult(sig, signedEvent.toString())
        } catch (e: Exception) {
            Log.e(TAG, "signEvent failed", e)
            null
        }
    }

    fun signMessage(privateKeyHex: String, message: String): String {
        val messageHash = sha256Hex(message.toByteArray(Charsets.UTF_8))
        return schnorrSign(privateKeyHex, messageHash)
    }

    // ── Decrypt zap event (NIP-57) ────────────────────────────────────────

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

    // ── ECDH shared secret ───────────────────────────────────────────────

    private fun ecdhSharedSecretX(privateKeyHex: String, peerPubkeyHex: String): ByteArray {
        val privateKey = hexToBytes(privateKeyHex)
        val peerPubkey = Secp256k1.pointFromHex(peerPubkeyHex)
            ?: throw IllegalArgumentException("Invalid peer pubkey")
        val sharedPoint = Secp256k1.multiply(peerPubkey, privateKey)
            ?: throw IllegalArgumentException("ECDH multiplication failed")
        return bigIntTo32Bytes(sharedPoint.x)
    }

    // ── NIP-44 v2 internals (matches nostr-tools / Dart implementation) ──

    private fun nip44ConversationKey(privateKeyHex: String, peerPubkeyHex: String): ByteArray {
        val sharedX = ecdhSharedSecretX(privateKeyHex, peerPubkeyHex)
        // conversation_key = HKDF-Extract(salt="nip44-v2", ikm=sharedX)
        return hkdfExtract("nip44-v2".toByteArray(Charsets.UTF_8), sharedX)
    }

    private fun hkdfExtract(salt: ByteArray, ikm: ByteArray): ByteArray {
        return hmacSha256(salt, ikm)
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
        if (raw.size < 99 || raw.size > 65603) throw IllegalArgumentException("Invalid NIP-44 payload size")

        val version = raw[0]
        if (version.toInt() != 2) throw IllegalArgumentException("Unsupported NIP-44 version: $version")

        val nonce = raw.copyOfRange(1, 33)
        val ciphertext = raw.copyOfRange(33, raw.size - 32)
        val mac = raw.copyOfRange(raw.size - 32, raw.size)

        val messageKeys = nip44MessageKeys(conversationKey, nonce)

        val expectedMac = hmacSha256(messageKeys.hmacKey, nonce + ciphertext)
        if (!constantTimeEquals(mac, expectedMac)) {
            throw IllegalArgumentException("NIP-44 HMAC verification failed")
        }

        val decrypted = chacha20Decrypt(messageKeys.chachaKey, messageKeys.chachaNonce, ciphertext)
        return nip44Unpad(decrypted)
    }

    private data class MessageKeys(val chachaKey: ByteArray, val chachaNonce: ByteArray, val hmacKey: ByteArray)

    private fun nip44MessageKeys(conversationKey: ByteArray, nonce: ByteArray): MessageKeys {
        // message_keys = HKDF-Expand(conversationKey, info=nonce, len=76)
        val expanded = hkdfExpand(conversationKey, nonce, 76)
        return MessageKeys(
            chachaKey = expanded.copyOfRange(0, 32),
            chachaNonce = expanded.copyOfRange(32, 44),
            hmacKey = expanded.copyOfRange(44, 76),
        )
    }

    // ── NIP-44 v2 padding (matches nostr-tools spec) ─────────────────────

    private fun nip44Pad(plaintext: String): ByteArray {
        val messageBytes = plaintext.toByteArray(Charsets.UTF_8)
        val len = messageBytes.size
        if (len < 1 || len > 65535) throw IllegalArgumentException("Invalid NIP-44 plaintext length: $len")
        val paddedLen = nip44PaddedLength(len)
        // [2-byte big-endian length] [zeros] [message]
        val padded = ByteArray(2 + paddedLen)
        padded[0] = (len shr 8).toByte()
        padded[1] = len.toByte()
        System.arraycopy(messageBytes, 0, padded, 2, len)
        return padded
    }

    private fun nip44PaddedLength(unpaddedLen: Int): Int {
        if (unpaddedLen <= 32) return 32
        val nextPower = 1 shl (32 - Integer.numberOfLeadingZeros(unpaddedLen - 1))
        val chunk = if (nextPower <= 256) 32 else nextPower / 8
        return chunk * (((unpaddedLen - 1) / chunk) + 1)
    }

    private fun nip44Unpad(data: ByteArray): String {
        if (data.size < 34) throw IllegalArgumentException("Invalid NIP-44 padding")
        val len = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
        if (len < 1 || len > 65535) throw IllegalArgumentException("Invalid NIP-44 message length: $len")
        if (data.size != 2 + nip44PaddedLength(len)) throw IllegalArgumentException("Invalid NIP-44 padding length")
        return String(data, 2, len, Charsets.UTF_8)
    }

    // ── ChaCha20 (plain, NOT ChaCha20-Poly1305) ──────────────────────────
    // NIP-44 v2 uses plain ChaCha20 for encryption and a separate HMAC-SHA256
    // for authentication. Android's "ChaCha20" cipher (API 28+) is plain
    // ChaCha20 with a 12-byte nonce.

    private fun chacha20Encrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
        // Android's Conscrypt ChaCha20 provider accepts IvParameterSpec with a
        // 12-byte nonce. ChaCha20ParameterSpec (API 35) is for the reference
        // provider only — Conscrypt is the default on Android and uses IvParameterSpec.
        return try {
            val cipher = Cipher.getInstance("ChaCha20/None/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce))
            cipher.doFinal(plaintext)
        } catch (e: Exception) {
            throw UnsupportedOperationException("ChaCha20 not available on this device", e)
        }
    }

    private fun chacha20Decrypt(key: ByteArray, nonce: ByteArray, ciphertext: ByteArray): ByteArray {
        return try {
            val cipher = Cipher.getInstance("ChaCha20/None/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce))
            cipher.doFinal(ciphertext)
        } catch (e: Exception) {
            throw UnsupportedOperationException("ChaCha20 not available on this device", e)
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

    // ── Schnorr signing (BIP-340 with tagged hashes) ──────────────────────

    private fun schnorrSign(privateKeyHex: String, messageHashHex: String): String {
        val d = BigInteger(1, hexToBytes(privateKeyHex))
        val msgHash = hexToBytes(messageHashHex)

        // BIP-340: P = d·G, determine if we need to negate d
        val P = Secp256k1.multiply(Secp256k1.G, d)
            ?: throw IllegalArgumentException("Invalid private key")
        val px = P.x

        // If P.y is odd, negate the secret key: d = n - d
        val dFinal = if (P.y.mod(Secp256k1.TWO) != BigInteger.ZERO) {
            Secp256k1.n.subtract(d)
        } else {
            d
        }

        // Fix #5: BIP-340 tagged nonce hash
        // t = tagged_hash("BIP340/aux", aux) — we use random aux as per BIP-340
        val aux = ByteArray(32).also { secureRandom.nextBytes(it) }
        val t = taggedHash("BIP0340/aux", aux)
        // XOR d' with t (both 32 bytes)
        val dPrime = bigIntTo32Bytes(dFinal)
        val xored = ByteArray(32)
        for (i in 0 until 32) xored[i] = (dPrime[i].toInt() xor t[i].toInt()).toByte()

        // rand = tagged_hash("BIP340/nonce", xored || P.x || m)
        val randInput = xored + bigIntTo32Bytes(px) + msgHash
        val rand = taggedHash("BIP0340/nonce", randInput)

        // k = rand mod n, fail if k is zero
        val k = BigInteger(1, rand).mod(Secp256k1.n)
        if (k == BigInteger.ZERO) throw IllegalArgumentException("Schnorr nonce is zero")

        // R = k·G
        val R = Secp256k1.multiply(Secp256k1.G, k)
            ?: throw IllegalArgumentException("Schnorr nonce point is invalid")

        // If R.y is odd, negate k
        val kFinal = if (R.y.mod(Secp256k1.TWO) != BigInteger.ZERO) {
            Secp256k1.n.subtract(k)
        } else {
            k
        }

        // e = tagged_hash("BIP340/challenge", R.x || P.x || m) mod n
        val challengeInput = bigIntTo32Bytes(R.x) + bigIntTo32Bytes(px) + msgHash
        val e = BigInteger(1, taggedHash("BIP0340/challenge", challengeInput)).mod(Secp256k1.n)

        // sig = (k_final + e * d') mod n
        val sig = kFinal.add(e.multiply(dFinal)).mod(Secp256k1.n)

        // Signature is R.x (32 bytes) || sig (32 bytes)
        return bytesToHex(bigIntTo32Bytes(R.x) + bigIntTo32Bytes(sig))
    }

    // ── Crypto utilities ─────────────────────────────────────────────────

    private fun sha256(data: ByteArray): ByteArray {
        return MessageDigest.getInstance("SHA-256").digest(data)
    }

    private fun sha256Hex(data: ByteArray): String {
        return bytesToHex(sha256(data))
    }

    /**
     * BIP-340 tagged hash: SHA256(SHA256(tag) || SHA256(tag) || message)
     */
    private fun taggedHash(tag: String, message: ByteArray): ByteArray {
        val tagHash = sha256(tag.toByteArray(Charsets.UTF_8))
        return sha256(tagHash + tagHash + message)
    }

    private fun hmacSha256(key: ByteArray, message: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(message)
    }

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
        return diff == 0
    }

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

    private fun hexToBytes(hex: String): ByteArray {
        val len = hex.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(hex[i], 16) shl 4) + Character.digit(hex[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun bigIntTo32Bytes(n: BigInteger): ByteArray {
        val raw = n.toByteArray()
        if (raw.size == 32) return raw
        if (raw.size > 32) return raw.copyOfRange(raw.size - 32, raw.size)
        return ByteArray(32 - raw.size) + raw
    }
}

/**
 * Minimal secp256k1 curve operations for ECDH and Schnorr signing.
 *
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
    val TWO = BigInteger.valueOf(2)
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
            .multiply(TWO.multiply(a.y).modInverse(p))
            .mod(p)
        val x3 = slope.multiply(slope).subtract(a.x).subtract(a.x).mod(p)
        val y3 = slope.multiply(a.x.subtract(x3)).subtract(a.y).mod(p)
        return ECPoint(x3, y3)
    }

    fun pointFromHex(hex: String): ECPoint? {
        if (hex.length != 64) return null
        val x = BigInteger(hex, 16)
        val ySquared = x.modPow(BigInteger.valueOf(3), p).add(BigInteger.valueOf(7)).mod(p)
        val y = ySquared.modPow(p.add(BigInteger.ONE).divide(BigInteger.valueOf(4)), p)
        if (y.modPow(BigInteger.valueOf(2), p) != ySquared) return null
        val evenY = if (y.mod(TWO) == BigInteger.ZERO) y else p.subtract(y)
        return ECPoint(x, evenY)
    }

    /** Self-test: verify multiply(G, 1) == G and multiply(G, 2) == 2G */
    fun selfTest(): Boolean {
        val g1 = multiply(G, BigInteger.ONE)
        if (g1 != G) {
            android.util.Log.e("Diogel-Secp256k1", "selfTest FAIL: 1*G != G")
            return false
        }
        val g2 = multiply(G, BigInteger.valueOf(2))
        val expected2Gx = BigInteger("C6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5", 16)
        if (g2?.x != expected2Gx) {
            android.util.Log.e("Diogel-Secp256k1", "selfTest FAIL: 2*G x mismatch")
            return false
        }
        android.util.Log.d("Diogel-Secp256k1", "selfTest PASS: secp256k1 point arithmetic is correct")
        return true
    }
}

private operator fun ByteArray.plus(other: ByteArray): ByteArray {
    return this.copyOf(this.size + other.size).also { System.arraycopy(other, 0, it, this.size, other.size) }
}