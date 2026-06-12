import 'dart:typed_data';

/// Parameters for the Argon2id key derivation function used to turn a PIN
/// into a key-encryption key (KEK).
///
/// `memory` is expressed in KiB, matching the unit used by Argon2's spec and
/// by `pointycastle`'s `Argon2Parameters.memory`.
class VaultKdfParams {
  final String algorithm;
  final int memory;
  final int iterations;
  final int parallelism;

  const VaultKdfParams({
    this.algorithm = 'argon2id',
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  static const VaultKdfParams defaultParams = VaultKdfParams();

  Map<String, dynamic> toJson() => {
    'algorithm': algorithm,
    'memory': memory,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  factory VaultKdfParams.fromJson(Map<String, dynamic> json) => VaultKdfParams(
    algorithm: json['algorithm'] as String,
    memory: json['memory'] as int,
    iterations: json['iterations'] as int,
    parallelism: json['parallelism'] as int,
  );
}

/// Implements the PIN-derived key hierarchy used to protect identity secrets.
///
/// See `documentation/vault-pin-key-encryption-design.md` for the full design:
/// `PIN --Argon2id--> KEK --AES-256-GCM wrap--> DEK --AES-256-GCM--> secrets`.
abstract class VaultCryptoService {
  /// Generates a random salt suitable for [deriveKek].
  Uint8List generateSalt();

  /// Generates a random 256-bit data-encryption key (DEK).
  Uint8List generateDek();

  /// Derives a key-encryption key (KEK) from [pin] and [salt] using
  /// Argon2id with the given [params].
  Uint8List deriveKek(String pin, Uint8List salt, VaultKdfParams params);

  /// Encrypts [dek] with [kek] using AES-256-GCM.
  ///
  /// Returns base64(nonce ‖ ciphertext ‖ tag).
  String wrapDek(Uint8List dek, Uint8List kek);

  /// Decrypts a wrapped DEK produced by [wrapDek].
  ///
  /// Throws [VaultCryptoTamperException] if the GCM authentication tag does
  /// not match, which (for a wrapped DEK) means the PIN was incorrect.
  Uint8List unwrapDek(String wrapped, Uint8List kek);

  /// Encrypts [plaintext] with [key] using AES-256-GCM.
  ///
  /// Returns base64(nonce ‖ ciphertext ‖ tag).
  String encrypt(String plaintext, Uint8List key);

  /// Decrypts ciphertext produced by [encrypt].
  ///
  /// Throws [VaultCryptoTamperException] if the GCM authentication tag does
  /// not match.
  String decrypt(String wrapped, Uint8List key);
}

/// Thrown when an AES-GCM authentication tag check fails, indicating the
/// ciphertext was tampered with or decrypted with the wrong key.
class VaultCryptoTamperException implements Exception {
  final String message;
  const VaultCryptoTamperException(this.message);

  @override
  String toString() => 'VaultCryptoTamperException: $message';
}
