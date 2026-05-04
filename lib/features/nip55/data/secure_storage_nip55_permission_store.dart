import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/nip55_client_permission.dart';
import '../domain/nip55_permission_store.dart';

class SecureStorageNip55PermissionStore implements Nip55PermissionStore {
  static const _key = 'nip55_permission_grants_v1';

  final FlutterSecureStorage _storage;
  List<Nip55PermissionGrant>? _cache;
  Completer<void>? _initCompleter;

  SecureStorageNip55PermissionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<void> _ensureInitialized() async {
    if (_cache != null) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.trim().isEmpty) {
        _cache = [];
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _cache =
              decoded
                  .whereType<Map>()
                  .map((item) => Nip55PermissionGrant.fromJson(item.cast()))
                  .toList();
        } else {
          _cache = [];
        }
      }
      _initCompleter!.complete();
    } catch (e) {
      _cache = [];
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  @override
  Future<List<Nip55PermissionGrant>> listGrants() async {
    await _ensureInitialized();
    return List.unmodifiable(_cache!);
  }

  @override
  Future<void> saveGrant(Nip55PermissionGrant grant) async {
    await _ensureInitialized();
    final next = [
      for (final item in _cache!)
        if (item.id != grant.id) item,
      grant,
    ];
    _cache = next;
    await _write(next);
  }

  @override
  Future<void> deleteGrant(String id) async {
    await _ensureInitialized();
    final next = _cache!.where((grant) => grant.id != id).toList();
    _cache = next;
    await _write(next);
  }

  @override
  Future<void> deleteAllForPackage(String packageName) async {
    await _ensureInitialized();
    final next =
        _cache!.where((grant) => grant.packageName != packageName).toList();
    _cache = next;
    await _write(next);
  }

  @override
  Future<void> clearAll() async {
    _cache = [];
    await _storage.delete(key: _key);
  }

  Future<void> _write(List<Nip55PermissionGrant> grants) {
    final payload = jsonEncode(grants.map((grant) => grant.toJson()).toList());
    return _storage.write(key: _key, value: payload);
  }
}
