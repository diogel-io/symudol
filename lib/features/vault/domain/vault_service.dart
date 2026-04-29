import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';

/// Interface for the Vault service.
/// 
/// This service is responsible for managing the vault lifecycle and identities.
/// Implementation should be independent of any specific storage mechanism 
/// like flutter_secure_storage.
abstract interface class VaultService {
  /// Returns the current state of the vault.
  VaultState get state;

  /// Returns the active identity summary, or null if none is active or vault is locked.
  VaultIdentity? get activeIdentity;

  /// Creates a new vault with the given [pin].
  /// 
  /// Throws [VaultAlreadyExistsException] if a vault already exists.
  /// Throws [VaultStorageException] if there is an error during creation.
  Future<void> createVault(String pin);

  /// Unlocks the vault with the given [pin].
  /// 
  /// Throws [VaultNotFoundException] if no vault exists.
  /// Throws [InvalidPinException] if the PIN is incorrect.
  Future<void> unlock(String pin);

  /// Locks the vault.
  Future<void> lock();

  /// Creates a new identity in the vault.
  /// 
  /// [displayName] is an optional name for the identity.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [VaultStorageException] if there is an error during creation.
  Future<VaultIdentity> createIdentity({String? displayName});

  /// Imports an existing identity into the vault using its [keyInput] (nsec or hex).
  /// 
  /// [displayName] is an optional name for the identity.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [VaultStorageException] if the key is invalid or a duplicate.
  Future<VaultIdentity> importIdentity(String keyInput, {String? displayName});

  /// Lists all identities stored in the vault.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  Future<List<VaultIdentity>> listIdentities();

  /// Sets the identity with [localId] as the active identity.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [IdentityNotFoundException] if the identity does not exist.
  Future<void> setActiveIdentity(String localId);
}
