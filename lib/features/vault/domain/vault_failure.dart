sealed class VaultFailure {
  final String message;
  const VaultFailure(this.message);
}

class VaultLockedFailure extends VaultFailure {
  const VaultLockedFailure() : super('Vault is locked');
}

class InvalidPrivateKeyFailure extends VaultFailure {
  const InvalidPrivateKeyFailure() : super('Invalid private key');
}

class UnsupportedKeyFormatFailure extends VaultFailure {
  const UnsupportedKeyFormatFailure() : super('Unsupported key format');
}

class DuplicateIdentityFailure extends VaultFailure {
  const DuplicateIdentityFailure() : super('Identity already exists in vault');
}

class VaultNotFoundFailure extends VaultFailure {
  const VaultNotFoundFailure() : super('Vault not found');
}

class VaultAlreadyExistsFailure extends VaultFailure {
  const VaultAlreadyExistsFailure() : super('Vault already exists');
}

class InvalidPinFailure extends VaultFailure {
  const InvalidPinFailure() : super('Invalid PIN');
}

class VaultLockedOutFailure extends VaultFailure {
  /// How long until the next attempt is allowed, when the failure was raised.
  final Duration remaining;

  const VaultLockedOutFailure(this.remaining)
    : super('Too many failed attempts. Try again later.');
}

class VaultWipedFailure extends VaultFailure {
  const VaultWipedFailure()
    : super('Too many failed attempts. The vault was erased.');
}

class VaultWipeIncompleteFailure extends VaultFailure {
  const VaultWipeIncompleteFailure()
    : super('The vault was not completely wiped.');
}

class IdentityNotFoundFailure extends VaultFailure {
  const IdentityNotFoundFailure() : super('Identity not found');
}

class SecureStorageFailure extends VaultFailure {
  const SecureStorageFailure(super.message);
}

class CryptoFailure extends VaultFailure {
  const CryptoFailure(super.message);
}

/// Biometric unlock is off, or this phone cannot use it (#23).
class BiometricUnavailableFailure extends VaultFailure {
  const BiometricUnavailableFailure()
    : super('Biometric unlock is not available');
}

/// The PIN is needed: after a restart, or 72 hours after the last PIN (#23).
class BiometricPinRequiredFailure extends VaultFailure {
  const BiometricPinRequiredFailure()
    : super('Enter your PIN to use biometric unlock again');
}

/// Android stopped biometric checks after too many failed attempts (#23).
class BiometricLockedOutFailure extends VaultFailure {
  const BiometricLockedOutFailure()
    : super('Too many biometric attempts. Use your PIN.');
}

/// The biometric key can no longer be used and biometric unlock was turned
/// off, for example because a fingerprint was added (#23).
class BiometricKeyInvalidatedFailure extends VaultFailure {
  const BiometricKeyInvalidatedFailure()
    : super('Biometric unlock was turned off');
}

/// The biometric check failed for another reason (#23).
class BiometricFailure extends VaultFailure {
  const BiometricFailure(super.message);
}

/// The passphrase does not open a vault backup (#25).
class BackupPassphraseFailure extends VaultFailure {
  const BackupPassphraseFailure()
    : super("That passphrase doesn't open this backup.");
}

/// A backup could not be made or read; [message] says why (#25).
class VaultBackupFailure extends VaultFailure {
  const VaultBackupFailure(super.message);
}
