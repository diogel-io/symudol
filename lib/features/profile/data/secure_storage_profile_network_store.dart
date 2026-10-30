import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:symudol/app/diogel_log.dart';

import '../domain/profile_network_settings.dart';
import '../domain/profile_network_store.dart';

/// Stores the profile network settings in secure storage beside the vault, so
/// a vault wipe (`deleteAll`) resets them to the defaults
/// (diogel-io/symudol#45).
class SecureStorageProfileNetworkStore implements ProfileNetworkStore {
  static const _key = 'profile_network_settings_v1';

  final FlutterSecureStorage _storage;

  SecureStorageProfileNetworkStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<ProfileNetworkSettings> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.trim().isEmpty) {
        return ProfileNetworkSettings.defaults();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ProfileNetworkSettings.fromJson(decoded.cast());
      }
    } catch (e) {
      diogelLog(
        'SecureStorageProfileNetworkStore: could not read the settings',
        error: e,
      );
    }
    return ProfileNetworkSettings.defaults();
  }

  @override
  Future<void> write(ProfileNetworkSettings settings) =>
      _storage.write(key: _key, value: jsonEncode(settings.toJson()));
}
