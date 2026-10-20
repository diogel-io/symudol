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
