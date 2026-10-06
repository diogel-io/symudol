import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
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

    test('initial state should be VaultLocked when a vault exists', () async {
      await fakeStore.setWrappedDek('wrapped-dek-placeholder');
      await vaultService.init();
      expect(vaultService.state, isA<VaultLocked>());
    });

    test(
      'createVault should persist a wrapped DEK and transition to VaultUnlocked',
      () async {
        await vaultService.createVault('1234');

        expect(vaultService.state, isA<VaultUnlocked>());
        expect(await fakeStore.getWrappedDek(), isNotNull);
      },
    );

    test(
      'createVault should throw VaultAlreadyExistsException if a vault already exists',
      () async {
        await fakeStore.setWrappedDek('wrapped-dek-placeholder');

        expect(
          () => vaultService.createVault('1234'),
          throwsA(isA<VaultAlreadyExistsException>()),
        );
      },
    );

    test('lock should transition from VaultUnlocked to VaultLocked', () async {
      await vaultService.createVault('1234');
      expect(vaultService.state, isA<VaultUnlocked>());

      await vaultService.lock();
      expect(vaultService.state, isA<VaultLocked>());
    });

    test('lock should transition from VaultLocked to VaultLocked', () async {
      await fakeStore.setWrappedDek('wrapped-dek-placeholder');
      await vaultService.init();
      expect(vaultService.state, isA<VaultLocked>());

      await vaultService.lock();
      expect(vaultService.state, isA<VaultLocked>());
    });

    test(
      'unlock should transition from VaultLocked to VaultUnlocked with the correct PIN',
      () async {
        await vaultService.createVault('1234');
        await vaultService.lock();
        expect(vaultService.state, isA<VaultLocked>());

        await vaultService.unlock('1234');
        expect(vaultService.state, isA<VaultUnlocked>());
      },
    );

    test(
      'unlock should throw InvalidPinException for the wrong PIN',
      () async {
        await vaultService.createVault('1234');
        await vaultService.lock();

        expect(
          () => vaultService.unlock('0000'),
          throwsA(isA<InvalidPinException>()),
        );
        expect(vaultService.state, isA<VaultLocked>());
      },
    );

    test(
      'unlock should throw VaultNotFoundException if no vault exists',
      () async {
        expect(
          () => vaultService.unlock('1234'),
          throwsA(isA<VaultNotFoundException>()),
        );
      },
    );

    test(
      'lock should transition to NoVault if vault was deleted from store externally (edge case)',
      () async {
        await vaultService.createVault('1234');
        await fakeStore.clearAll();

        await vaultService.lock();
        expect(vaultService.state, isA<NoVault>());
      },
    );
  });

  group('VaultServiceImpl Lockout', () {
    test(
      'repeated wrong PINs trigger a lockout that blocks further unlock attempts',
      () async {
        var now = DateTime(2024, 1, 1);
        vaultService = VaultServiceImpl(fakeStore, now: () => now);

        await vaultService.createVault('1234');
        await vaultService.lock();

        for (var i = 0; i < 5; i++) {
          await expectLater(
            () => vaultService.unlock('0000'),
            throwsA(isA<InvalidPinException>()),
          );
        }

        // The 5th failure should trigger a lockout, blocking even the
        // correct PIN until the lockout window passes.
        await expectLater(
          () => vaultService.unlock('1234'),
          throwsA(isA<VaultLockedOutException>()),
        );

        // Advance time past the lockout window.
        now = now.add(const Duration(seconds: 31));

        await vaultService.unlock('1234');
        expect(vaultService.state, isA<VaultUnlocked>());
      },
    );

    test(
      'a successful unlock resets the failed-attempt counter',
      () async {
        await vaultService.createVault('1234');
        await vaultService.lock();

        await expectLater(
          () => vaultService.unlock('0000'),
          throwsA(isA<InvalidPinException>()),
        );

        await vaultService.unlock('1234');
        expect(vaultService.state, isA<VaultUnlocked>());
        expect(await fakeStore.getFailedUnlockAttempts(), equals(0));
      },
    );
  });

  group('VaultServiceImpl Identity operations while locked', () {
    test(
      'createIdentity should throw VaultLockedException when locked',
      () async {
        await fakeStore.setWrappedDek('wrapped-dek-placeholder');
        await vaultService.init();

        expect(
          () => vaultService.createIdentity(),
          throwsA(isA<VaultLockedException>()),
        );
      },
    );

    test(
      'listIdentities should throw VaultLockedException when locked',
      () async {
        await fakeStore.setWrappedDek('wrapped-dek-placeholder');
        await vaultService.init();

        expect(
          () => vaultService.listIdentities(),
          throwsA(isA<VaultLockedException>()),
        );
      },
    );
  });

  group('VaultServiceImpl Identity creation and listing', () {
    test(
      'createIdentity should generate a valid identity and store it',
      () async {
        await vaultService.createVault('1234');

        final identity = await vaultService.createIdentity(
          displayName: 'Test Identity',
        );

        expect(identity.publicKey, isNotEmpty);
        expect(identity.displayName, equals('Test Identity'));
        expect(identity.origin, equals(IdentityOrigin.generated));

        final identities = await vaultService.listIdentities();
        expect(identities, hasLength(1));
        expect(identities.first.publicKey, equals(identity.publicKey));
      },
    );

    test('listIdentities should not expose the private key', () async {
      await vaultService.createVault('1234');
      await vaultService.createIdentity();

      final identities = await vaultService.listIdentities();
      final identity = identities.first;

      // VaultIdentity doesn't have a private key field.
      // We check the record in the store to ensure it DOES have it,
      // but the returned object doesn't.
      final record = await fakeStore.getIdentityRecord(identity.localId);
      expect(record?.encryptedSecretPayload, isNotEmpty);

      // We expect a NoSuchMethodError if we try to access secretPayload on VaultIdentity
      expect(
        () => (identity as dynamic).secretPayload,
        throwsNoSuchMethodError,
      );
    });

    test(
      'importIdentity should derive public key from nsec and store it',
      () async {
        await vaultService.createVault('1234');

        final nostr = Nostr.instance;
        final keyPair = nostr.services.keys.generateKeyPair();
        final privateKey = keyPair.private;
        final nsec = nostr.services.bech32.encodePrivateKeyToNsec(privateKey);
        final expectedPublicKey = keyPair.public;

        final identity = await vaultService.importIdentity(
          nsec,
          displayName: 'Imported',
        );

        expect(identity.publicKey, equals(expectedPublicKey));
        expect(identity.origin, equals(IdentityOrigin.imported));

        final record = await fakeStore.getIdentityRecord(identity.localId);
        expect(record?.encryptedSecretPayload, isNot(equals(privateKey)));
        expect(await vaultService.getActivePrivateKey(), equals(privateKey));
      },
    );

    test(
      'importIdentity should derive public key from hex private key and store it',
      () async {
        await vaultService.createVault('1234');

        final nostr = Nostr.instance;
        final keyPair = nostr.services.keys.generateKeyPair();
        final privateKey = keyPair.private;
        final expectedPublicKey = keyPair.public;

        final identity = await vaultService.importIdentity(
          privateKey,
          displayName: 'Imported Hex',
        );

        expect(identity.publicKey, equals(expectedPublicKey));
        expect(identity.origin, equals(IdentityOrigin.imported));

        final record = await fakeStore.getIdentityRecord(identity.localId);
        expect(record?.encryptedSecretPayload, isNot(equals(privateKey)));
        expect(await vaultService.getActivePrivateKey(), equals(privateKey));
      },
    );

    test('importIdentity should reject invalid key formats', () async {
      await vaultService.createVault('1234');

      // Invalid nsec (wrong prefix/checksum)
      expect(
        () => vaultService.importIdentity('nsec1invalid'),
        throwsA(isA<VaultStorageException>()),
      );

      // Invalid hex (too short)
      expect(
        () => vaultService.importIdentity('abc123'),
        throwsA(isA<VaultStorageException>()),
      );

      // Invalid hex (not hex)
      expect(
        () => vaultService.importIdentity('g' * 64),
        throwsA(isA<VaultStorageException>()),
      );
    });

    test('should handle duplicate public keys for both nsec and hex', () async {
      await vaultService.createVault('1234');

      final nostr = Nostr.instance;
      final privateKey = nostr.services.keys.generateKeyPair().private;
      final nsec = nostr.services.bech32.encodePrivateKeyToNsec(privateKey);

      await vaultService.importIdentity(privateKey);

      // Duplicate hex
      expect(
        () => vaultService.importIdentity(privateKey),
        throwsA(isA<VaultStorageException>()),
      );

      // Duplicate nsec
      expect(
        () => vaultService.importIdentity(nsec),
        throwsA(isA<VaultStorageException>()),
      );
    });
    test('listIdentities should return safe summaries without secrets', () async {
      await vaultService.createVault('1234');
      await vaultService.createIdentity(displayName: 'Test');

      final identities = await vaultService.listIdentities();
      expect(identities, isNotEmpty);
      // VaultIdentity doesn't have secretPayload, it's only in VaultIdentityRecord
      // So listIdentities returning List<VaultIdentity> is already safe for UI.
    });
  });
  group('VaultServiceImpl Active Identity', () {
    test(
      'setActiveIdentity should update activeIdentity and persist in store',
      () async {
        await vaultService.createVault('1234');
        final identity = await vaultService.createIdentity(displayName: 'Test');

        await vaultService.setActiveIdentity(identity.localId);

        expect(vaultService.activeIdentity?.localId, equals(identity.localId));
        expect(await fakeStore.getActiveIdentityId(), equals(identity.localId));
      },
    );

    test(
      'setActiveIdentity should throw IdentityNotFoundException for unknown ID',
      () async {
        await vaultService.createVault('1234');

        expect(
          () => vaultService.setActiveIdentity('unknown'),
          throwsA(isA<IdentityNotFoundException>()),
        );
      },
    );

    test('active identity should be loaded during init', () async {
      await vaultService.createVault('1234');
      final identity = await vaultService.createIdentity(
        displayName: 'Test',
      );
      await vaultService.lock();

      // Re-init a fresh service instance backed by the same store.
      final reloadedService = VaultServiceImpl(fakeStore);
      await reloadedService.init();
      await reloadedService.unlock('1234');

      expect(
        reloadedService.activeIdentity?.localId,
        equals(identity.localId),
      );
    });

    test(
      'the first created identity should become active automatically if none active',
      () async {
        await vaultService.createVault('1234');
        final identity = await vaultService.createIdentity();

        expect(vaultService.activeIdentity?.localId, equals(identity.localId));
      },
    );

    test(
      'listIdentities should return identities with correct isActive flag',
      () async {
        await vaultService.createVault('1234');
        final identity1 = await vaultService.createIdentity(
          displayName: 'ID 1',
        );
        final identity2 = await vaultService.createIdentity(
          displayName: 'ID 2',
        );

        // Initially, identity1 is active (first created)
        var identities = await vaultService.listIdentities();
        expect(
          identities.firstWhere((i) => i.localId == identity1.localId).isActive,
          isTrue,
        );
        expect(
          identities.firstWhere((i) => i.localId == identity2.localId).isActive,
          isFalse,
        );

        // Switch to identity2
        await vaultService.setActiveIdentity(identity2.localId);

        identities = await vaultService.listIdentities();
        expect(
          identities.firstWhere((i) => i.localId == identity1.localId).isActive,
          isFalse,
        );
        expect(
          identities.firstWhere((i) => i.localId == identity2.localId).isActive,
          isTrue,
        );
      },
    );
  });

  group('VaultServiceImpl Nostr signing', () {
    final draft = NostrEventDraft(
      kind: 1,
      content: 'hello',
      tags: const [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        1777618800 * 1000,
        isUtc: true,
      ),
    );

    test('signNostrEvent refuses while locked', () async {
      await fakeStore.setWrappedDek('wrapped-dek-placeholder');
      await vaultService.init();

      expect(
        () => vaultService.signNostrEvent(
          identityLocalId: 'missing',
          draft: draft,
        ),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('signNostrEvent refuses missing identity', () async {
      await vaultService.createVault('1234');

      expect(
        () => vaultService.signNostrEvent(
          identityLocalId: 'missing',
          draft: draft,
        ),
        throwsA(isA<IdentityNotFoundException>()),
      );
    });

    test('signNostrEvent refuses active identity mismatch', () async {
      await vaultService.createVault('1234');
      final identity1 = await vaultService.createIdentity(displayName: 'ID 1');
      final identity2 = await vaultService.createIdentity(displayName: 'ID 2');
      await vaultService.setActiveIdentity(identity1.localId);

      expect(
        () => vaultService.signNostrEvent(
          identityLocalId: identity2.localId,
          draft: draft,
        ),
        throwsA(isA<IdentityMismatchException>()),
      );
    });

    test('signNostrEvent signs with active identity', () async {
      await vaultService.createVault('1234');
      final identity = await vaultService.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000001',
      );

      final event = await vaultService.signNostrEvent(
        identityLocalId: identity.localId,
        draft: draft,
      );

      expect(event.pubkey, identity.publicKey);
      expect(event.id, isNotEmpty);
      expect(event.sig, isNotEmpty);
      expect(const DartNostrCryptoService().verifySignedEvent(event), isTrue);
    });
  });

  group('VaultServiceImpl NIP-55 crypto', () {
    test('crypto operations refuse while locked', () async {
      await fakeStore.setWrappedDek('wrapped-dek-placeholder');
      await vaultService.init();

      expect(
        () => vaultService.nip44Encrypt(
          identityLocalId: 'missing',
          peerPubkeyHex: 'b' * 64,
          plaintext: 'hello',
        ),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('NIP-04 encrypt/decrypt uses active vault identity', () async {
      await vaultService.createVault('1234');
      final alice = await vaultService.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000001',
      );
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );

      final ciphertext = await vaultService.nip04Encrypt(
        identityLocalId: alice.localId,
        peerPubkeyHex: bob.public,
        plaintext: 'hello from vault',
      );

      expect(
        const DartNostrCryptoService().nip04Decrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: alice.publicKey,
          ciphertext: ciphertext,
        ),
        'hello from vault',
      );
    });

    test('NIP-44 encrypt/decrypt uses active vault identity', () async {
      await vaultService.createVault('1234');
      final alice = await vaultService.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000001',
      );
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );

      final ciphertext = await vaultService.nip44Encrypt(
        identityLocalId: alice.localId,
        peerPubkeyHex: bob.public,
        plaintext: 'hello nip44',
      );

      expect(
        const DartNostrCryptoService().nip44Decrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: alice.publicKey,
          ciphertext: ciphertext,
        ),
        'hello nip44',
      );
    });

    test('crypto operations refuse active identity mismatch', () async {
      await vaultService.createVault('1234');
      final identity1 = await vaultService.createIdentity(displayName: 'ID 1');
      final identity2 = await vaultService.createIdentity(displayName: 'ID 2');
      await vaultService.setActiveIdentity(identity1.localId);

      expect(
        () => vaultService.nip44Encrypt(
          identityLocalId: identity2.localId,
          peerPubkeyHex: identity1.publicKey,
          plaintext: 'hello',
        ),
        throwsA(isA<IdentityMismatchException>()),
      );
    });
  });
}
