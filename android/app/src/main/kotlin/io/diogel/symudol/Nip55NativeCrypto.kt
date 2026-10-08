package io.diogel.symudol

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigInteger
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Native crypto operations for NIP-55 ContentProvider auto-approve.
 *
 * Performs NIP-04 and NIP-44 v2 encrypt/decrypt entirely in Kotlin, without going through the
 * Flutter engine, so the ContentProvider answers remembered permissions in microseconds rather
 * than waiting on the Flutter bridge.
 *
 * It never signs: sign_event and sign_message go to the Dart vault service, which verifies every
 * signature before returning it (diogel-io/symudol#12, documentation/nip55-native-crypto-decision.md).
 * The ContentProvider uses its ECDH operations only while [selfTestPassed].
 *
 * Algorithms:
 * - NIP-04: ECDH (secp256k1) shared secret → AES-256-CBC
 * - NIP-44 v2: ECDH (secp256k1) → HKDF-Extract("nip44-v2") → HKDF-Expand → ChaCha20 + HMAC-SHA256
 *
 * Security note: Private keys are held in [Nip55CryptoBridge] (in-process memory only)
 * and are NEVER written to persistent storage by this class.
 * NO sensitive crypto material (shared secrets, private keys, IVs) is ever logged.
 */
object Nip55NativeCrypto {
    private const val TAG = "Diogel-NativeCrypto"

    private val secureRandom = SecureRandom()

    // ── Self-test ────────────────────────────────────────────────────────

    /**
     * Whether the hand-written curve arithmetic and NIP-44 key derivation give known answers,
     * computed once. False disables every native operation that uses the curve (#12).
     */
    val selfTestPassed: Boolean by lazy { selfTest() }

    // NIP-44 v2 conversation-key vector 0 (paulmillr/nip44 nip44.vectors.json).
    private const val KAT_SECRET = "315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268"
    private const val KAT_PEER = "c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133"
    private const val KAT_CONVERSATION_KEY = "3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1"

    internal fun selfTest(): Boolean {
        if (!Secp256k1.selfTest()) return false
        val conversationKey = try {
            nip44ConversationKey(hexToBytes(KAT_SECRET), KAT_PEER)
        } catch (e: Exception) {
            Log.e(TAG, "selfTest FAIL: NIP-44 conversation key threw", e)
            return false
        }
        if (bytesToHex(conversationKey) != KAT_CONVERSATION_KEY) {
            Log.e(TAG, "selfTest FAIL: NIP-44 conversation key mismatch")
            return false
        }
        return true
    }

    // ── NIP-44 v2 ────────────────────────────────────────────────────────

    fun nip44Encrypt(privateKey: ByteArray, peerPubkeyHex: String, plaintext: String): String {
        val conversationKey = nip44ConversationKey(privateKey, peerPubkeyHex)
        return nip44EncryptWithConversationKey(conversationKey, plaintext)
    }

    fun nip44Decrypt(privateKey: ByteArray, peerPubkeyHex: String, ciphertext: String): String {
        val conversationKey = nip44ConversationKey(privateKey, peerPubkeyHex)
        return nip44DecryptWithConversationKey(conversationKey, ciphertext)
    }

    // ── NIP-04 ────────────────────────────────────────────────────────────

    fun nip04Encrypt(privateKey: ByteArray, peerPubkeyHex: String, plaintext: String): String {
        val sharedX = ecdhSharedSecretX(privateKey, peerPubkeyHex)
        val iv = ByteArray(16).also { secureRandom.nextBytes(it) }
        val encrypted = aes256CbcEncrypt(sharedX, iv, plaintext.toByteArray(Charsets.UTF_8))
        return android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP) +
            "?iv=" + android.util.Base64.encodeToString(iv, android.util.Base64.NO_WRAP)
    }

    fun nip04Decrypt(privateKey: ByteArray, peerPubkeyHex: String, ciphertext: String): String {
        val sharedX = ecdhSharedSecretX(privateKey, peerPubkeyHex)
        val parts = ciphertext.split("?iv=", limit = 2)
        if (parts.size != 2) throw IllegalArgumentException("Malformed NIP-04 ciphertext: missing ?iv=")
        val encrypted = android.util.Base64.decode(parts[0], android.util.Base64.NO_WRAP)
        val iv = android.util.Base64.decode(parts[1], android.util.Base64.NO_WRAP)
        if (iv.size != 16) throw IllegalArgumentException("Malformed NIP-04 IV")
        val decrypted = aes256CbcDecrypt(sharedX, iv, encrypted)
        return String(decrypted, Charsets.UTF_8)
    }

    /**
     * Whether [message] has the shape of a Nostr event's id serialisation,
     * `[0,pubkey,created_at,kind,tags,content]` (NIP-01).
     *
     * sign_message signs sha256(message), and the sha256 of that serialisation is the event's id:
     * signing it would sign an event of any kind (diogel-io/symudol#8). Deliberately broad: any
     * JSON array of six elements starting with the number 0 counts. The Dart
     * `isNostrEventSerialisation` is the same rule.
     */
    fun isNostrEventSerialisation(message: String): Boolean {
        val array = try {
            JSONArray(message)
        } catch (e: Exception) {
            return false
        }
        val first = array.opt(0)
        return array.length() == 6 && first is Number && first.toDouble() == 0.0
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
    fun decryptZapEvent(privateKey: ByteArray, eventJson: String): String? {
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

            nip04Decrypt(privateKey, peerPubkey, content)
        } catch (e: Exception) {
            Log.e(TAG, "decryptZapEvent failed", e)
            null
        }
    }

    // ── ECDH shared secret ───────────────────────────────────────────────

    private fun ecdhSharedSecretX(privateKey: ByteArray, peerPubkeyHex: String): ByteArray {
        val peerPubkey = Secp256k1.pointFromHex(peerPubkeyHex)
            ?: throw IllegalArgumentException("Invalid peer pubkey")
        val sharedPoint = Secp256k1.multiply(peerPubkey, privateKey)
            ?: throw IllegalArgumentException("ECDH multiplication failed")
        return bigIntTo32Bytes(sharedPoint.x)
    }

    // ── NIP-44 v2 internals (matches nostr-tools / Dart implementation) ──

    private fun nip44ConversationKey(privateKey: ByteArray, peerPubkeyHex: String): ByteArray {
        val sharedX = ecdhSharedSecretX(privateKey, peerPubkeyHex)
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

    // ── Crypto utilities ─────────────────────────────────────────────────

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

    private fun hexToBytes(hex: String): ByteArray {
        if (hex.length % 2 != 0) throw IllegalArgumentException("Hex string must have even length, got ${hex.length}")
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
 * Minimal secp256k1 curve operations for ECDH. Not constant-time ([BigInteger]); the NIP-04 and
 * NIP-44 follow-up to #12 is to route those through Dart or a vetted library too.
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

    /**
     * Known answers: 1·G, 2·G, and a full-width scalar (BIP-340 test vector 1's key), which
     * exercises every doubling and addition the 256-step ladder makes.
     */
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
        val full = multiply(G, BigInteger("B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF", 16))
        val expectedFullX = BigInteger("DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", 16)
        if (full?.x != expectedFullX) {
            android.util.Log.e("Diogel-Secp256k1", "selfTest FAIL: full-width scalar x mismatch")
            return false
        }
        android.util.Log.d("Diogel-Secp256k1", "selfTest PASS: secp256k1 point arithmetic is correct")
        return true
    }
}

private operator fun ByteArray.plus(other: ByteArray): ByteArray {
    return this.copyOf(this.size + other.size).also { System.arraycopy(other, 0, it, this.size, other.size) }
}