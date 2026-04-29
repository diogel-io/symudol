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
  if (failure is SecureStorageFailure) {
    return 'Storage error: ${failure.message}';
  }
  if (failure is CryptoFailure) {
    return 'Encryption error: ${failure.message}';
  }
  
  return failure.message;
}
