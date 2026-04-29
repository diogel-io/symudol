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
  Future<List<VaultIdentity>> getIdentities();

  /// Saves an identity record.
  Future<void> saveIdentity(VaultIdentity identity);

  /// Deletes an identity record by its local ID.
  Future<void> deleteIdentity(String localId);

  /// Clears all vault data.
  Future<void> clearAll();
}
