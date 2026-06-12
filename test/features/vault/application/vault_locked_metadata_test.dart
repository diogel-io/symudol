import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  late FakeVaultStore store;
  late VaultServiceImpl service;
  late VaultController controller;

  setUp(() async {
    store = FakeVaultStore();
    service = VaultServiceImpl(store);
    await service.init();
    controller = VaultController(service);
  });

  group('Vault Locked Metadata Policy', () {
    test('Create vault + identity -> lock -> controller state clears identities and active identity', () async {
      // 1. Setup: Create vault and an identity
      await controller.createVault('1234');
      await controller.createIdentity(displayName: 'Active User');
      
      expect(controller.state.vaultState, isA<VaultUnlocked>());
      expect(controller.state.identities, isNotEmpty);
      expect(controller.state.activeIdentity, isNotNull);
      expect(controller.state.activeIdentity?.displayName, 'Active User');

      // 2. Action: Lock the vault
      await controller.lock();

      // 3. Verification: Metadata should be cleared
      expect(controller.state.vaultState, isA<VaultLocked>());
      expect(controller.state.identities, isEmpty, reason: 'Identities list should be empty when locked');
      expect(controller.state.activeIdentity, isNull, reason: 'Active identity should be null when locked');
    });

    test('Unlock -> active identity restored', () async {
      // 1. Setup: Create vault, identity, and then lock
      await controller.createVault('1234');
      await controller.createIdentity(displayName: 'Active User');
      final originalId = controller.state.activeIdentity?.localId;
      await controller.lock();
      
      expect(controller.state.activeIdentity, isNull);

      // 2. Action: Unlock the vault
      await controller.unlock('1234');

      // 3. Verification: Active identity should be restored
      expect(controller.state.vaultState, isA<VaultUnlocked>());
      expect(controller.state.activeIdentity, isNotNull, reason: 'Active identity should be restored after unlock');
      expect(controller.state.activeIdentity?.displayName, 'Active User');
      expect(controller.state.activeIdentity?.localId, originalId);
      expect(controller.state.identities, isNotEmpty);
    });

    test('Expire session -> controller state clears identities and active identity', () async {
      // 1. Setup: Create vault and identity
      await controller.createVault('1234');
      await controller.createIdentity(displayName: 'Active User');
      
      expect(controller.state.identities, isNotEmpty);
      expect(controller.state.activeIdentity, isNotNull);

      // 2. Action: Expire session
      await controller.expireSession();

      // 3. Verification: Metadata should be cleared
      expect(controller.state.vaultState, isA<SessionExpired>());
      expect(controller.state.identities, isEmpty, reason: 'Identities list should be empty when session expired');
      expect(controller.state.activeIdentity, isNull, reason: 'Active identity should be null when session expired');
    });

    test('Fresh app start with existing vault -> state starts locked and metadata is cleared', () async {
        // 1. Pre-fill store
        await store.setWrappedDek('wrapped-dek-placeholder');
        await store.setActiveIdentityId('some-id');
        // We need a record for toVaultIdentity to work if service.init reads it
        // but here we just want to check if controller correctly reflects the policy.
        
        // 2. Re-init service and controller
        service = VaultServiceImpl(store);
        await service.init();
        controller = VaultController(service);
        await controller.initialize();

        // 3. Verification
        expect(controller.state.vaultState, isA<VaultLocked>());
        expect(controller.state.identities, isEmpty);
        expect(controller.state.activeIdentity, isNull, reason: 'Even if active identity exists in store, it should not be in state while locked');
    });
  });
}
