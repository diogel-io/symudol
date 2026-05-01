import 'package:android_diogel/features/vault/data/vault_identity_record.dart';

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

  /// Reads the inactivity timeout in minutes.
  Future<int?> getInactivityTimeout();

  /// Sets the inactivity timeout in minutes.
  Future<void> setInactivityTimeout(int minutes);

  /// Reads the background lock delay in minutes.
  ///
  /// `0` means lock immediately when backgrounded, and `-1` means never lock
  /// merely because the app was backgrounded while this process remains alive.
  Future<int?> getBackgroundLockDelayMinutes();

  /// Sets the background lock delay in minutes.
  Future<void> setBackgroundLockDelayMinutes(int minutes);

  /// Reads a full identity record including secret.
  Future<VaultIdentityRecord?> getIdentityRecord(String localId);

  /// Saves an identity record.
  Future<void> saveIdentityRecord(VaultIdentityRecord record);

  /// Deletes an identity record by its local ID.
  Future<void> deleteIdentity(String localId);

  /// Clears all vault data.
  Future<void> clearAll();
}
