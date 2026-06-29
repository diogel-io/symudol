import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:android_diogel/features/vault/domain/vault_crypto_service.dart';
import 'package:pointycastle/export.dart';

/// [VaultCryptoService] implementation backed by `pointycastle`.
///
/// Uses Argon2id for PIN-based key derivation and AES-256-GCM for both DEK
/// wrapping and identity-secret encryption, per
/// `documentation/vault-pin-key-encryption-design.md`.
class PointyCastleVaultCryptoService implements VaultCryptoService {
  static const int _saltLength = 16;
  static const int _dekLength = 32;
  static const int _nonceLength = 12;
  static const int _macSizeBits = 128;

  const PointyCastleVaultCryptoService();

  @override
  Uint8List generateSalt() => _randomBytes(_saltLength);

  @override
  Uint8List generateDek() => _randomBytes(_dekLength);

  @override
  Uint8List deriveKek(String pin, Uint8List salt, VaultKdfParams params) {
    final argon2Params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      desiredKeyLength: _dekLength,
      iterations: params.iterations,
      memory: params.memory,
      lanes: params.parallelism,
    );

    final generator = Argon2BytesGenerator()..init(argon2Params);
    return generator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  @override
  String wrapDek(Uint8List dek, Uint8List kek) => _encryptBytes(dek, kek);

  @override
  Uint8List unwrapDek(String wrapped, Uint8List kek) =>
      _decryptBytes(wrapped, kek);

  @override
  String encrypt(String plaintext, Uint8List key) =>
      _encryptBytes(Uint8List.fromList(utf8.encode(plaintext)), key);

  @override
  String decrypt(String wrapped, Uint8List key) =>
      utf8.decode(_decryptBytes(wrapped, key));

  String _encryptBytes(Uint8List plaintext, Uint8List key) {
    final nonce = _randomBytes(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          _macSizeBits,
          nonce,
          Uint8List(0),
        ),
      );

    final ciphertext = cipher.process(plaintext);
    final combined = Uint8List(nonce.length + ciphertext.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + ciphertext.length, ciphertext);
    return base64Encode(combined);
  }

  Uint8List _decryptBytes(String wrapped, Uint8List key) {
    final combined = base64Decode(wrapped);
    if (combined.length <= _nonceLength) {
      throw const VaultCryptoTamperException('Ciphertext is too short');
    }

    final nonce = combined.sublist(0, _nonceLength);
    final ciphertext = combined.sublist(_nonceLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          _macSizeBits,
          nonce,
          Uint8List(0),
        ),
      );

    try {
      return cipher.process(ciphertext);
    } on InvalidCipherTextException catch (e) {
      throw VaultCryptoTamperException(e.message);
    }
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}