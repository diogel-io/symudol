import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nip55_native_mirror_sync.dart';
import '../domain/nip55_client_permission.dart';
import '../domain/nip55_permission_store.dart';

class SecureStorageNip55PermissionStore implements Nip55PermissionStore {
  static const _key = 'nip55_permission_grants_v1';

  final FlutterSecureStorage _storage;
  final Nip55NativeMirrorSync? _nativeSync;
  List<Nip55PermissionGrant>? _cache;
  Completer<void>? _initCompleter;

  SecureStorageNip55PermissionStore({FlutterSecureStorage? storage, Nip55NativeMirrorSync? nativeSync})
    : _storage = storage ?? const FlutterSecureStorage(),
      _nativeSync = nativeSync;

  /// Force sync current grants to native mirror. Called on startup.
  Future<void> syncToNative() async {
    await _ensureInitialized();
    debugPrint('SecureStorageNip55PermissionStore: syncToNative: ${_cache?.length ?? 0} grants');
    await _nativeSync?.syncGrants(_cache ?? []);
  }

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
          final loaded =
              decoded
                  .whereType<Map>()
                  .map((item) => Nip55PermissionGrant.fromJson(item.cast()))
                  .toList();
          // Broad allows saved before #5 are dropped, and the stored list is
          // rewritten without them, so Trusted apps and the native mirror
          // agree with what can actually be remembered.
          _cache = loaded.where((grant) => grant.isRememberable).toList();
          if (_cache!.length != loaded.length) {
            debugPrint(
              'SecureStorageNip55PermissionStore: dropped '
              '${loaded.length - _cache!.length} broad allow grant(s)',
            );
            await _storage.write(
              key: _key,
              value: jsonEncode(_cache!.map((grant) => grant.toJson()).toList()),
            );
          }
        } else {
          _cache = [];
        }
      }
      // Sync loaded grants to native mirror so ContentProvider can use them
      // immediately on startup without waiting for a grant write.
      debugPrint('SecureStorageNip55PermissionStore: loaded ${_cache?.length ?? 0} grants, syncing to native mirror');
      await _nativeSync?.syncGrants(_cache ?? []);
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
    // Never stored, whichever caller asks (#5).
    if (!grant.isRememberable) return;
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
    await _nativeSync?.syncGrants([]);
  }

  Future<void> _write(List<Nip55PermissionGrant> grants) async {
    final payload = jsonEncode(grants.map((grant) => grant.toJson()).toList());
    await _storage.write(key: _key, value: payload);
    // Sync to native mirror for ContentProvider auto-approve
    await _nativeSync?.syncGrants(grants);
  }
}
