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

class IdentityNotFoundFailure extends VaultFailure {
  const IdentityNotFoundFailure() : super('Identity not found');
}

class SecureStorageFailure extends VaultFailure {
  const SecureStorageFailure(super.message);
}

class CryptoFailure extends VaultFailure {
  const CryptoFailure(super.message);
}
