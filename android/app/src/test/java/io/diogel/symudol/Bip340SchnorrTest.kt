package io.diogel.symudol

import org.junit.Assert.*
import org.junit.Test
import java.math.BigInteger

/**
 * BIP-340 Schnorr signature test vectors, as a check on the [Secp256k1] curve arithmetic that
 * native NIP-04/NIP-44 ECDH relies on. The app never signs natively (#12); the signing here is a
 * test-side BIP-340 implementation over that arithmetic, compared against the official vectors:
 * https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
 */
class Bip340SchnorrTest {

    companion object {
        data class SignVector(
            val index: Int,
            val secretKey: String,
            val publicKey: String,
            val auxRand: String,
            val message: String, // raw hex bytes of the message
            val expectedSignature: String,
            val comment: String
        )

        // Vectors 0-3: standard sign+verify vectors
        val SIGN_VECTORS = listOf(
            SignVector(0,
                "0000000000000000000000000000000000000000000000000000000000000003",
                "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0",
                ""
            ),
            SignVector(1,
                "B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF",
                "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
                "0000000000000000000000000000000000000000000000000000000000000001",
                "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
                "6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A",
                ""
            ),
            SignVector(2,
                "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9",
                "DD308AFEC5777E13121FA72B9CC1B7CC0139715309B086C960E18FD969774EB8",
                "C87AA53824B4D7AE2EB035A2B5BBBCCC080E76CDC6D1692C4B0B62D798E6D906",
                "7E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C",
                "5831AAEED7B44BB74E5EAB94BA9D4294C49BCF2A60728D8B4C200F50DD313C1BAB745879A5AD954A72C45A91C3A51D3C7ADEA98D82F8481E0E1E03674A6F3FB7",
                ""
            ),
            SignVector(3,
                "0B432B2677937381AEF05BB02A66ECD012773062CF3FA2549E44F58ED2401710",
                "25D1DFF95105F5253C4022F628A996AD3A0D95FBF21D468A1B33F8C160D8F517",
                "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
                "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
                "7EB0509757E246F19449885651611CB965ECC1A187DD51B64FDA1EDC9637D5EC97582B9CB13DB3933705B32BA982AF5AF25FD78881EBB32771FC5922EFC66EA3",
                "test fails if msg is reduced modulo p or n"
            ),
        )

        // Vectors 15-18: varying message sizes
        val EXTRA_VECTORS = listOf(
            SignVector(15,
                "0340034003400340034003400340034003400340034003400340034003400340",
                "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "",  // empty message
                "71535DB165ECD9FBBC046E5FFAEA61186BB6AD436732FCCC25291A55895464CF6069CE26BF03466228F19A3A62DB8A649F2D560FAC652827D1AF0574E427AB63",
                "message of size 0"
            ),
            SignVector(16,
                "0340034003400340034003400340034003400340034003400340034003400340",
                "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "11",  // 1-byte message
                "08A20A0AFEF64124649232E0693C583AB1B9934AE63B4C3511F3AE1134C6A303EA3173BFEA6683BD101FA5AA5DBC1996FE7CACFC5A577D33EC14564CEC2BACBF",
                "message of size 1"
            ),
        )
    }

    // ── Crypto primitives (mirrors Nip55NativeCrypto) ──────────────────

    private fun sha256(data: ByteArray): ByteArray =
        java.security.MessageDigest.getInstance("SHA-256").digest(data)

    private fun taggedHash(tag: String, message: ByteArray): ByteArray {
        val tagHash = sha256(tag.toByteArray(Charsets.UTF_8))
        return sha256(tagHash + tagHash + message)
    }

