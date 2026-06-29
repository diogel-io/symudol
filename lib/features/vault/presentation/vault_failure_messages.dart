import '../domain/vault_failure.dart';

String vaultFailureMessage(VaultFailure failure) {
  if (failure is VaultLockedFailure) {
    return 'Vault is locked. Please unlock it first.';
  }
  if (failure is InvalidPrivateKeyFailure) {
    return 'Invalid nsec key format';
  }
  if (failure is UnsupportedKeyFormatFailure) {
    return 'Invalid private key format';
  }
  if (failure is DuplicateIdentityFailure) {
    return 'This identity already exists in your vault.';
  }
  if (failure is VaultNotFoundFailure) {
    return 'Vault not found.';
  }
  if (failure is VaultAlreadyExistsFailure) {
    return 'A vault already exists on this device.';
  }
  if (failure is InvalidPinFailure) {
    return 'Invalid PIN. Please try again.';
  }
  if (failure is VaultLockedOutFailure) {
    return 'Too many failed attempts. Please wait and try again.';
  }
  if (failure is IdentityNotFoundFailure) {
    return 'The requested identity was not found.';
  }
  if (failure is SecureStorageFailure) {
    return 'A storage error occurred. Please try again.';
  }
  if (failure is CryptoFailure) {
    return 'An encryption error occurred.';
  }
  
  return failure.message;
}
