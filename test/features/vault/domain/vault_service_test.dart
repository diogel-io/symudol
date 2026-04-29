import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:dart_nostr/dart_nostr.dart';
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

  group('VaultServiceImpl Identity creation and listing', () {
    test('createIdentity should generate a valid identity and store it', () async {
      await vaultService.createVault('1234');
      
      final identity = await vaultService.createIdentity(displayName: 'Test Identity');
      
      expect(identity.publicKey, isNotEmpty);
      expect(identity.displayName, equals('Test Identity'));
      expect(identity.origin, equals(IdentityOrigin.generated));
      
      final identities = await vaultService.listIdentities();
      expect(identities, hasLength(1));
      expect(identities.first.publicKey, equals(identity.publicKey));
    });

    test('listIdentities should not expose the private key', () async {
      await vaultService.createVault('1234');
      await vaultService.createIdentity();
      
      final identities = await vaultService.listIdentities();
      final identity = identities.first;
      
      // VaultIdentity doesn't have a private key field.
      // We check the record in the store to ensure it DOES have it, 
      // but the returned object doesn't.
      final record = await fakeStore.getIdentityRecord(identity.localId);
      expect(record?.secretPayload, isNotEmpty);
      
      // We expect a NoSuchMethodError if we try to access secretPayload on VaultIdentity
      expect(() => (identity as dynamic).secretPayload, throwsNoSuchMethodError);
    });

    test('importIdentity should derive public key from private key and store it', () async {
      await vaultService.createVault('1234');
      
      final nostr = Nostr.instance;
      final keyPair = nostr.services.keys.generateKeyPair();
      final privateKey = keyPair.private;
      final expectedPublicKey = keyPair.public;
      
      final identity = await vaultService.importIdentity(privateKey, displayName: 'Imported');
      
      expect(identity.publicKey, equals(expectedPublicKey));
      expect(identity.origin, equals(IdentityOrigin.imported));
      
      final record = await fakeStore.getIdentityRecord(identity.localId);
      expect(record?.secretPayload, equals(privateKey));
    });

    test('should handle duplicate public keys', () async {
      await vaultService.createVault('1234');
      
      final nostr = Nostr.instance;
      final privateKey = nostr.services.keys.generateKeyPair().private;
      
      await vaultService.importIdentity(privateKey);
      
      expect(
        () => vaultService.importIdentity(privateKey),
        throwsA(isA<VaultStorageException>()),
      );
    });
  });
}