    private fun hexToBytes(hex: String): ByteArray {
        if (hex.isEmpty()) return ByteArray(0)
        val len = hex.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(hex[i], 16) shl 4) + Character.digit(hex[i + 1], 16)).toByte()
            i += 2
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

    // ── BIP-340 deterministic signing (with fixed aux_rand) ────────────

    /**
     * Full BIP-340 signing algorithm with fixed aux_rand.
     * This mirrors the reference Python implementation exactly:
     *   - No message hashing step (message bytes used directly in nonce/challenge)
     *   - Uses tagged_hash("BIP0340/aux", aux_rand) for t
     *   - Uses tagged_hash("BIP0340/nonce", ...) for rand
     *   - Uses tagged_hash("BIP0340/challenge", ...) for e
     */
    private fun bip340Sign(seckeyHex: String, auxRandHex: String, messageHex: String): String {
        val d0 = BigInteger(1, hexToBytes(seckeyHex))
        val auxRand = hexToBytes(auxRandHex)
        val msg = hexToBytes(messageHex)

        val P = Secp256k1.multiply(Secp256k1.G, d0)
            ?: throw IllegalArgumentException("Invalid secret key")

        // BIP-340: d = d0 if has_even_y(P), else n - d0
        val d = if (P.y.mod(Secp256k1.TWO) != BigInteger.ZERO) {
            Secp256k1.n.subtract(d0)
        } else {
            d0
        }

        // t = xor(d_bytes, tagged_hash("BIP0340/aux", aux_rand))
        val t = taggedHash("BIP0340/aux", auxRand)
        val dBytes = bigIntTo32Bytes(d)
        val xored = ByteArray(32)
        for (i in 0 until 32) xored[i] = (dBytes[i].toInt() xor t[i].toInt()).toByte()

        // rand = tagged_hash("BIP0340/nonce", t || P.x || msg)
        val rand = taggedHash("BIP0340/nonce", xored + bigIntTo32Bytes(P.x) + msg)
        val k0 = BigInteger(1, rand).mod(Secp256k1.n)
        if (k0 == BigInteger.ZERO) throw IllegalArgumentException("k is zero")

        // R = k0 * G
        val R = Secp256k1.multiply(Secp256k1.G, k0)
            ?: throw IllegalArgumentException("R is invalid")

        // k = n - k0 if !has_even_y(R), else k0
        val k = if (R.y.mod(Secp256k1.TWO) != BigInteger.ZERO) {
            Secp256k1.n.subtract(k0)
        } else {
            k0
        }

        // e = tagged_hash("BIP0340/challenge", R.x || P.x || msg) mod n
        val e = BigInteger(1, taggedHash("BIP0340/challenge",
            bigIntTo32Bytes(R.x) + bigIntTo32Bytes(P.x) + msg)).mod(Secp256k1.n)

        // sig = (k + e * d) mod n
        val sig = k.add(e.multiply(d)).mod(Secp256k1.n)

        return bytesToHex(bigIntTo32Bytes(R.x) + bigIntTo32Bytes(sig)).uppercase()
    }

    // ── Tests ──────────────────────────────────────────────────────────

    @Test
    fun testPublicKeyDerivation() {
        for (v in SIGN_VECTORS) {
            val d0 = BigInteger(1, hexToBytes(v.secretKey))
            val P = Secp256k1.multiply(Secp256k1.G, d0)
            assertNotNull("Vector ${v.index}: multiply returned null", P)

            // BIP-340 pubkey is the x-coordinate of the even-y version of P
            // If P.y is odd, the effective key is the negation, but the pubkey
            // x-coordinate stays the same (negation doesn't change x on secp256k1)
            val pxHex = bytesToHex(bigIntTo32Bytes(P!!.x)).uppercase()
            assertEquals("Vector ${v.index}: pubkey x mismatch", v.publicKey, pxHex)
        }
    }

    @Test
    fun testExtraPublicKeyDerivation() {
        for (v in EXTRA_VECTORS) {
            val d0 = BigInteger(1, hexToBytes(v.secretKey))
            val P = Secp256k1.multiply(Secp256k1.G, d0)
            assertNotNull("Vector ${v.index}: multiply returned null", P)
            val pxHex = bytesToHex(bigIntTo32Bytes(P!!.x)).uppercase()
            assertEquals("Vector ${v.index}: pubkey x mismatch", v.publicKey, pxHex)
        }
    }

    @Test
    fun testDeterministicSigning() {
        for (v in SIGN_VECTORS) {
            val sig = bip340Sign(v.secretKey, v.auxRand, v.message)
            assertEquals("Vector ${v.index} (${v.comment}): signature mismatch",
                v.expectedSignature, sig)
        }
    }

    @Test
    fun testExtraDeterministicSigning() {
        for (v in EXTRA_VECTORS) {
            val sig = bip340Sign(v.secretKey, v.auxRand, v.message)
            assertEquals("Vector ${v.index} (${v.comment}): signature mismatch",
                v.expectedSignature, sig)
        }
    }

    @Test
    fun testSignatureVerification() {
        for (v in SIGN_VECTORS) {
            val sigBytes = hexToBytes(v.expectedSignature)
            val r = BigInteger(1, sigBytes.copyOfRange(0, 32))
            val s = BigInteger(1, sigBytes.copyOfRange(32, 64))

            val pubKeyPoint = Secp256k1.pointFromHex(v.publicKey)
            assertNotNull("Vector ${v.index}: pubkey point is null", pubKeyPoint)

            val msgBytes = hexToBytes(v.message)

            // e = tagged_hash("BIP0340/challenge", R.x || P.x || msg) mod n
            val e = BigInteger(1, taggedHash("BIP0340/challenge",
                bigIntTo32Bytes(r) + bigIntTo32Bytes(pubKeyPoint!!.x) + msgBytes))
                .mod(Secp256k1.n)

            // Verify: s*G + (n-e)*P should have x-coordinate equal to r
            val sG = Secp256k1.multiply(Secp256k1.G, s)!!
            val negEP = Secp256k1.multiply(pubKeyPoint, Secp256k1.n.subtract(e))!!
            val Rprime = Secp256k1.add(sG, negEP)

            assertNotNull("Vector ${v.index}: R' is null", Rprime)
            assertEquals("Vector ${v.index}: signature verification failed",
                r, Rprime!!.x)
        }
    }

    @Test
    fun testSecp256k1PointArithmetic() {
        // Verify 1*G == G
        val g1 = Secp256k1.multiply(Secp256k1.G, BigInteger.ONE)
        assertEquals("1*G should equal G", Secp256k1.G, g1)

        // Verify 2*G against known value
        val g2 = Secp256k1.multiply(Secp256k1.G, BigInteger.valueOf(2))
        val expected2Gx = BigInteger("C6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5", 16)
        assertEquals("2*G x mismatch", expected2Gx, g2!!.x)
    }
}