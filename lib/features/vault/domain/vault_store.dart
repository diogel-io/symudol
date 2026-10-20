import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/vault_key_envelope.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';

abstract class VaultStore {
  /// Returns the current version of the storage schema.
  Future<String?> getVersion();

  /// Sets the storage schema version.
  Future<void> setVersion(String version);

  /// Reads the key envelope: the Argon2id salt and parameters and the
  /// wrapped DEK.
  ///
  /// Prefers the single envelope value and falls back to the three separate
  /// keys that vaults made before #16 used. Returns `null` when there is no
  /// complete set.
  Future<VaultKeyEnvelope?> getKeyEnvelope();

  /// Writes the key envelope in a single write, then deletes any legacy
  /// separate keys. A failed write leaves the previous envelope in place.
  Future<void> setKeyEnvelope(VaultKeyEnvelope envelope);

  /// Reads the wrapped (encrypted) data-encryption key (DEK), from the
  /// envelope or the legacy key. A non-null value means a vault exists.
  Future<String?> getWrappedDek();

  /// Reads the number of consecutive failed unlock attempts.
  Future<int> getFailedUnlockAttempts();

  /// Sets the number of consecutive failed unlock attempts.
  Future<void> setFailedUnlockAttempts(int attempts);

  /// Reads the current PIN lockout, if any.
  Future<VaultLockout?> getLockout();

  /// Sets the PIN lockout. Pass `null` to clear it.
  Future<void> setLockout(VaultLockout? lockout);

  /// Reads the wall-clock lockout end that vaults made before #16 stored.
  Future<DateTime?> getLegacyLockoutUntil();

  /// Deletes the legacy wall-clock lockout end.
  Future<void> deleteLegacyLockoutUntil();

  /// Reads how many failed PIN attempts erase the vault, or `null` when the
  /// vault is never erased for failed attempts.
  Future<int?> getWipeAfterFailures();

  /// Sets how many failed PIN attempts erase the vault. Pass `null` to turn
  /// it off.
  Future<void> setWipeAfterFailures(int? attempts);

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

  /// Reads the in-memory approval session duration in minutes.
  ///
  /// `0` means ask every time. The duration setting is persisted, but the
  /// approval session itself must remain process-local.
  Future<int?> getApprovalSessionDurationMinutes();

  /// Sets the approval session duration in minutes.
  Future<void> setApprovalSessionDurationMinutes(int minutes);

  /// Reads a full identity record including secret.
  Future<VaultIdentityRecord?> getIdentityRecord(String localId);

  /// Saves an identity record.
  Future<void> saveIdentityRecord(VaultIdentityRecord record);

  /// Deletes an identity record by its local ID.
  Future<void> deleteIdentity(String localId);

  /// Clears all vault data.
  Future<void> clearAll();
}
