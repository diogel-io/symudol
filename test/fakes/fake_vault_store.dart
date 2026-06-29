import 'dart:typed_data';

import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_crypto_service.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';

class FakeVaultStore implements VaultStore {
  String? _version;
  Uint8List? _kdfSalt;
  VaultKdfParams? _kdfParams;
  String? _wrappedDek;
  int _failedUnlockAttempts = 0;
  DateTime? _lockoutUntil;
  String? _activeIdentityId;
  int? _inactivityTimeout;
  int? _backgroundLockDelayMinutes;
  int? _approvalSessionDurationMinutes;
  final Map<String, VaultIdentityRecord> _identities = {};

  /// Simulates a storage error when set to true.
  bool shouldThrowStorageError = false;

  /// Simulates a missing vault (no wrapped DEK) when set to true.
  bool simulateMissingVault = false;

  /// Simulates a duplicate identity error when set to true.
  bool shouldThrowDuplicateIdentityError = false;

  void _checkError() {
    if (shouldThrowStorageError) {
      throw const VaultStorageException('Simulated storage error');
    }
  }

  @override
  Future<String?> getVersion() async {
    _checkError();
    return _version;
  }

  @override
  Future<void> setVersion(String version) async {
    _checkError();
    _version = version;
  }

  @override
  Future<Uint8List?> getKdfSalt() async {
    _checkError();
    if (simulateMissingVault) return null;
    return _kdfSalt;
  }

  @override
  Future<void> setKdfSalt(Uint8List salt) async {
    _checkError();
    _kdfSalt = salt;
  }

  @override
  Future<VaultKdfParams?> getKdfParams() async {
    _checkError();
    if (simulateMissingVault) return null;
    return _kdfParams;
  }

  @override
  Future<void> setKdfParams(VaultKdfParams params) async {
    _checkError();
    _kdfParams = params;
  }

  @override
  Future<String?> getWrappedDek() async {
    _checkError();
    if (simulateMissingVault) return null;
    return _wrappedDek;
  }

  @override
  Future<void> setWrappedDek(String wrappedDek) async {
    _checkError();
    _wrappedDek = wrappedDek;
  }

  @override
  Future<int> getFailedUnlockAttempts() async {
    _checkError();
    return _failedUnlockAttempts;
  }

  @override
  Future<void> setFailedUnlockAttempts(int attempts) async {
    _checkError();
    _failedUnlockAttempts = attempts;
  }

  @override
  Future<DateTime?> getLockoutUntil() async {
    _checkError();
    return _lockoutUntil;
  }

  @override
  Future<void> setLockoutUntil(DateTime? until) async {
    _checkError();
    _lockoutUntil = until;
  }

  @override
  Future<String?> getActiveIdentityId() async {
    _checkError();
    return _activeIdentityId;
  }

  @override
  Future<void> setActiveIdentityId(String id) async {
    _checkError();
    _activeIdentityId = id;
  }

  @override
  Future<int?> getInactivityTimeout() async {
    _checkError();
    return _inactivityTimeout;
  }

  @override
  Future<void> setInactivityTimeout(int minutes) async {
    _checkError();
    _inactivityTimeout = minutes;
  }

  @override
  Future<int?> getBackgroundLockDelayMinutes() async {
    _checkError();
    return _backgroundLockDelayMinutes;
  }

  @override
  Future<void> setBackgroundLockDelayMinutes(int minutes) async {
    _checkError();
    _backgroundLockDelayMinutes = minutes;
  }

  @override
  Future<int?> getApprovalSessionDurationMinutes() async {
    _checkError();
    return _approvalSessionDurationMinutes;
  }

  @override
  Future<void> setApprovalSessionDurationMinutes(int minutes) async {
    _checkError();
    _approvalSessionDurationMinutes = minutes;
  }

  @override
  Future<List<VaultIdentityRecord>> getIdentities() async {
    _checkError();
    return _identities.values.toList();
  }

  @override
  Future<VaultIdentityRecord?> getIdentityRecord(String localId) async {
    _checkError();
    return _identities[localId];
  }

  @override
  Future<void> saveIdentityRecord(VaultIdentityRecord record) async {
    _checkError();
    if (shouldThrowDuplicateIdentityError &&
        _identities.containsKey(record.identityId)) {
      throw const VaultStorageException(
        'Already exists: Simulated duplicate identity error',
      );
    }
    _identities[record.identityId] = record;
  }

  @override
  Future<void> deleteIdentity(String localId) async {
    _checkError();
    _identities.remove(localId);
  }

  @override
  Future<void> clearAll() async {
    _checkError();
    _version = null;
    _kdfSalt = null;
    _kdfParams = null;
    _wrappedDek = null;
    _failedUnlockAttempts = 0;
    _lockoutUntil = null;
    _activeIdentityId = null;
    _inactivityTimeout = null;
    _backgroundLockDelayMinutes = null;
    _approvalSessionDurationMinutes = null;
    _identities.clear();
  }
}
