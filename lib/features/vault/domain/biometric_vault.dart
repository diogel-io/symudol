import 'dart:typed_data';

/// Whether this phone can use biometric unlock (#23).
enum BiometricAvailability {
  /// A strong biometric is enrolled.
  available,

  /// The sensor is there but no fingerprint is enrolled.
  noneEnrolled,

  /// No strong biometric sensor.
  noHardware,

  /// Not usable now, or not on this platform.
  unavailable,
}

/// The vault's DEK encrypted under the biometric Keystore key (#23).
///
/// AES-GCM: the tag checks that [ciphertext] is exactly what was wrapped.
class BiometricWrap {
  final String iv;
  final String ciphertext;

  const BiometricWrap({required this.iv, required this.ciphertext});

  Map<String, dynamic> toJson() => {'iv': iv, 'ciphertext': ciphertext};

  factory BiometricWrap.fromJson(Map<String, dynamic> json) => BiometricWrap(
    iv: json['iv'] as String,
    ciphertext: json['ciphertext'] as String,
  );
}

/// The Keystore key that wraps the DEK for biometric unlock (#23).
///
/// Each use of the key needs a fresh strong biometric, checked by Android's
/// `BiometricPrompt` with the key's cipher, so [wrap] and [unwrap] both show
/// the system prompt. Adding a fingerprint invalidates the key.
///
/// Throws [BiometricCancelledException], [BiometricLockedOutException],
/// [BiometricKeyInvalidatedException] or [BiometricFailedException] (from
/// `vault_exceptions.dart`).
abstract interface class BiometricVault {
  Future<BiometricAvailability> availability();

  /// Creates the key and encrypts [dek] under it.
  Future<BiometricWrap> wrap(Uint8List dek);

  /// Decrypts the DEK in [wrap].
  Future<Uint8List> unwrap(BiometricWrap wrap);

  /// Deletes the key. Does nothing if there is none.
  Future<void> deleteKey();
}
