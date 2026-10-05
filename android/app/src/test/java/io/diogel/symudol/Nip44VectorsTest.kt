package io.diogel.symudol

import org.junit.Assert.*
import org.junit.Test
import java.math.BigInteger
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.ChaCha20ParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * NIP-44 v2 encryption/decryption test vectors.
 *
 * Tests core crypto primitives against the official vectors from:
 * https://github.com/paulmillr/nip44/blob/main/nip44.vectors.json
 *
 * All crypto is replicated here to avoid Android SDK dependencies in JVM tests.
 * The replication mirrors Nip55NativeCrypto.kt exactly.
 */
class Nip44VectorsTest {
    private companion object {
        // The JDK's IETF ChaCha20 (12-byte nonce), which NIP-44 uses. Named explicitly because
        // Robolectric tests in the same JVM register BouncyCastle first, whose "ChaCha20" is the
        // original 8-byte-nonce variant and gives different output (#68).
        const val CHACHA_PROVIDER = "SunJCE"
    }


    // ── Shared crypto helpers ────────────────────────────────────────────

    private fun sha256(data: ByteArray): ByteArray =
        java.security.MessageDigest.getInstance("SHA-256").digest(data)

    private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    private fun hkdfExtract(salt: ByteArray, ikm: ByteArray): ByteArray =
        hmacSha256(salt, ikm)

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

    private fun hexToBytes(hex: String): ByteArray {
        if (hex.isEmpty()) return ByteArray(0)
        val data = ByteArray(hex.length / 2)
        for (i in data.indices) {
            data[i] = ((Character.digit(hex[2 * i], 16) shl 4) + Character.digit(hex[2 * i + 1], 16)).toByte()
        }
        return data
    }

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    private fun bigIntTo32Bytes(n: BigInteger): ByteArray {
        val raw = n.toByteArray()
        if (raw.size == 32) return raw
        if (raw.size > 32) return raw.copyOfRange(raw.size - 32, raw.size)
        return ByteArray(32 - raw.size) + raw
    }

    private fun ecdhSharedX(privateKeyHex: String, peerPubkeyHex: String): ByteArray {
        val privateKey = BigInteger(1, hexToBytes(privateKeyHex))
        val peerPubkey = Secp256k1.pointFromHex(peerPubkeyHex)
            ?: throw IllegalArgumentException("Invalid peer pubkey")
        val sharedPoint = Secp256k1.multiply(peerPubkey, privateKey)
            ?: throw IllegalArgumentException("ECDH failed")
        return bigIntTo32Bytes(sharedPoint.x)
    }

    private fun nip44ConversationKey(privateKeyHex: String, peerPubkeyHex: String): ByteArray {
        val sharedX = ecdhSharedX(privateKeyHex, peerPubkeyHex)
        return hkdfExtract("nip44-v2".toByteArray(Charsets.UTF_8), sharedX)
    }

    private data class MessageKeys(val chachaKey: ByteArray, val chachaNonce: ByteArray, val hmacKey: ByteArray)

    private fun nip44MessageKeys(conversationKey: ByteArray, nonce: ByteArray): MessageKeys {
        val expanded = hkdfExpand(conversationKey, nonce, 76)
        return MessageKeys(
            chachaKey = expanded.copyOfRange(0, 32),
            chachaNonce = expanded.copyOfRange(32, 44),
            hmacKey = expanded.copyOfRange(44, 76),
        )
    }

