import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';

class FakeVaultStore implements VaultStore {
  String? _version;
  String? _sentinel;
  String? _activeIdentityId;
  final Map<String, VaultIdentity> _identities = {};

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
  Future<List<VaultIdentity>> getIdentities() async {
    _checkError();
    return _identities.values.toList();
  }

  @override
  Future<void> saveIdentity(VaultIdentity identity) async {
    _checkError();
    if (shouldThrowDuplicateIdentityError && _identities.containsKey(identity.localId)) {
      throw const VaultStorageException('Simulated duplicate identity error');
    }
    _identities[identity.localId] = identity;
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
    _identities.clear();
  }
}
