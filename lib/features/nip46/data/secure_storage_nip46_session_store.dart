import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:symudol/app/diogel_log.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:symudol/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';

import '../domain/nip46_session.dart';
import '../domain/nip46_session_store.dart';

/// Sessions in `flutter_secure_storage`, with each session's private key and
/// single-use secret encrypted under the vault's NIP-46 storage key (#32).
/// The rest of a session, such as its grants and relays, is stored as is.
class SecureStorageNip46SessionStore implements Nip46SessionStore {
  static const _key = 'nip46_sessions_v2';
  // Sessions stored before #32, keys in the clear. Moved to [_key] on the
  // first load with a key, then deleted.
  static const _legacyKey = 'nip46_sessions_v1';
  static const _runInBackgroundKey = 'nip46_run_in_background_v1';

  // The JSON fields that are encrypted, and the field that holds them.
  static const _secretFields = ['remoteSignerPrivkey', 'pendingSecret'];
  static const _secretsField = 'secrets';

  final FlutterSecureStorage _storage;
  final VaultCryptoService _crypto;
  List<Nip46Session>? _cache;
  Future<void>? _loading;
  Uint8List? _storageKey;
  // A legacy value is still stored: deleted after the next write.
  bool _legacyStored = false;

  SecureStorageNip46SessionStore({
    FlutterSecureStorage? storage,
    VaultCryptoService crypto = const PointyCastleVaultCryptoService(),
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _crypto = crypto;

  @override
  void useStorageKey(Uint8List key) {
    _clearStorageKey();
    _storageKey = Uint8List.fromList(key);
  }

  Future<void> _ensureInitialized() {
    if (_cache != null) return Future.value();
    // One load at a time; a failed one is retried by the next call.
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _key);
    if (raw != null) {
      _cache = [
        for (final entry in _decodeList(raw))
          Nip46Session.fromJson(_openSecrets(entry)),
      ];
      // A move whose delete failed, or was cut short, left the keys in the
      // clear: delete them now, or after the next write.
      if (await _storage.read(key: _legacyKey) != null) {
        _legacyStored = true;
        try {
          await _storage.delete(key: _legacyKey);
          _legacyStored = false;
        } catch (e) {
          diogelLog(
            'SecureStorageNip46SessionStore: could not delete old sessions',
            error: e,
          );
        }
      }
    } else {
      await _loadLegacy();
    }
    diogelLog(
      'SecureStorageNip46SessionStore: loaded ${_cache?.length ?? 0} sessions',
    );
  }

  /// Reads sessions stored before #32 and stores them encrypted. The legacy
  /// value is deleted only after that write succeeds, so a failed write
  /// loses nothing: it is tried again on the next save.
  Future<void> _loadLegacy() async {
    final raw = await _storage.read(key: _legacyKey);
    final entries = raw == null
        ? const <Map<String, Object?>>[]
        : _decodeList(raw);
    if (entries.isNotEmpty && _storageKey == null) {
      throw const Nip46StoreLockedException();
    }
    _cache = [for (final entry in entries) Nip46Session.fromJson(entry)];
    if (raw == null) return;
    _legacyStored = true;
    try {
      await _write(_cache!);
    } catch (e) {
      diogelLog(
        'SecureStorageNip46SessionStore: could not encrypt stored sessions',
        error: e,
      );
    }
  }

  static List<Map<String, Object?>> _decodeList(String raw) {
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map) item.cast<String, Object?>(),
    ];
  }

  /// Puts back the session's decrypted secrets. They must belong to the same
  /// session, so a value copied from another entry is refused.
  Map<String, Object?> _openSecrets(Map<String, Object?> entry) {
    final key = _storageKey;
    if (key == null) throw const Nip46StoreLockedException();
    final sealed = entry[_secretsField];
    if (sealed is! String) {
      throw const FormatException('NIP-46 session has no secrets');
    }
    final secrets = (jsonDecode(_crypto.decrypt(sealed, key)) as Map)
        .cast<String, Object?>();
    if (secrets['sessionId'] != entry['id']) {
      throw const VaultCryptoTamperException(
        'NIP-46 secrets belong to another session',
      );
    }
    return {
      for (final MapEntry(key: name, :value) in entry.entries)
        if (name != _secretsField) name: value,
      for (final field in _secretFields) field: secrets[field],
    };
  }

  Map<String, Object?> _sealSecrets(Nip46Session session, Uint8List key) {
    final json = session.toJson();
    final secrets = {
      'sessionId': session.id,
      for (final field in _secretFields) field: json[field],
    };
    return {
      for (final MapEntry(key: name, :value) in json.entries)
        if (!_secretFields.contains(name)) name: value,
      _secretsField: _crypto.encrypt(jsonEncode(secrets), key),
    };
  }

  @override
  Future<List<Nip46Session>> listSessions() async {
    await _ensureInitialized();
    return List.unmodifiable(_cache!);
  }

  @override
  Future<int> countSessions() async {
    final cache = _cache;
    if (cache != null) return cache.length;
    final raw =
        await _storage.read(key: _key) ?? await _storage.read(key: _legacyKey);
    return raw == null ? 0 : _decodeList(raw).length;
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
    _clearStorageKey();
    await _storage.delete(key: _key);
    await _storage.delete(key: _legacyKey);
    _legacyStored = false;
    await _storage.delete(key: _runInBackgroundKey);
  }

  @override
  Future<bool> getRunInBackground() async =>
      await _storage.read(key: _runInBackgroundKey) == 'true';

  @override
  Future<void> setRunInBackground(bool value) =>
      _storage.write(key: _runInBackgroundKey, value: value.toString());

  Future<void> _write(List<Nip46Session> sessions) async {
    final key = _storageKey;
    if (key == null && sessions.isNotEmpty) {
      throw const Nip46StoreLockedException();
    }
    final payload = jsonEncode([
      for (final session in sessions) _sealSecrets(session, key!),
    ]);
    await _storage.write(key: _key, value: payload);
    if (_legacyStored) {
      await _storage.delete(key: _legacyKey);
      _legacyStored = false;
    }
  }

  void _clearStorageKey() {
    final key = _storageKey;
    if (key != null) key.fillRange(0, key.length, 0);
    _storageKey = null;
  }
}
