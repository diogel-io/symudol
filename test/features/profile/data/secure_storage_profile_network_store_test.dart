import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/data/secure_storage_profile_network_store.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';

/// The profile network settings are kept in secure storage, beside the vault
/// (diogel-io/symudol#45).
void main() {
  late SecureStorageProfileNetworkStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureStorageProfileNetworkStore();
  });

  test('nothing saved reads as the defaults', () async {
    expect(await store.read(), ProfileNetworkSettings.defaults());
  });

  test('saved settings read back', () async {
    const settings = ProfileNetworkSettings(
      profileRelays: ['wss://one.example.com'],
      indexerRelays: [],
      blossomServer: 'https://media.example.com',
    );

    await store.write(settings);

    expect(await SecureStorageProfileNetworkStore().read(), settings);
  });

  test('unreadable settings read as the defaults', () async {
    FlutterSecureStorage.setMockInitialValues({
      'profile_network_settings_v1': '{not json',
    });

    expect(await store.read(), ProfileNetworkSettings.defaults());
  });

  test('a wipe of secure storage resets them to the defaults', () async {
    await store.write(
      ProfileNetworkSettings.defaults().copyWith(
        profileRelays: ['wss://one.example.com'],
      ),
    );

    await const FlutterSecureStorage().deleteAll();

    expect(await store.read(), ProfileNetworkSettings.defaults());
  });
}
