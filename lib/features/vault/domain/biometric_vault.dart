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
/// [alias] names the Keystore key: each wrap gets its own, so a cancelled
/// turn-on leaves the previous key in place.
class BiometricWrap {
  final String alias;
  final String iv;
  final String ciphertext;

  const BiometricWrap({
    required this.alias,
    required this.iv,
    required this.ciphertext,
  });

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'iv': iv,
    'ciphertext': ciphertext,
  };

  /// The one key used before each wrap got its own (#108). A wrap saved
  /// then has no alias, and still opens with this key.
  static const legacyAlias = 'symudol_biometric_dek_wrap';

  factory BiometricWrap.fromJson(Map<String, dynamic> json) => BiometricWrap(
    alias: json['alias'] as String? ?? legacyAlias,
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

  /// Creates a new key and encrypts [dek] under it. Older keys are deleted
  /// only once this succeeds.
  Future<BiometricWrap> wrap(Uint8List dek);

  /// Decrypts the DEK in [wrap].
  Future<Uint8List> unwrap(BiometricWrap wrap);

  /// Deletes every biometric key. Does nothing if there is none.
  Future<void> deleteKey();
}
