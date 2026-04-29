import 'dart:convert';
import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageVaultStore implements VaultStore {
  final FlutterSecureStorage _storage;

  static const String _keyVersion = 'vault_version';
  static const String _keySentinel = 'vault_sentinel';
  static const String _keyActiveIdentityId = 'active_identity_id';
  static const String _keyInactivityTimeout = 'inactivity_timeout';
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
  Future<int?> getInactivityTimeout() async {
    final value = await _storage.read(key: _keyInactivityTimeout);
    return value != null ? int.tryParse(value) : null;
  }

  @override
  Future<void> setInactivityTimeout(int minutes) =>
      _storage.write(key: _keyInactivityTimeout, value: minutes.toString());

  @override
  Future<List<VaultIdentityRecord>> getIdentities() async {
    final all = await _storage.readAll();
    return all.entries
        .where((e) => e.key.startsWith(_keyIdentitiesPrefix))
        .map((e) => VaultIdentityRecord.fromJson(jsonDecode(e.value)))
        .toList();
  }

  @override
  Future<VaultIdentityRecord?> getIdentityRecord(String localId) async {
    final data = await _storage.read(key: '$_keyIdentitiesPrefix$localId');
    if (data == null) return null;
    return VaultIdentityRecord.fromJson(jsonDecode(data));
  }

  @override
  Future<void> saveIdentityRecord(VaultIdentityRecord record) async {
    final key = '$_keyIdentitiesPrefix${record.identityId}';
    await _storage.write(
      key: key,
      value: jsonEncode(record.toJson()),
    );
  }

  @override
  Future<void> deleteIdentity(String localId) =>
      _storage.delete(key: '$_keyIdentitiesPrefix$localId');

  @override
  Future<void> clearAll() => _storage.deleteAll();
}
