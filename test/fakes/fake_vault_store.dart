import 'dart:typed_data';

import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/biometric_vault.dart';
import 'package:symudol/features/vault/domain/monotonic_clock.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_key_envelope.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:symudol/features/vault/domain/vault_store.dart';

class FakeVaultStore implements VaultStore {
  String? _version;
  Uint8List? _kdfSalt;
  VaultKdfParams? _kdfParams;
  String? _wrappedDek;
  VaultKeyEnvelope? _keyEnvelope;
  int _failedUnlockAttempts = 0;
  VaultLockout? _lockout;
  DateTime? _legacyLockoutUntil;
  int? _wipeAfterFailures;
  BiometricWrap? _biometricWrap;
  MonotonicInstant? _pinVerifiedAt;
  String? _activeIdentityId;
  int? _inactivityTimeout;
  int? _backgroundLockDelayMinutes;
  int? _approvalSessionDurationMinutes;
  final Map<String, VaultIdentityRecord> _identities = {};

  /// Simulates a storage error when set to true.
  bool shouldThrowStorageError = false;

  /// Simulates a missing vault (no wrapped DEK) when set to true.
  bool simulateMissingVault = false;

  /// Simulates a storage error from [clearAll] only when set to true.
  bool shouldThrowOnClearAll = false;

  /// Simulates a failed write from [setKeyEnvelope] only when set to true.
  bool shouldThrowOnSetKeyEnvelope = false;

  /// How many times [setKeyEnvelope] wrote an envelope.
  int keyEnvelopeWrites = 0;

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

  // The three separate keys vaults used before #16. Not part of VaultStore:
  // tests use them to set up a legacy vault, or just a vault sentinel.

  Future<Uint8List?> getKdfSalt() async {
    _checkError();
    if (simulateMissingVault) return null;
    return _kdfSalt;
  }

  Future<void> setKdfSalt(Uint8List salt) async {
    _checkError();
    _kdfSalt = salt;
  }

  Future<void> setKdfParams(VaultKdfParams params) async {
    _checkError();
    _kdfParams = params;
  }

  Future<void> setWrappedDek(String wrappedDek) async {
    _checkError();
    _wrappedDek = wrappedDek;
  }

  /// Whether the legacy separate keys are still stored.
  bool get hasLegacyKeyFields =>
      _kdfSalt != null || _kdfParams != null || _wrappedDek != null;

  /// The envelope as stored, without the legacy fallback.
  VaultKeyEnvelope? get storedKeyEnvelope => _keyEnvelope;

  Future<void> setLegacyLockoutUntil(DateTime? until) async {
    _checkError();
    _legacyLockoutUntil = until;
  }

  @override
  Future<VaultKeyEnvelope?> getKeyEnvelope() async {
    _checkError();
    if (simulateMissingVault) return null;
    final envelope = _keyEnvelope;
    if (envelope != null) return envelope;
    final salt = _kdfSalt;
    final params = _kdfParams;
    final wrappedDek = _wrappedDek;
    if (salt == null || params == null || wrappedDek == null) return null;
    return VaultKeyEnvelope(salt: salt, params: params, wrappedDek: wrappedDek);
  }

  @override
  Future<void> setKeyEnvelope(VaultKeyEnvelope envelope) async {
    _checkError();
    if (shouldThrowOnSetKeyEnvelope) {
      throw const VaultStorageException('Simulated setKeyEnvelope error');
    }
    _keyEnvelope = envelope;
    keyEnvelopeWrites++;
    _kdfSalt = null;
    _kdfParams = null;
    _wrappedDek = null;
  }

  @override
  Future<String?> getWrappedDek() async {
    _checkError();
    if (simulateMissingVault) return null;
    return _keyEnvelope?.wrappedDek ?? _wrappedDek;
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
  Future<VaultLockout?> getLockout() async {
    _checkError();
    return _lockout;
  }

  @override
  Future<void> setLockout(VaultLockout? lockout) async {
    _checkError();
    _lockout = lockout;
  }

  @override
  Future<DateTime?> getLegacyLockoutUntil() async {
    _checkError();
    return _legacyLockoutUntil;
  }

  @override
  Future<void> deleteLegacyLockoutUntil() async {
    _checkError();
    _legacyLockoutUntil = null;
  }

  @override
  Future<int?> getWipeAfterFailures() async {
    _checkError();
    return _wipeAfterFailures;
  }

  @override
  Future<void> setWipeAfterFailures(int? attempts) async {
    _checkError();
    _wipeAfterFailures = attempts;
  }

  @override
  Future<BiometricWrap?> getBiometricWrap() async {
    _checkError();
    return _biometricWrap;
  }

  @override
  Future<void> setBiometricWrap(BiometricWrap? wrap) async {
    _checkError();
    _biometricWrap = wrap;
  }

  @override
  Future<MonotonicInstant?> getPinVerifiedAt() async {
    _checkError();
    return _pinVerifiedAt;
  }

  @override
  Future<void> setPinVerifiedAt(MonotonicInstant instant) async {
    _checkError();
    _pinVerifiedAt = instant;
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
    if (shouldThrowOnClearAll) {
      throw const VaultStorageException('Simulated clearAll error');
    }
    _version = null;
    _kdfSalt = null;
    _kdfParams = null;
    _wrappedDek = null;
    _keyEnvelope = null;
    _failedUnlockAttempts = 0;
    _lockout = null;
    _legacyLockoutUntil = null;
    _wipeAfterFailures = null;
    _biometricWrap = null;
    _pinVerifiedAt = null;
    _activeIdentityId = null;
    _inactivityTimeout = null;
    _backgroundLockDelayMinutes = null;
    _approvalSessionDurationMinutes = null;
    _identities.clear();
  }
}
