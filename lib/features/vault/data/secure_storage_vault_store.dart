import 'dart:convert';
import 'dart:typed_data';

import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageVaultStore implements VaultStore {
  final FlutterSecureStorage _storage;

  static const String _keyVersion = 'vault_version';
  static const String _keyKdfSalt = 'vault_kdf_salt';
  static const String _keyKdfParams = 'vault_kdf_params';
  static const String _keyWrappedDek = 'vault_wrapped_dek';
  static const String _keyFailedUnlockAttempts = 'vault_failed_attempts';
  static const String _keyLockoutUntil = 'vault_lockout_until';
  static const String _keyActiveIdentityId = 'active_identity_id';
  static const String _keyInactivityTimeout = 'inactivity_timeout';
  static const String _keyBackgroundLockDelay = 'background_lock_delay_minutes';
  static const String _keyApprovalSessionDuration =
      'approval_session_duration_minutes';
  static const String _keyIdentitiesPrefix = 'identity_';

  // In-memory cache
  final Map<String, String?> _cache = {};

  SecureStorageVaultStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> _readCached(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final value = await _storage.read(key: key);
    _cache[key] = value;
    return value;
  }

  Future<void> _writeCached(String key, String value) async {
    _cache[key] = value;
    await _storage.write(key: key, value: value);
  }

  @override
  Future<String?> getVersion() => _readCached(_keyVersion);

  @override
  Future<void> setVersion(String version) => _writeCached(_keyVersion, version);

  @override
  Future<Uint8List?> getKdfSalt() async {
    final value = await _readCached(_keyKdfSalt);
    return value != null ? base64Decode(value) : null;
  }

  @override
  Future<void> setKdfSalt(Uint8List salt) =>
      _writeCached(_keyKdfSalt, base64Encode(salt));

  @override
  Future<VaultKdfParams?> getKdfParams() async {
    final value = await _readCached(_keyKdfParams);
    if (value == null) return null;
    return VaultKdfParams.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> setKdfParams(VaultKdfParams params) =>
      _writeCached(_keyKdfParams, jsonEncode(params.toJson()));

  @override
  Future<String?> getWrappedDek() => _readCached(_keyWrappedDek);

  @override
  Future<void> setWrappedDek(String wrappedDek) =>
      _writeCached(_keyWrappedDek, wrappedDek);

  @override
  Future<int> getFailedUnlockAttempts() async {
    final value = await _readCached(_keyFailedUnlockAttempts);
    return value != null ? int.parse(value) : 0;
  }

  @override
  Future<void> setFailedUnlockAttempts(int attempts) =>
      _writeCached(_keyFailedUnlockAttempts, attempts.toString());

  @override
  Future<DateTime?> getLockoutUntil() async {
    final value = await _readCached(_keyLockoutUntil);
    if (value == null || value.isEmpty) return null;
    return DateTime.parse(value);
  }

  @override
  Future<void> setLockoutUntil(DateTime? until) =>
      _writeCached(_keyLockoutUntil, until?.toIso8601String() ?? '');

  @override
  Future<String?> getActiveIdentityId() => _readCached(_keyActiveIdentityId);

  @override
  Future<void> setActiveIdentityId(String id) =>
      _writeCached(_keyActiveIdentityId, id);

  @override
  Future<int?> getInactivityTimeout() async {
    final value = await _readCached(_keyInactivityTimeout);
    return value != null ? int.tryParse(value) : null;
  }

  @override
  Future<void> setInactivityTimeout(int minutes) =>
      _writeCached(_keyInactivityTimeout, minutes.toString());

  @override
  Future<int?> getBackgroundLockDelayMinutes() async {
    final value = await _readCached(_keyBackgroundLockDelay);
    return value != null ? int.tryParse(value) : null;
  }

  @override
  Future<void> setBackgroundLockDelayMinutes(int minutes) =>
      _writeCached(_keyBackgroundLockDelay, minutes.toString());

  @override
  Future<int?> getApprovalSessionDurationMinutes() async {
    final value = await _readCached(_keyApprovalSessionDuration);
    return value != null ? int.tryParse(value) : null;
  }

  @override
  Future<void> setApprovalSessionDurationMinutes(int minutes) => _writeCached(
    _keyApprovalSessionDuration,
    minutes.toString(),
  );

  @override
  Future<List<VaultIdentityRecord>> getIdentities() async {
    // We don't cache all identities in a single map key yet,
    // but readAll is only called here.
    final all = await _storage.readAll();
    // Sync cache with readAll results
    all.forEach((key, value) {
      _cache[key] = value;
    });
    return all.entries
        .where((e) => e.key.startsWith(_keyIdentitiesPrefix))
        .map((e) => VaultIdentityRecord.fromJson(jsonDecode(e.value)))
        .toList();
  }

  @override
  Future<VaultIdentityRecord?> getIdentityRecord(String localId) async {
    final key = '$_keyIdentitiesPrefix$localId';
    final data = await _readCached(key);
    if (data == null) return null;
    return VaultIdentityRecord.fromJson(jsonDecode(data));
  }

  @override
  Future<void> saveIdentityRecord(VaultIdentityRecord record) async {
    final key = '$_keyIdentitiesPrefix${record.identityId}';
    await _writeCached(key, jsonEncode(record.toJson()));
  }

  @override
  Future<void> deleteIdentity(String localId) async {
    final key = '$_keyIdentitiesPrefix$localId';
    _cache.remove(key);
    await _storage.delete(key: key);
  }

  @override
  Future<void> clearAll() async {
    _cache.clear();
    await _storage.deleteAll();
  }
}
