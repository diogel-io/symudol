package io.diogel.symudol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** The native scrypt against RFC 7914 §12 and the key NIP-49's test vector needs (#25). */
class ScryptTest {
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    private fun bytes(hex: String) = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    @Test
    fun `RFC 7914 vector 1, empty password and salt`() {
        assertEquals(
            "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442" +
                "fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906",
            hex(Scrypt.derive(ByteArray(0), ByteArray(0), 16, 1, 1, 64)),
        )
    }

    @Test
    fun `RFC 7914 vector 2, password and NaCl`() {
        assertEquals(
            "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162" +
                "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640",
            hex(Scrypt.derive("password".toByteArray(), "NaCl".toByteArray(), 1024, 8, 16, 64)),
        )
    }

    @Test
    fun `RFC 7914 vector 3, pleaseletmein and SodiumChloride`() {
        assertEquals(
            "7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2" +
                "d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887",
            hex(Scrypt.derive("pleaseletmein".toByteArray(), "SodiumChloride".toByteArray(), 16384, 8, 1, 64)),
        )
    }

    @Test
    fun `matches the Dart key for NIP-49's test vector`() {
        // Password "nostr", log_n 16, and the salt inside NIP-49's test ncryptsec; the expected key
        // is what pointycastle's scrypt gives, and it decrypts that vector in the Dart tests.
        assertEquals(
            "6d1e8b279f52b3a9ba60a2b43cab50804a67ac763ff4bafa782475efb0722aff",
            hex(Scrypt.derive("nostr".toByteArray(), bytes("52d7c3f8580e7b41953381e5bc49646b"), 1 shl 16, 8, 1, 32)),
        )
    }

    @Test
    fun `refuses a cost that is not a power of two, or too large`() {
        assertThrows(IllegalArgumentException::class.java) {
            Scrypt.derive(ByteArray(1), ByteArray(16), 1000, 8, 1, 32)
        }
        assertThrows(IllegalArgumentException::class.java) {
            Scrypt.derive(ByteArray(1), ByteArray(16), 1 shl 21, 8, 1, 32)
        }
    }
}
