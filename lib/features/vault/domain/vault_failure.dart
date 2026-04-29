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

class SecureStorageFailure extends VaultFailure {
  const SecureStorageFailure(super.message);
}

class CryptoFailure extends VaultFailure {
  const CryptoFailure(super.message);
}
