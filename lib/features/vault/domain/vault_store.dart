import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';

abstract class VaultStore {
  /// Returns the current version of the storage schema.
  Future<String?> getVersion();

  /// Sets the storage schema version.
  Future<void> setVersion(String version);

  /// Reads the vault sentinel.
  Future<String?> getSentinel();

  /// Writes the vault sentinel.
  Future<void> setSentinel(String sentinel);

  /// Reads the active identity ID.
  Future<String?> getActiveIdentityId();

  /// Sets the active identity ID.
  Future<void> setActiveIdentityId(String id);

  /// Reads all identity records.
  Future<List<VaultIdentityRecord>> getIdentities();

  /// Reads a full identity record including secret.
  Future<VaultIdentityRecord?> getIdentityRecord(String localId);

  /// Saves an identity record.
  Future<void> saveIdentityRecord(VaultIdentityRecord record);

  /// Deletes an identity record by its local ID.
  Future<void> deleteIdentity(String localId);

  /// Clears all vault data.
  Future<void> clearAll();
}