    private fun chacha20Encrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("ChaCha20", CHACHA_PROVIDER)
        val paramSpec = ChaCha20ParameterSpec(nonce, 0)
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "ChaCha20"), paramSpec)
        return cipher.doFinal(plaintext)
    }

    private fun chacha20Decrypt(key: ByteArray, nonce: ByteArray, ciphertext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("ChaCha20", CHACHA_PROVIDER)
        val paramSpec = ChaCha20ParameterSpec(nonce, 0)
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "ChaCha20"), paramSpec)
        return cipher.doFinal(ciphertext)
    }

    private fun nip44PaddedLength(unpaddedLen: Int): Int {
        if (unpaddedLen <= 32) return 32
        val nextPower = 1 shl (32 - Integer.numberOfLeadingZeros(unpaddedLen - 1))
        val chunk = if (nextPower <= 256) 32 else nextPower / 8
        return chunk * (((unpaddedLen - 1) / chunk) + 1)
    }

    private fun nip44Pad(plaintext: String): ByteArray {
        val messageBytes = plaintext.toByteArray(Charsets.UTF_8)
        val len = messageBytes.size
        if (len < 1 || len > 65535) throw IllegalArgumentException("Invalid NIP-44 plaintext length: $len")
        val paddedLen = nip44PaddedLength(len)
        val padded = ByteArray(2 + paddedLen)
        padded[0] = (len shr 8).toByte()
        padded[1] = len.toByte()
        System.arraycopy(messageBytes, 0, padded, 2, len)
        return padded
    }

    private fun nip44Unpad(data: ByteArray): String {
        if (data.size < 2) throw IllegalArgumentException("Invalid NIP-44 padded data")
        val unpaddedLen = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
        if (unpaddedLen == 0 || unpaddedLen > data.size - 2) throw IllegalArgumentException("Invalid NIP-44 unpadded length: $unpaddedLen")
        val expectedPaddedLen = nip44PaddedLength(unpaddedLen)
        if (data.size != 2 + expectedPaddedLen) throw IllegalArgumentException("Invalid NIP-44 padded data size")
        return String(data, 2, unpaddedLen, Charsets.UTF_8)
    }

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var result = 0
        for (i in a.indices) result = result or (a[i].toInt() xor b[i].toInt())
        return result == 0
    }

    private fun nip44EncryptWithNonce(conversationKey: ByteArray, nonce: ByteArray, plaintext: String): String {
        val messageKeys = nip44MessageKeys(conversationKey, nonce)
        val padded = nip44Pad(plaintext)
        val ciphertext = chacha20Encrypt(messageKeys.chachaKey, messageKeys.chachaNonce, padded)
        val mac = hmacSha256(messageKeys.hmacKey, nonce + ciphertext)
        val payload = byteArrayOf(0x02) + nonce + ciphertext + mac
        return java.util.Base64.getEncoder().encodeToString(payload)
    }

    private fun nip44DecryptWithConversationKey(conversationKey: ByteArray, payload: String): String {
        if (payload.isEmpty()) throw IllegalArgumentException("Empty NIP-44 payload")
        if (payload[0] == '#') throw IllegalArgumentException("Unsupported NIP-44 payload version")
        val raw = java.util.Base64.getDecoder().decode(payload)
        if (raw.size < 99 || raw.size > 65603) throw IllegalArgumentException("Invalid NIP-44 payload size: ${raw.size}")
        val version = raw[0]
        if (version.toInt() != 2) throw IllegalArgumentException("Unsupported NIP-44 version: $version")
        val nonce = raw.copyOfRange(1, 33)
        val ciphertext = raw.copyOfRange(33, raw.size - 32)
        val mac = raw.copyOfRange(raw.size - 32, raw.size)
        val messageKeys = nip44MessageKeys(conversationKey, nonce)
        val expectedMac = hmacSha256(messageKeys.hmacKey, nonce + ciphertext)
        if (!constantTimeEquals(mac, expectedMac)) throw IllegalArgumentException("NIP-44 HMAC verification failed")
        val decrypted = chacha20Decrypt(messageKeys.chachaKey, messageKeys.chachaNonce, ciphertext)
        return nip44Unpad(decrypted)
    }

    private operator fun ByteArray.plus(other: ByteArray): ByteArray {
        return this.copyOf(this.size + other.size).also { System.arraycopy(other, 0, it, this.size, other.size) }
    }

    private fun computePubkey(privateKeyHex: String): String {
        val d = BigInteger(1, hexToBytes(privateKeyHex))
        val P = Secp256k1.multiply(Secp256k1.G, d)!!
        return bytesToHex(bigIntTo32Bytes(P.x)).lowercase()
    }

    // ── Test: Conversation Key Derivation (13 vectors) ────────────────────

    @Test
    fun testConversationKeyDerivation() {
        // Standard vectors
        val vectors = listOf(
            Triple("315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268",
                "c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133",
                "3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1"),
            Triple("a1e37752c9fdc1273be53f68c5f74be7c8905728e8de75800b94262f9497c86e",
                "03bb7947065dde12ba991ea045132581d0954f042c84e06d8c00066e23c1a800",
                "4d14f36e81b8452128da64fe6f1eae873baae2f444b02c950b90e43553f2178b"),
            Triple("98a5902fd67518a0c900f0fb62158f278f94a21d6f9d33d30cd3091195500311",
                "aae65c15f98e5e677b5050de82e3aba47a6fe49b3dab7863cf35d9478ba9f7d1",
                "9c00b769d5f54d02bf175b7284a1cbd28b6911b06cda6666b2243561ac96bad7"),
            Triple("86ae5ac8034eb2542ce23ec2f84375655dab7f836836bbd3c54cefe9fdc9c19f",
                "59f90272378089d73f1339710c02e2be6db584e9cdbe86eed3578f0c67c23585",
                "19f934aafd3324e8415299b64df42049afaa051c71c98d0aa10e1081f2e3e2ba"),
            Triple("2528c287fe822421bc0dc4c3615878eb98e8a8c31657616d08b29c00ce209e34",
                "f66ea16104c01a1c532e03f166c5370a22a5505753005a566366097150c6df60",
                "c833bbb292956c43366145326d53b955ffb5da4e4998a2d853611841903f5442"),
            // Edge cases
            Triple("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139",
                "0000000000000000000000000000000000000000000000000000000000000002",
                "8b6392dbf2ec6a2b2d5b1477fc2be84d63ef254b667cadd31bd3f444c44ae6ba"),
            Triple("0000000000000000000000000000000000000000000000000000000000000002",
                "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdeb",
                "be234f46f60a250bef52a5ee34c758800c4ca8e5030bf4cc1a31d37ba2104d43"),
            Triple("0000000000000000000000000000000000000000000000000000000000000001",
                "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
                "3b4610cb7189beb9cc29eb3716ecc6102f1247e8f3101a03a1787d8908aeb54e"),
        )
        for ((i, triple) in vectors.withIndex()) {
            val (sec1, pub2, expectedKey) = triple
            val convKey = nip44ConversationKey(sec1, pub2)
            assertEquals("ConvKey vector $i: mismatch", expectedKey.lowercase(), bytesToHex(convKey).lowercase())
        }
    }

    // ── Test: Message Keys Derivation ────────────────────────────────

    @Test
    fun testMessageKeysDerivation() {
        val convKey = hexToBytes("a1a3d60f3470a8612633924e91febf96dc5366ce130f658b1f0fc652c20b3b54")
        val vectors = listOf(
            Triple("e1e6f880560d6d149ed83dcc7e5861ee62a5ee051f7fde9975fe5d25d2a02d72",
                "f145f3bed47cb70dbeaac07f3a3fe683e822b3715edb7c4fe310829014ce7d76",
                "c4ad129bb01180c0933a160c"),
            Triple("e1d6d28c46de60168b43d79dacc519698512ec35e8ccb12640fc8e9f26121101",
                "e35b88f8d4a8f1606c5082f7a64b100e5d85fcdb2e62aeafbec03fb9e860ad92",
                "22925e920cee4a50a478be90"),
            Triple("cfc13bef512ac9c15951ab00030dfaf2626fdca638dedb35f2993a9eeb85d650",
                "020783eb35fdf5b80ef8c75377f4e937efb26bcbad0e61b4190e39939860c4bf",
                "d3594987af769a52904656ac"),
        )
        val expectedHmacKeys = listOf(
            "027c1db445f05e2eee864a0975b0ddef5b7110583c8c192de3732571ca5838c4",
            "46a7c55d4283cb0df1d5e29540be67abfe709e3b2e14b7bf9976e6df994ded30",
            "237ec0ccb6ebd53d179fa8fd319e092acff599ef174c1fdafd499ef2b8dee745",
        )
        for ((i, vec) in vectors.withIndex()) {
            val (nonceHex, expectedChachaKey, expectedChachaNonce) = vec
            val nonce = hexToBytes(nonceHex)
            val keys = nip44MessageKeys(convKey, nonce)
            assertEquals("Vector $i: chacha_key mismatch", expectedChachaKey.lowercase(), bytesToHex(keys.chachaKey).lowercase())
            assertEquals("Vector $i: chacha_nonce mismatch", expectedChachaNonce.lowercase(), bytesToHex(keys.chachaNonce).lowercase())
            assertEquals("Vector $i: hmac_key mismatch", expectedHmacKeys[i].lowercase(), bytesToHex(keys.hmacKey).lowercase())
        }
    }

    // ── Test: Padding ────────────────────────────────────────────────

    @Test
    fun testPaddedLength() {
        val vectors = listOf(
            16 to 32, 32 to 32, 33 to 64, 37 to 64, 45 to 64, 49 to 64, 64 to 64,
            65 to 96, 100 to 128, 111 to 128, 200 to 224, 250 to 256, 320 to 320,
            383 to 384, 384 to 384, 400 to 448, 500 to 512, 512 to 512, 515 to 640,
            700 to 768, 800 to 896, 900 to 1024, 1020 to 1024, 65536 to 65536
        )
        for ((input, expected) in vectors) {
            assertEquals("calc_padded_len($input)", expected, nip44PaddedLength(input))
        }
    }

    // ── Test: Encrypt/Decrypt (vector 0 from official test file) ─────────

    @Test
    fun testDecryptEncryptVector0() {
        // Vector 0: sec1=1, sec2=2, plaintext="a"
        val sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
        val sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
        val expectedConvKey = "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d"
        val nonceHex = "0000000000000000000000000000000000000000000000000000000000000001"
        val expectedPlaintext = "a"
        val payload = "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"

        // Verify conversation key
        val pub2 = computePubkey(sec2)
        val convKey = nip44ConversationKey(sec1, pub2)
        assertEquals("conversation_key mismatch", expectedConvKey.lowercase(), bytesToHex(convKey).lowercase())

        // Decrypt
        val decrypted = nip44DecryptWithConversationKey(convKey, payload)
        assertEquals("decrypt plaintext mismatch", expectedPlaintext, decrypted)

        // Encrypt with same nonce should produce same payload
        val nonce = hexToBytes(nonceHex)
        val encrypted = nip44EncryptWithNonce(convKey, nonce, expectedPlaintext)
        assertEquals("encrypt payload mismatch", payload, encrypted)
    }

    // ── Test: Round-trip encrypt/decrypt ─────────────────────────────────

    @Test
    fun testEncryptDecryptRoundTrip() {
        val random = SecureRandom()
        val sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
        val sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
        val pub2 = computePubkey(sec2)
        val sec1Pub = computePubkey(sec1)

        val testPlaintexts = listOf("a", "hello", "🍕🫃", "表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀")

        for (plaintext in testPlaintexts) {
            val convKey1 = nip44ConversationKey(sec1, pub2)
            val convKey2 = nip44ConversationKey(sec2, sec1Pub)

            // Verify symmetry
            assertArrayEquals("conversation keys must be symmetric", convKey1, convKey2)

            val nonce = ByteArray(32).also { random.nextBytes(it) }
            val payload = nip44EncryptWithNonce(convKey1, nonce, plaintext)
            val decrypted = nip44DecryptWithConversationKey(convKey2, payload)
            assertEquals("round-trip failed for '$plaintext'", plaintext, decrypted)
        }
    }

    @Test
    fun testConversationKeySymmetry() {
        val random = SecureRandom()
        for (i in 0 until 5) {
            val sec1 = ByteArray(32).also { random.nextBytes(it) }.let { bytesToHex(it) }
            val sec2 = ByteArray(32).also { random.nextBytes(it) }.let { bytesToHex(it) }
            val pub2 = computePubkey(sec2)
            val sec1Pub = computePubkey(sec1)

            val convKey1 = nip44ConversationKey(sec1, pub2)
            val convKey2 = nip44ConversationKey(sec2, sec1Pub)
            assertArrayEquals("conversation keys must be symmetric (iter $i)", convKey1, convKey2)
        }
    }
}