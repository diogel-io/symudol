import 'dart:typed_data';

import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_crypto_service.dart';

abstract class VaultStore {
  /// Returns the current version of the storage schema.
  Future<String?> getVersion();

  /// Sets the storage schema version.
  Future<void> setVersion(String version);

  /// Reads the Argon2id salt used to derive the key-encryption key (KEK)
  /// from the user's PIN. A non-null value indicates a vault exists.
  Future<Uint8List?> getKdfSalt();

  /// Sets the Argon2id salt.
  Future<void> setKdfSalt(Uint8List salt);

  /// Reads the Argon2id parameters used to derive the KEK.
  Future<VaultKdfParams?> getKdfParams();

  /// Sets the Argon2id parameters.
  Future<void> setKdfParams(VaultKdfParams params);

  /// Reads the wrapped (encrypted) data-encryption key (DEK).
  Future<String?> getWrappedDek();

  /// Sets the wrapped data-encryption key.
  Future<void> setWrappedDek(String wrappedDek);

  /// Reads the number of consecutive failed unlock attempts.
  Future<int> getFailedUnlockAttempts();

  /// Sets the number of consecutive failed unlock attempts.
  Future<void> setFailedUnlockAttempts(int attempts);

  /// Reads the timestamp until which unlocking is locked out, if any.
  Future<DateTime?> getLockoutUntil();

  /// Sets the timestamp until which unlocking is locked out.
  ///
  /// Pass `null` to clear the lockout.
  Future<void> setLockoutUntil(DateTime? until);

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
