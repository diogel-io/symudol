import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/nip55_client_permission.dart';
import '../domain/nip55_permission_store.dart';

class SecureStorageNip55PermissionStore implements Nip55PermissionStore {
  static const _key = 'nip55_permission_grants_v1';

  final FlutterSecureStorage _storage;

  SecureStorageNip55PermissionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<List<Nip55PermissionGrant>> listGrants() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Nip55PermissionGrant.fromJson(item.cast()))
        .toList(growable: false);
  }

  @override
  Future<void> saveGrant(Nip55PermissionGrant grant) async {
    final existing = await listGrants();
    final next = [
      for (final item in existing)
        if (item.id != grant.id) item,
      grant,
    ];
    await _write(next);
  }

  @override
  Future<void> deleteGrant(String id) async {
    final existing = await listGrants();
    await _write(existing.where((grant) => grant.id != id).toList());
  }

  @override
  Future<void> deleteAllForPackage(String packageName) async {
    final existing = await listGrants();
    await _write(
      existing.where((grant) => grant.packageName != packageName).toList(),
    );
  }

  @override
  Future<void> clearAll() => _storage.delete(key: _key);

  Future<void> _write(List<Nip55PermissionGrant> grants) {
    final payload = jsonEncode(grants.map((grant) => grant.toJson()).toList());
    return _storage.write(key: _key, value: payload);
  }
}
