import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_failure.dart';
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
      expect(controller.state.vaultState, isA<NoVault>());
      expect(controller.state.identities, isEmpty);
      expect(controller.state.activeIdentity, isNull);
    });

    test('createVault should transition state to Unlocked', () async {
      await controller.createVault('1234');

      expect(controller.state.vaultState, isA<VaultUnlocked>());
      expect(await store.getSentinel(), isNotNull);
    });

    test(
      'lock and unlock should update state correctly and lock should clear identities',
      () async {
        await controller.createVault('1234');
        await controller.createIdentity(displayName: 'Test');
        expect(controller.state.vaultState, isA<VaultUnlocked>());
        expect(controller.state.identities, isNotEmpty);

        await controller.lock();
        expect(controller.state.vaultState, isA<VaultLocked>());
        expect(controller.state.identities, isEmpty);

        await controller.unlock('1234');
        expect(controller.state.vaultState, isA<VaultUnlocked>());
        expect(controller.state.identities, isNotEmpty);
      },
    );

    test(
      'createIdentity should update identities list and activeIdentity',
      () async {
        await controller.createVault('1234');

        await controller.createIdentity(displayName: 'Test Identity');

        expect(controller.state.identities, hasLength(1));
        expect(
          controller.state.identities.first.displayName,
          equals('Test Identity'),
        );
        expect(controller.state.activeIdentity, isNotNull);
        expect(
          controller.state.activeIdentity?.displayName,
          equals('Test Identity'),
        );
      },
    );

    test('setActiveIdentity should update activeIdentity', () async {
      await controller.createVault('1234');

      await controller.createIdentity(displayName: 'Id 1');
      final firstIdentity = controller.state.activeIdentity!;
      expect(firstIdentity.displayName, equals('Id 1'));

      await controller.createIdentity(displayName: 'Id 2');
      // In VaultServiceImpl, creating a second identity does NOT automatically change activeIdentity
      // if one is already set. Let's verify this assumption.

      await controller.setActiveIdentity(
        controller.state.identities
            .firstWhere((i) => i.displayName == 'Id 2')
            .localId,
      );
      final secondIdentity = controller.state.activeIdentity!;

      expect(secondIdentity.displayName, equals('Id 2'));

      await controller.setActiveIdentity(firstIdentity.localId);
      expect(
        controller.state.activeIdentity?.localId,
        equals(firstIdentity.localId),
      );
      expect(controller.state.activeIdentity?.displayName, equals('Id 1'));
    });

    test(
      'active identity flag in identities list should be correct in controller state',
      () async {
        await controller.createVault('1234');
        await controller.createIdentity(displayName: 'Id 1');
        await controller.createIdentity(displayName: 'Id 2');

        final id1 = controller.state.identities.firstWhere(
          (i) => i.displayName == 'Id 1',
        );
        final id2 = controller.state.identities.firstWhere(
          (i) => i.displayName == 'Id 2',
        );

        // Id 1 should be active (first created)
        expect(id1.isActive, isTrue);
        expect(id2.isActive, isFalse);

        // Switch to Id 2
        await controller.setActiveIdentity(id2.localId);

        final updatedId1 = controller.state.identities.firstWhere(
          (i) => i.displayName == 'Id 1',
        );
        final updatedId2 = controller.state.identities.firstWhere(
          (i) => i.displayName == 'Id 2',
        );

        expect(updatedId1.isActive, isFalse);
        expect(updatedId2.isActive, isTrue);
      },
    );

    test(
      'mutation operations should be blocked when locked and set failure',
      () async {
        await controller.createVault('1234');
        await controller.lock();

        expect(controller.state.vaultState, isA<VaultLocked>());

        await controller.createIdentity(displayName: 'Should fail');
        expect(controller.state.identities, isEmpty);
        expect(controller.state.failure, isA<VaultLockedFailure>());

        controller.clearFailure();
        expect(controller.state.failure, isNull);

        await controller.importIdentity('nsec1...', displayName: 'Should fail');
        expect(controller.state.identities, isEmpty);
        expect(controller.state.failure, isA<VaultLockedFailure>());
      },
    );

    test(
      'importIdentity should map VaultStorageException to UI-safe failure',
      () async {
        await controller.createVault('1234');

        // Attempt to import an invalid key
        await controller.importIdentity('invalid-key');

        expect(controller.state.failure, isA<UnsupportedKeyFormatFailure>());

        // Create an identity then try to import it again (duplicate)
        await service.createIdentity();
        // We need a real private key for a successful import first to then fail on duplicate,
        // but VaultServiceImpl.createIdentity doesn't expose the private key easily here.
        // Let's use a known private key.
        const privateKey =
            '0000000000000000000000000000000000000000000000000000000000000001';
        await controller.importIdentity(privateKey);
        expect(controller.state.failure, isNull);

        await controller.importIdentity(privateKey);
        expect(controller.state.failure, isA<DuplicateIdentityFailure>());
      },
    );
  });

  backgroundLockDelayControllerTests();
}

void backgroundLockDelayControllerTests() {
  group('VaultController background lock delay', () {
    late FakeVaultStore store;
    late VaultServiceImpl service;
    late VaultController controller;

    setUp(() async {
      store = FakeVaultStore();
      service = VaultServiceImpl(store);
      await service.init();
      controller = VaultController(service);
    });

    test('defaults to 5 minutes when unset', () async {
      await controller.createVault('1234');

      expect(controller.state.backgroundLockDelayMinutes, 5);
    });

    test('persists updates and refreshes locked state', () async {
      await controller.createVault('1234');
      await controller.setBackgroundLockDelayMinutes(15);

      expect(controller.state.backgroundLockDelayMinutes, 15);
      expect(await store.getBackgroundLockDelayMinutes(), 15);

      await controller.lock();
      expect(controller.state.backgroundLockDelayMinutes, 15);
    });

    test('rejects unsupported values', () async {
      await controller.createVault('1234');
      await controller.setBackgroundLockDelayMinutes(-2);

      expect(controller.state.backgroundLockDelayMinutes, 5);
      expect(controller.state.failure, isA<SecureStorageFailure>());
    });
  });
}
