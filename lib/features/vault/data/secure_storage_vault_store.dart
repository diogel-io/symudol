import 'dart:convert';

import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/biometric_vault.dart';
import 'package:symudol/features/vault/domain/monotonic_clock.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_key_envelope.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:symudol/features/vault/domain/vault_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageVaultStore implements VaultStore {
  final FlutterSecureStorage _storage;

  static const String _keyVersion = 'vault_version';
  static const String _keyKeyEnvelope = 'vault_key_envelope';
  // Before #16 the envelope was three separate keys.
  static const String _keyLegacyKdfSalt = 'vault_kdf_salt';
  static const String _keyLegacyKdfParams = 'vault_kdf_params';
  static const String _keyLegacyWrappedDek = 'vault_wrapped_dek';
  static const String _keyFailedUnlockAttempts = 'vault_failed_attempts';
  static const String _keyLockout = 'vault_lockout';
  static const String _keyLegacyLockoutUntil = 'vault_lockout_until';
  static const String _keyWipeAfterFailures = 'vault_wipe_after_failures';
  static const String _keyBiometricWrap = 'vault_biometric_wrap';
  static const String _keyPinVerifiedAt = 'vault_pin_verified_at';
  static const String _keyActiveIdentityId = 'active_identity_id';
  static const String _keyInactivityTimeout = 'inactivity_timeout';
  static const String _keyBackgroundLockDelay = 'background_lock_delay_minutes';
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

  /// Caches [value] only once it is written, so a failed write is not read
  /// back as if it had worked.
  Future<void> _writeCached(String key, String value) async {
    await _storage.write(key: key, value: value);
    _cache[key] = value;
  }

  Future<void> _deleteCached(String key) async {
    await _storage.delete(key: key);
    _cache[key] = null;
  }

  @override
  Future<String?> getVersion() => _readCached(_keyVersion);

  @override
  Future<void> setVersion(String version) => _writeCached(_keyVersion, version);

  @override
  Future<VaultKeyEnvelope?> getKeyEnvelope() async {
    final value = await _readCached(_keyKeyEnvelope);
    if (value != null) {
      return VaultKeyEnvelope.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    }
    final salt = await _readCached(_keyLegacyKdfSalt);
    final params = await _readCached(_keyLegacyKdfParams);
    final wrappedDek = await _readCached(_keyLegacyWrappedDek);
    if (salt == null || params == null || wrappedDek == null) return null;
    return VaultKeyEnvelope(
      salt: base64Decode(salt),
      params: VaultKdfParams.fromJson(
        jsonDecode(params) as Map<String, dynamic>,
      ),
      wrappedDek: wrappedDek,
    );
  }

  @override
  Future<void> setKeyEnvelope(VaultKeyEnvelope envelope) async {
    await _writeCached(_keyKeyEnvelope, jsonEncode(envelope.toJson()));
    // Only once the envelope is safely written: reads prefer it, so a delete
    // cut short leaves nothing that is read.
    for (final key in const [
      _keyLegacyKdfSalt,
      _keyLegacyKdfParams,
      _keyLegacyWrappedDek,
    ]) {
      if (await _readCached(key) != null) await _deleteCached(key);
    }
  }

  @override
  Future<String?> getWrappedDek() async {
    final value = await _readCached(_keyKeyEnvelope);
    if (value != null) {
      return (jsonDecode(value) as Map<String, dynamic>)['wrappedDek']
          as String?;
    }
    return _readCached(_keyLegacyWrappedDek);
  }

  @override
  Future<int> getFailedUnlockAttempts() async {
    final value = await _readCached(_keyFailedUnlockAttempts);
    return value != null ? int.parse(value) : 0;
  }

  @override
  Future<void> setFailedUnlockAttempts(int attempts) =>
      _writeCached(_keyFailedUnlockAttempts, attempts.toString());

  @override
  Future<VaultLockout?> getLockout() async {
    final value = await _readCached(_keyLockout);
    if (value == null || value.isEmpty) return null;
    return VaultLockout.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> setLockout(VaultLockout? lockout) => _writeCached(
    _keyLockout,
    lockout == null ? '' : jsonEncode(lockout.toJson()),
  );

  @override
  Future<DateTime?> getLegacyLockoutUntil() async {
    final value = await _readCached(_keyLegacyLockoutUntil);
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  Future<void> deleteLegacyLockoutUntil() =>
      _deleteCached(_keyLegacyLockoutUntil);

  @override
  Future<int?> getWipeAfterFailures() async {
    final value = await _readCached(_keyWipeAfterFailures);
    return value != null ? int.tryParse(value) : null;
  }

  @override
  Future<void> setWipeAfterFailures(int? attempts) =>
      _writeCached(_keyWipeAfterFailures, attempts?.toString() ?? '');

  @override
  Future<BiometricWrap?> getBiometricWrap() async {
    final value = await _readCached(_keyBiometricWrap);
    if (value == null || value.isEmpty) return null;
    return BiometricWrap.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> setBiometricWrap(BiometricWrap? wrap) => _writeCached(
    _keyBiometricWrap,
    wrap == null ? '' : jsonEncode(wrap.toJson()),
  );

  @override
  Future<MonotonicInstant?> getPinVerifiedAt() async {
    final value = await _readCached(_keyPinVerifiedAt);
    if (value == null || value.isEmpty) return null;
    return MonotonicInstant.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> setPinVerifiedAt(MonotonicInstant instant) =>
      _writeCached(_keyPinVerifiedAt, jsonEncode(instant.toJson()));

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
