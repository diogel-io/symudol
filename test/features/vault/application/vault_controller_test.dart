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

  group('VaultController', () {
    test('initial state should be NoVault if store is empty', () {
      expect(controller.debugState.vaultState, isA<NoVault>());
      expect(controller.debugState.identities, isEmpty);
      expect(controller.debugState.activeIdentity, isNull);
    });

    test('createVault should transition state to Unlocked', () async {
      await controller.createVault('1234');
      
      expect(controller.debugState.vaultState, isA<VaultUnlocked>());
      expect(await store.getSentinel(), isNotNull);
    });

    test('lock and unlock should update state correctly', () async {
      await controller.createVault('1234');
      expect(controller.debugState.vaultState, isA<VaultUnlocked>());

      await controller.lock();
      expect(controller.debugState.vaultState, isA<VaultLocked>());

      await controller.unlock('1234');
      expect(controller.debugState.vaultState, isA<VaultUnlocked>());
    });

    test('createIdentity should update identities list and activeIdentity', () async {
      await controller.createVault('1234');
      
      await controller.createIdentity(displayName: 'Test Identity');
      
      expect(controller.debugState.identities, hasLength(1));
      expect(controller.debugState.identities.first.displayName, equals('Test Identity'));
      expect(controller.debugState.activeIdentity, isNotNull);
      expect(controller.debugState.activeIdentity?.displayName, equals('Test Identity'));
    });

    test('setActiveIdentity should update activeIdentity', () async {
      await controller.createVault('1234');
      
      await controller.createIdentity(displayName: 'Id 1');
      final firstIdentity = controller.debugState.activeIdentity!;
      expect(firstIdentity.displayName, equals('Id 1'));
      
      await controller.createIdentity(displayName: 'Id 2');
      // In VaultServiceImpl, creating a second identity does NOT automatically change activeIdentity
      // if one is already set. Let's verify this assumption.
      
      await controller.setActiveIdentity(controller.debugState.identities.firstWhere((i) => i.displayName == 'Id 2').localId);
      final secondIdentity = controller.debugState.activeIdentity!;
      
      expect(secondIdentity.displayName, equals('Id 2'));
      
      await controller.setActiveIdentity(firstIdentity.localId);
      expect(controller.debugState.activeIdentity?.localId, equals(firstIdentity.localId));
      expect(controller.debugState.activeIdentity?.displayName, equals('Id 1'));
    });

    test('active identity flag in identities list should be correct in controller state', () async {
      await controller.createVault('1234');
      await controller.createIdentity(displayName: 'Id 1');
      await controller.createIdentity(displayName: 'Id 2');
      
      final id1 = controller.debugState.identities.firstWhere((i) => i.displayName == 'Id 1');
      final id2 = controller.debugState.identities.firstWhere((i) => i.displayName == 'Id 2');
      
      // Id 1 should be active (first created)
      expect(id1.isActive, isTrue);
      expect(id2.isActive, isFalse);
      
      // Switch to Id 2
      await controller.setActiveIdentity(id2.localId);
      
      final updatedId1 = controller.debugState.identities.firstWhere((i) => i.displayName == 'Id 1');
      final updatedId2 = controller.debugState.identities.firstWhere((i) => i.displayName == 'Id 2');
      
      expect(updatedId1.isActive, isFalse);
      expect(updatedId2.isActive, isTrue);
    });

    test('mutation operations should be blocked when locked', () async {
      await controller.createVault('1234');
      await controller.lock();
      
      expect(controller.debugState.vaultState, isA<VaultLocked>());
      
      await controller.createIdentity(displayName: 'Should fail');
      expect(controller.debugState.identities, isEmpty);
      
      await controller.importIdentity('nsec1...', displayName: 'Should fail');
      expect(controller.debugState.identities, isEmpty);
    });
  });
}
