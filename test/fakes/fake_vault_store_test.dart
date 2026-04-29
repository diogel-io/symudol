import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_vault_store.dart';

void main() {
  late FakeVaultStore store;

  setUp(() {
    store = FakeVaultStore();
  });

  group('FakeVaultStore', () {
    test('should store and retrieve version', () async {
      await store.setVersion('1.0');
      expect(await store.getVersion(), '1.0');
    });

    test('should store and retrieve sentinel', () async {
      await store.setSentinel('sentinel');
      expect(await store.getSentinel(), 'sentinel');
    });

    test('should simulate missing vault', () async {
      await store.setSentinel('sentinel');
      store.simulateMissingVault = true;
      expect(await store.getSentinel(), isNull);
    });

    test('should store and retrieve identities', () async {
      final identity = VaultIdentity(
        localId: 'id1',
        publicKey: 'pub1',
        createdAt: DateTime.now(),
        origin: IdentityOrigin.generated,
      );

      await store.saveIdentity(identity);
      final identities = await store.getIdentities();
      
      expect(identities, hasLength(1));
      expect(identities.first.localId, 'id1');
    });

    test('should throw storage error when requested', () async {
      store.shouldThrowStorageError = true;
      expect(() => store.getVersion(), throwsA(isA<VaultStorageException>()));
    });

    test('should throw duplicate identity error when requested', () async {
      final identity = VaultIdentity(
        localId: 'id1',
        publicKey: 'pub1',
        createdAt: DateTime.now(),
        origin: IdentityOrigin.generated,
      );

      await store.saveIdentity(identity);
      store.shouldThrowDuplicateIdentityError = true;
      
      expect(() => store.saveIdentity(identity), throwsA(isA<VaultStorageException>()));
    });

    test('clearAll should reset everything', () async {
      await store.setVersion('1.0');
      await store.setSentinel('sentinel');
      await store.saveIdentity(VaultIdentity(
        localId: 'id1',
        publicKey: 'pub1',
        createdAt: DateTime.now(),
        origin: IdentityOrigin.generated,
      ));

      await store.clearAll();

      expect(await store.getVersion(), isNull);
      expect(await store.getSentinel(), isNull);
      expect(await store.getIdentities(), isEmpty);
    });
  });
}
