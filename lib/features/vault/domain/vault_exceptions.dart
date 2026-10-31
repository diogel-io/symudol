sealed class VaultException implements Exception {
  final String message;
  const VaultException(this.message);
}

class VaultNotFoundException extends VaultException {
  const VaultNotFoundException() : super('Vault not found');
}

class VaultAlreadyExistsException extends VaultException {
  const VaultAlreadyExistsException() : super('Vault already exists');
}

class VaultLockedException extends VaultException {
  const VaultLockedException() : super('Vault is locked');
}

class InvalidPinException extends VaultException {
  const InvalidPinException() : super('Invalid PIN');
}

class VaultLockedOutException extends VaultException {
  /// How long until the next attempt is allowed.
  final Duration remaining;

  VaultLockedOutException(this.remaining)
    : super('Too many failed attempts. Try again later.');
}

/// A wrong PIN reached the failed-attempt limit and the vault was erased
/// (#16).
class VaultWipedException extends VaultException {
  const VaultWipedException()
    : super('Too many failed attempts. The vault was erased.');
}

/// A wipe ran every step, but [failedSteps] could not be erased.
class VaultWipeIncompleteException extends VaultException {
  final List<String> failedSteps;

  VaultWipeIncompleteException(this.failedSteps)
    : super('Wipe did not finish: ${failedSteps.join(', ')}');
}

class IdentityNotFoundException extends VaultException {
  const IdentityNotFoundException() : super('Identity not found');
}

class IdentityMismatchException extends VaultException {
  const IdentityMismatchException() : super('Identity mismatch');
}

class VaultSigningException extends VaultException {
  const VaultSigningException(super.message);
}

class VaultStorageException extends VaultException {
  const VaultStorageException(super.message);

  @override
  String toString() => 'VaultStorageException: $message';
}

/// The passphrase does not open a vault backup (#25).
class BackupPassphraseException extends VaultException {
  const BackupPassphraseException()
    : super("That passphrase doesn't open this backup.");
}

/// A file that is not a vault backup this build can restore, or a backup
/// that could not be made (#25).
class VaultBackupException extends VaultException {
  const VaultBackupException(super.message);

  @override
  String toString() => 'VaultBackupException: $message';
}

/// Biometric unlock is not turned on, or this phone cannot use it (#23).
class BiometricUnavailableException extends VaultException {
  const BiometricUnavailableException()
    : super('Biometric unlock is not available');
}

/// The PIN is needed first: after a restart, or 72 hours after the last PIN
/// unlock (#23).
class BiometricPinRequiredException extends VaultException {
  const BiometricPinRequiredException()
    : super('Enter your PIN to use biometric unlock again');
}

/// The user dismissed the biometric prompt (#23).
class BiometricCancelledException extends VaultException {
  const BiometricCancelledException() : super('Biometric unlock cancelled');
}

/// Android stopped biometric checks after too many failed attempts (#23).
class BiometricLockedOutException extends VaultException {
  const BiometricLockedOutException()
    : super('Too many biometric attempts. Use your PIN.');
}

/// The biometric key can no longer be used, for example because a
/// fingerprint was added. Biometric unlock has been turned off (#23).
class BiometricKeyInvalidatedException extends VaultException {
  const BiometricKeyInvalidatedException()
    : super('Biometric unlock was turned off');
}

/// The biometric check failed for another reason (#23).
class BiometricFailedException extends VaultException {
  const BiometricFailedException(super.message);
}
