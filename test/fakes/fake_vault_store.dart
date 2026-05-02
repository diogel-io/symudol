import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';

class FakeVaultStore implements VaultStore {
  String? _version;
  String? _sentinel;
  String? _activeIdentityId;
  int? _inactivityTimeout;
  int? _backgroundLockDelayMinutes;
  final Map<String, VaultIdentityRecord> _identities = {};

  /// Simulates a storage error when set to true.
  bool shouldThrowStorageError = false;

  /// Simulates a missing vault (sentinel is null) when set to true.
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
  Future<String?> getSentinel() async {
    _checkError();
    if (simulateMissingVault) return null;
    return _sentinel;
  }

  @override
  Future<void> setSentinel(String sentinel) async {
    _checkError();
    _sentinel = sentinel;
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
    _sentinel = null;
    _activeIdentityId = null;
    _inactivityTimeout = null;
    _backgroundLockDelayMinutes = null;
    _identities.clear();
  }
}
