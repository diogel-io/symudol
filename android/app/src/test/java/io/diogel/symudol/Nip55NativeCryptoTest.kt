package io.diogel.symudol

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Nip55NativeCrypto: it never signs (#12), its self-test, and the event
 * serialisation check the ContentProvider refuses sign_message with (#8).
 */
class Nip55NativeCryptoTest {

    private val testPubKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    // ════════════════════════════════════════════════════════════════════
    //  Never signs (#12)
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun nativeCryptoHasNoSigningOperation() {
        // Signing belongs to the Dart vault service, which verifies every signature.
        val names = (Nip55NativeCrypto::class.java.declaredMethods.map { it.name } +
            Secp256k1::class.java.declaredMethods.map { it.name }).map { it.lowercase() }
        assertTrue(names.toString(), names.none { "sign" in it && "serialisation" !in it })
    }

    // ════════════════════════════════════════════════════════════════════
    //  Self-test
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun selfTest_passes() {
        assertTrue(Secp256k1.selfTest())
        assertTrue(Nip55NativeCrypto.selfTest())
        assertTrue(Nip55NativeCrypto.selfTestPassed)
    }

    // ════════════════════════════════════════════════════════════════════
    //  sign_message — never an event serialisation (#8)
    // ════════════════════════════════════════════════════════════════════

    @Test
    fun isNostrEventSerialisation_matchesTheEventIdSerialisation() {
        for (message in listOf(
            "[0,\"$testPubKey\",1700000000,1,[],\"hi\"]",
            "[0,\"$testPubKey\",1700000000,0,[[\"p\",\"$testPubKey\"]],\"{}\"]",
            " [ 0 , \"x\" , 1 , 1 , [ ] , \"\" ] ",
            "[0,null,null,null,null,null]",
            "[0.0,1,2,3,4,5]",
        )) {
            assertTrue(message, Nip55NativeCrypto.isNostrEventSerialisation(message))
        }
    }

    @Test
    fun isNostrEventSerialisation_ignoresEverythingElse() {
        for (message in listOf(
            "[]",
            "[1,\"$testPubKey\",1700000000,1,[],\"hi\"]",
            "[\"0\",\"$testPubKey\",1700000000,1,[],\"hi\"]",
            "[0,\"$testPubKey\",1700000000,1,[]]",
            "[0,\"$testPubKey\",1700000000,1,[],\"hi\",\"extra\"]",
            "{\"kind\":1,\"content\":\"hi\"}",
            "[0,\"$testPubKey\",1700000000,1,[],\"hi\"",
            "hello",
            "0",
            "",
            "gm \uD83C\uDF05",
        )) {
            assertFalse(message, Nip55NativeCrypto.isNostrEventSerialisation(message))
        }
    }
}
