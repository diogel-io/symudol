import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../test/fakes/fake_vault_store.dart';

void main() {
  test('vaultStoreProvider should return SecureStorageVaultStore by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(vaultStoreProvider);
    expect(store.runtimeType.toString(), contains('SecureStorageVaultStore'));
  });

  test('vaultServiceProvider should return VaultServiceImpl', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final service = container.read(vaultServiceProvider);
    expect(service, isA<VaultServiceImpl>());
  });

  test('vaultStoreProvider can be overridden in tests', () {
    final fakeStore = FakeVaultStore();
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWithValue(fakeStore),
      ],
    );
    addTearDown(container.dispose);

    final store = container.read(vaultStoreProvider);
    expect(store, same(fakeStore));
  });

  test('vaultStateProvider reflects initial state of service', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(vaultStateProvider);
    expect(state, isA<NoVault>());
  });
}
