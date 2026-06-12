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
  final DateTime lockoutUntil;

  VaultLockedOutException(this.lockoutUntil)
    : super('Too many failed attempts. Try again later.');
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
