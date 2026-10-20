import 'package:symudol/features/vault/domain/biometric_vault.dart';

/// Where biometric unlock stands (#23).
class BiometricUnlockStatus {
  /// Whether the user turned it on: a biometric wrap of the DEK is stored.
  final bool enabled;

  /// Whether this phone can use it now.
  final BiometricAvailability availability;

  /// Whether the PIN is needed first: after a restart, or [pinInterval]
  /// after the last PIN check.
  final bool pinRequired;

  /// Whether this read turned biometric unlock off, because the phone no
  /// longer has a fingerprint enrolled and the key went with it.
  final bool turnedOff;

  const BiometricUnlockStatus({
    required this.enabled,
    required this.availability,
    required this.pinRequired,
    this.turnedOff = false,
  });

  static const off = BiometricUnlockStatus(
    enabled: false,
    availability: BiometricAvailability.unavailable,
    pinRequired: false,
  );

  /// Whether the unlock screen can offer a fingerprint now.
  bool get canUnlock =>
      enabled &&
      availability == BiometricAvailability.available &&
      !pinRequired;

  /// On, but the phone can't use it now (no sensor, or not available).
  bool get enabledButUnavailable =>
      enabled && availability != BiometricAvailability.available;

  @override
  bool operator ==(Object other) =>
      other is BiometricUnlockStatus &&
      other.enabled == enabled &&
      other.availability == availability &&
      other.pinRequired == pinRequired &&
      other.turnedOff == turnedOff;

  @override
  int get hashCode =>
      Object.hash(enabled, availability, pinRequired, turnedOff);
}
