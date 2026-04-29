sealed class VaultFailure {
  const VaultFailure();
}

class VaultLockedFailure extends VaultFailure {
  const VaultLockedFailure();
}

class InvalidPrivateKeyFailure extends VaultFailure {
  const InvalidPrivateKeyFailure();
}

class UnsupportedKeyFormatFailure extends VaultFailure {
  const UnsupportedKeyFormatFailure();
}

class DuplicateIdentityFailure extends VaultFailure {
  const DuplicateIdentityFailure();
}

class SecureStorageFailure extends VaultFailure {
  final String message;
  const SecureStorageFailure(this.message);
}

class CryptoFailure extends VaultFailure {
  final String message;
  const CryptoFailure(this.message);
}
