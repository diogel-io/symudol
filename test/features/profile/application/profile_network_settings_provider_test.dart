import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/application/profile_editor.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_profile_relay_client.dart';
import '../../../fakes/fake_vault_store.dart';

/// Changing the relays in Settings changes where profiles are read from and
/// published to (diogel-io/symudol#45).
void main() {
  const chosen = 'wss://chosen.example.com';
  final chosenSettings = ProfileNetworkSettings.defaults().copyWith(
    profileRelays: [chosen],
    indexerRelays: [],
  );

  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeProfileRelayClient relays;
  late FakeProfileNetworkStore store;
  late ProviderContainer container;
  late String pubkey;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock('123456');
    pubkey = controller.state.activeIdentity!.publicKey;

    relays = FakeProfileRelayClient();
    store = FakeProfileNetworkStore();
    container = ProviderContainer(
      overrides: [
        vaultServiceProvider.overrideWithValue(vault),
        vaultControllerProvider.overrideWith((ref) => controller),
        profileRelayClientProvider.overrideWithValue(relays),
        profileNetworkStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  test('the saved settings are read from the store', () async {
    store.settings = chosenSettings;

    expect(
      await container.read(profileNetworkSettingsProvider.future),
      chosenSettings,
    );
  });

  test('saving stores the settings and the next lookup uses them', () async {
    await container.read(profileNetworkSettingsProvider.future);

    await container
        .read(profileNetworkSettingsProvider.notifier)
        .save(chosenSettings);
    final lookup = await container
        .read(relayProfileServiceProvider)
        .fetchProfile(pubkey);

    expect(store.settings, chosenSettings);
    expect(relays.queries.single.relays, [chosen]);
    expect(lookup.publishRelays, [chosen]);
  });

  test('a profile save publishes to the relays chosen in Settings', () async {
    container.listen(profileEditorProvider(pubkey), (_, _) {});
    await container
        .read(profileNetworkSettingsProvider.notifier)
        .save(chosenSettings);
    final editor = container.read(profileEditorProvider(pubkey).notifier);

    await editor.load();
    editor.confirmCreate();
    editor.updateForm(
      container.read(profileEditorProvider(pubkey)).form.withText('name', 'a'),
    );
    await editor.save();

    expect(relays.published.single.relays, [chosen]);
  });

  test('a wipe brings back the defaults', () async {
    await container
        .read(profileNetworkSettingsProvider.notifier)
        .save(chosenSettings);
    container.listen(profileNetworkSettingsProvider, (_, _) {});
    // The wipe deletes the stored settings with the vault.
    store.settings = ProfileNetworkSettings.defaults();

    await controller.wipe();

    expect(
      await container.read(profileNetworkSettingsProvider.future),
      ProfileNetworkSettings.defaults(),
    );
  });
}
