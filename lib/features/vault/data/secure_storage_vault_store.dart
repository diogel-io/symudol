import 'dart:convert';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageVaultStore implements VaultStore {
  final FlutterSecureStorage _storage;

  static const String _keyVersion = 'vault_version';
  static const String _keySentinel = 'vault_sentinel';
  static const String _keyActiveIdentityId = 'active_identity_id';
  static const String _keyIdentitiesPrefix = 'identity_';

  SecureStorageVaultStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> getVersion() => _storage.read(key: _keyVersion);

  @override
  Future<void> setVersion(String version) =>
      _storage.write(key: _keyVersion, value: version);

  @override
  Future<String?> getSentinel() => _storage.read(key: _keySentinel);

  @override
  Future<void> setSentinel(String sentinel) =>
      _storage.write(key: _keySentinel, value: sentinel);

  @override
  Future<String?> getActiveIdentityId() =>
      _storage.read(key: _keyActiveIdentityId);

  @override
  Future<void> setActiveIdentityId(String id) =>
      _storage.write(key: _keyActiveIdentityId, value: id);

  @override
  Future<List<VaultIdentity>> getIdentities() async {
    final all = await _storage.readAll();
    return all.entries
        .where((e) => e.key.startsWith(_keyIdentitiesPrefix))
        .map((e) => VaultIdentity.fromJson(jsonDecode(e.value)))
        .toList();
  }

  @override
  Future<void> saveIdentity(VaultIdentity identity) async {
    final key = '$_keyIdentitiesPrefix${identity.localId}';
    await _storage.write(
      key: key,
      value: jsonEncode(identity.toJson()),
    );
  }

  @override
  Future<void> deleteIdentity(String localId) =>
      _storage.delete(key: '$_keyIdentitiesPrefix$localId');

  @override
  Future<void> clearAll() => _storage.deleteAll();
}
