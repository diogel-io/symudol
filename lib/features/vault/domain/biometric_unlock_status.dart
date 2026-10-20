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

  const BiometricUnlockStatus({
    required this.enabled,
    required this.availability,
    required this.pinRequired,
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

  @override
  bool operator ==(Object other) =>
      other is BiometricUnlockStatus &&
      other.enabled == enabled &&
      other.availability == availability &&
      other.pinRequired == pinRequired;

  @override
  int get hashCode => Object.hash(enabled, availability, pinRequired);
}
