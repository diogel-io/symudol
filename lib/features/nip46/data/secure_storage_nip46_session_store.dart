import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/nip46_session.dart';
import '../domain/nip46_session_store.dart';

class SecureStorageNip46SessionStore implements Nip46SessionStore {
  static const _key = 'nip46_sessions_v1';

  final FlutterSecureStorage _storage;
  List<Nip46Session>? _cache;
  Completer<void>? _initCompleter;

  SecureStorageNip46SessionStore({FlutterSecureStorage? storage})
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
          _cache = decoded
              .whereType<Map>()
              .map((item) => Nip46Session.fromJson(item.cast()))
              .toList();
        } else {
          _cache = [];
        }
      }
      debugPrint(
        'SecureStorageNip46SessionStore: loaded ${_cache?.length ?? 0} sessions',
      );
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
  Future<List<Nip46Session>> listSessions() async {
    await _ensureInitialized();
    return List.unmodifiable(_cache!);
  }

  @override
  Future<void> saveSession(Nip46Session session) async {
    await _ensureInitialized();
    final next = [
      for (final item in _cache!)
        if (item.id != session.id) item,
      session,
    ];
    _cache = next;
    await _write(next);
  }

  @override
  Future<void> deleteSession(String id) async {
    await _ensureInitialized();
    final next = _cache!.where((s) => s.id != id).toList();
    _cache = next;
    await _write(next);
  }

  @override
  Future<void> clearAll() async {
    _cache = [];
    await _storage.delete(key: _key);
  }

  Future<void> _write(List<Nip46Session> sessions) async {
    final payload = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await _storage.write(key: _key, value: payload);
  }
}
