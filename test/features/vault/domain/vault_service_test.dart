import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  late FakeVaultStore fakeStore;
  late VaultServiceImpl vaultService;

  setUp(() {
    fakeStore = FakeVaultStore();
    vaultService = VaultServiceImpl(fakeStore);
  });

  group('VaultServiceImpl Lifecycle', () {
    test('initial state should be NoVault when no sentinel exists', () async {
      await vaultService.init();
      expect(vaultService.state, isA<NoVault>());
    });

    test('initial state should be VaultLocked when sentinel exists', () async {
      await fakeStore.setSentinel('vault_exists');
      await vaultService.init();
      expect(vaultService.state, isA<VaultLocked>());
    });

    test('createVault should set sentinel and transition to VaultUnlocked', () async {
      await vaultService.createVault('1234');
      
      expect(vaultService.state, isA<VaultUnlocked>());
      expect(await fakeStore.getSentinel(), isNotNull);
    });

    test('createVault should throw VaultAlreadyExistsException if sentinel exists', () async {
      await fakeStore.setSentinel('vault_exists');
      
      expect(
        () => vaultService.createVault('1234'),
        throwsA(isA<VaultAlreadyExistsException>()),
      );
    });

    test('lock should transition from VaultUnlocked to VaultLocked', () async {
      await vaultService.createVault('1234');
      expect(vaultService.state, isA<VaultUnlocked>());

      await vaultService.lock();
      expect(vaultService.state, isA<VaultLocked>());
    });

    test('lock should transition from VaultLocked to VaultLocked', () async {
      await fakeStore.setSentinel('vault_exists');
      await vaultService.init();
      expect(vaultService.state, isA<VaultLocked>());

      await vaultService.lock();
      expect(vaultService.state, isA<VaultLocked>());
    });

    test('unlock should transition from VaultLocked to VaultUnlocked', () async {
      await fakeStore.setSentinel('vault_exists');
      await vaultService.init();
      expect(vaultService.state, isA<VaultLocked>());

      await vaultService.unlock('1234');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('unlock should throw VaultNotFoundException if no vault exists', () async {
      expect(
        () => vaultService.unlock('1234'),
        throwsA(isA<VaultNotFoundException>()),
      );
    });

    test('lock should transition to NoVault if vault was deleted from store externally (edge case)', () async {
      await vaultService.createVault('1234');
      await fakeStore.clearAll();
      
      await vaultService.lock();
      expect(vaultService.state, isA<NoVault>());
    });
  });

  group('VaultServiceImpl Identity operations while locked', () {
    test('createIdentity should throw VaultLockedException when locked', () async {
      await fakeStore.setSentinel('vault_exists');
      await vaultService.init();
      
      expect(
        () => vaultService.createIdentity(),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('listIdentities should throw VaultLockedException when locked', () async {
      await fakeStore.setSentinel('vault_exists');
      await vaultService.init();
      
      expect(
        () => vaultService.listIdentities(),
        throwsA(isA<VaultLockedException>()),
      );
    });
  });
}
