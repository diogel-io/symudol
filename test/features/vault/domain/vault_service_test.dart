import 'dart:typed_data';

import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_scope.dart';
import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_key_envelope.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_monotonic_clock.dart';
import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_nip55_permission_store.dart';
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

  group('VaultServiceImpl on background isolates', () {
    // The other tests run crypto inline (flutter_test_config.dart). The app
    // copies the service into an isolate for each task, so nothing it holds
    // may be unsendable.
    setUp(() => ConcurrencyUtils.useSynchronousTasks = false);
    tearDown(() => ConcurrencyUtils.useSynchronousTasks = true);

    test('create, lock, fail and unlock work across isolates', () async {
      vaultService = VaultServiceImpl(
        fakeStore,
        clock: FakeMonotonicClock(),
        vaultCryptoService: const _CheapKdfCryptoService(),
      );
      await vaultService.createVault('123456');
      await vaultService.createIdentity(displayName: 'Alice');
      await vaultService.lock();

      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<InvalidPinException>()),
      );
      await vaultService.unlock('123456');

      expect(vaultService.state, isA<VaultUnlocked>());
      expect(await vaultService.getActivePrivateKey(), isNotNull);
    });
  });

  group('VaultServiceImpl lockout schedule (#16)', () {
    test('attempts 1-4 are free, then the lockout escalates to a cap', () {
      final expected = {
        1: Duration.zero,
        4: Duration.zero,
        5: const Duration(seconds: 30),
        6: const Duration(minutes: 1),
        7: const Duration(minutes: 5),
        8: const Duration(minutes: 15),
        9: const Duration(hours: 1),
        10: const Duration(hours: 2),
        11: const Duration(hours: 4),
        12: const Duration(hours: 8),
        13: const Duration(hours: 16),
        14: const Duration(hours: 24),
        15: const Duration(hours: 24),
        1000: const Duration(hours: 24),
      };
      expected.forEach((attempts, lockout) {
        expect(
          VaultServiceImpl.lockoutFor(attempts),
          lockout,
          reason: 'attempt $attempts',
        );
      });
    });
  });

  group('VaultServiceImpl PIN lockout (#16)', () {
    late FakeMonotonicClock clock;

    setUp(() {
      clock = FakeMonotonicClock();
      vaultService = VaultServiceImpl(
        fakeStore,
        clock: clock,
        vaultCryptoService: const _CheapKdfCryptoService(),
      );
    });

    Future<void> failTimes(int times) async {
      for (var i = 0; i < times; i++) {
        await expectLater(
          vaultService.unlock('000000'),
          throwsA(isA<InvalidPinException>()),
        );
        // Wait out whatever that attempt earned, so the next one is checked.
        clock.advance(VaultServiceImpl.lockoutFor(i + 1));
      }
    }

    Future<Duration> lockedOutFor() async {
      try {
        await vaultService.unlock('123456');
      } on VaultLockedOutException catch (e) {
        return e.remaining;
      }
      fail('expected a lockout');
    }

    test('the 5th wrong PIN locks out even the right one for 30 s', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();

      for (var i = 0; i < 5; i++) {
        await expectLater(
          vaultService.unlock('000000'),
          throwsA(isA<InvalidPinException>()),
        );
      }

      expect(await lockedOutFor(), const Duration(seconds: 30));
      clock.advance(const Duration(seconds: 29));
      expect(await lockedOutFor(), const Duration(seconds: 1));

      clock.advance(const Duration(seconds: 1));
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('the lockout is timed on the monotonic clock only', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await failTimes(4);
      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<InvalidPinException>()),
      );

      // Nothing the wall clock does reaches the service: with the monotonic
      // clock standing still, the whole lockout is still there however
      // long this takes.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await lockedOutFor(), const Duration(seconds: 30));
      expect(
        await vaultService.getLockoutRemaining(),
        const Duration(seconds: 30),
      );
    });

    test('a reboot restarts the remaining lockout', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await failTimes(4);
      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<InvalidPinException>()),
      );
      clock.advance(const Duration(seconds: 20));
      expect(await lockedOutFor(), const Duration(seconds: 10));

      clock.reboot();

      expect(await lockedOutFor(), const Duration(seconds: 30));
      // Re-based to this boot, so it now runs down.
      clock.advance(const Duration(seconds: 30));
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('an elapsed clock that went backwards restarts the lockout', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await failTimes(4);
      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<InvalidPinException>()),
      );

      clock.elapsedMs -= 60000;

      expect(await lockedOutFor(), const Duration(seconds: 30));
    });

    test('an attempt is charged even if the check never finishes', () async {
      final crashing = VaultServiceImpl(
        fakeStore,
        clock: clock,
        vaultCryptoService: const _CheapKdfCryptoService(crashOnUnwrap: true),
      );
      await vaultService.createVault('123456');
      await vaultService.lock();
      await fakeStore.setFailedUnlockAttempts(4);

      // As if the app were killed mid-check: unwrapping never returns.
      await expectLater(crashing.unlock('123456'), throwsA(isA<StateError>()));

      expect(await fakeStore.getFailedUnlockAttempts(), 5);
      expect(await lockedOutFor(), const Duration(seconds: 30));
    });

    test('a successful unlock resets the count and clears the lockout', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await failTimes(5);

      await vaultService.unlock('123456');

      expect(vaultService.state, isA<VaultUnlocked>());
      expect(await fakeStore.getFailedUnlockAttempts(), 0);
      expect(await fakeStore.getLockout(), isNull);
      expect(await vaultService.getLockoutRemaining(), Duration.zero);
    });

    test('a pre-#16 lockout moves onto the monotonic clock', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await fakeStore.setLegacyLockoutUntil(
        DateTime.now().add(const Duration(minutes: 10)),
      );

      final remaining = await lockedOutFor();

      expect(remaining, lessThanOrEqualTo(const Duration(minutes: 10)));
      expect(remaining, greaterThan(const Duration(minutes: 9)));
      expect(await fakeStore.getLegacyLockoutUntil(), isNull);
      clock.advance(remaining);
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('a pre-#16 lockout is capped at 24 h', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await fakeStore.setLegacyLockoutUntil(
        DateTime.now().add(const Duration(days: 30)),
      );

      expect(await lockedOutFor(), VaultServiceImpl.maxLockout);
    });

    test('an expired pre-#16 lockout is just removed', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await fakeStore.setLegacyLockoutUntil(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await vaultService.unlock('123456');

      expect(vaultService.state, isA<VaultUnlocked>());
      expect(await fakeStore.getLegacyLockoutUntil(), isNull);
    });
  });

  group('VaultServiceImpl wipe after failed PINs (#16)', () {
    late FakeMonotonicClock clock;
    late FakeNip55PermissionStore grantStore;
    var nativeWipes = 0;

    setUp(() {
      clock = FakeMonotonicClock();
      grantStore = FakeNip55PermissionStore()
        ..grants.add(
          Nip55PermissionGrant(
            id: 'grant-1',
            identityPubkey: 'pubkey',
            packageName: 'com.example.client',
            scope: const GetPublicKeyScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime(2026, 10, 1),
          ),
        );
      nativeWipes = 0;
      vaultService = VaultServiceImpl(
        fakeStore,
        clock: clock,
        vaultCryptoService: const _CheapKdfCryptoService(),
        nip55PermissionStore: grantStore,
        wipeNativeState: () async => nativeWipes++,
      );
    });

    test('is off by default', () async {
      expect(await vaultService.getWipeAfterFailures(), isNull);
    });

    test('the Nth wrong PIN erases the vault', () async {
      await vaultService.createVault('123456');
      await vaultService.createIdentity(displayName: 'Alice');
      await vaultService.setWipeAfterFailures(10);
      await vaultService.lock();
      await fakeStore.setFailedUnlockAttempts(9);

      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<VaultWipedException>()),
      );

      expect(vaultService.state, isA<NoVault>());
      expect(await fakeStore.getWrappedDek(), isNull);
      expect(await fakeStore.getIdentities(), isEmpty);
      expect(grantStore.grants, isEmpty);
      expect(nativeWipes, 1);
    });

    test('the right PIN at N-1 failures does not erase it', () async {
      await vaultService.createVault('123456');
      await vaultService.setWipeAfterFailures(10);
      await vaultService.lock();
      await fakeStore.setFailedUnlockAttempts(9);

      await vaultService.unlock('123456');

      expect(vaultService.state, isA<VaultUnlocked>());
      expect(await fakeStore.getFailedUnlockAttempts(), 0);
    });

    test('a right PIN sent alongside the erasing one cannot unlock', () async {
      await vaultService.createVault('123456');
      await vaultService.setWipeAfterFailures(10);
      await vaultService.lock();
      await fakeStore.setFailedUnlockAttempts(9);

      final wrong = vaultService.unlock('000000');
      final right = vaultService.unlock('123456');

      await expectLater(wrong, throwsA(isA<VaultWipedException>()));
      await expectLater(right, throwsA(isA<VaultNotFoundException>()));
      expect(vaultService.state, isA<NoVault>());
      expect(await fakeStore.getWrappedDek(), isNull);
    });

    test('a count already past N still erases on a wrong PIN', () async {
      await vaultService.createVault('123456');
      await vaultService.setWipeAfterFailures(10);
      await vaultService.lock();
      // An earlier attempt was charged at N, then the app was killed.
      await fakeStore.setFailedUnlockAttempts(10);

      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<VaultWipedException>()),
      );
      expect(vaultService.state, isA<NoVault>());
    });

    test('never erases when it is off', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      await fakeStore.setFailedUnlockAttempts(40);

      await expectLater(
        vaultService.unlock('000000'),
        throwsA(isA<InvalidPinException>()),
      );
      expect(vaultService.state, isA<VaultLocked>());
      expect(await fakeStore.getWrappedDek(), isNotNull);
    });

    test('only 10, 15, 20 or off can be set, and only while unlocked', () async {
      await vaultService.createVault('123456');
      for (final attempts in [10, 15, 20, null]) {
        await vaultService.setWipeAfterFailures(attempts);
        expect(await vaultService.getWipeAfterFailures(), attempts);
      }
      await expectLater(
        vaultService.setWipeAfterFailures(3),
        throwsA(isA<VaultStorageException>()),
      );

      await vaultService.lock();
      await expectLater(
        vaultService.setWipeAfterFailures(10),
        throwsA(isA<VaultLockedException>()),
      );
    });
  });

  group('VaultServiceImpl change PIN (#21)', () {
    late FakeMonotonicClock clock;

    setUp(() {
      clock = FakeMonotonicClock();
      vaultService = VaultServiceImpl(
        fakeStore,
        clock: clock,
        vaultCryptoService: const _CheapKdfCryptoService(),
      );
    });

    Future<void> createWithIdentity() async {
      await vaultService.createVault('123456');
      await vaultService.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000001',
      );
    }

    test('afterwards only the new PIN unlocks, with the same keys', () async {
      await createWithIdentity();
      final key = await vaultService.getActivePrivateKey();
      final before = fakeStore.storedKeyEnvelope!;

      await vaultService.changePin('123456', '654321');

      final after = fakeStore.storedKeyEnvelope!;
      expect(after.salt, isNot(before.salt));
      expect(after.params, VaultKdfParams.defaultParams);
      expect(vaultService.state, isA<VaultUnlocked>());
      await vaultService.lock();
      await expectLater(
        vaultService.unlock('123456'),
        throwsA(isA<InvalidPinException>()),
      );
      await vaultService.unlock('654321');
      expect(await vaultService.getActivePrivateKey(), key);
      expect(await vaultService.listIdentities(), hasLength(1));
    });

    test('a change moves weaker Argon2id params to the defaults', () async {
      await createWithIdentity();
      // As a vault from before #16: the same wrapped DEK under weaker params
      // (the cheap test KDF ignores params, so the old PIN still unwraps it).
      const weak = VaultKdfParams(memory: 19456, iterations: 2);
      final stored = fakeStore.storedKeyEnvelope!;
      await fakeStore.setKeyEnvelope(
        VaultKeyEnvelope(
          salt: stored.salt,
          params: weak,
          wrappedDek: stored.wrappedDek,
        ),
      );
      expect(fakeStore.storedKeyEnvelope!.params, weak);

      await vaultService.changePin('123456', '654321');

      expect(
        fakeStore.storedKeyEnvelope!.params,
        VaultKdfParams.defaultParams,
      );
      await vaultService.lock();
      await vaultService.unlock('654321');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('a wrong current PIN is refused and charged', () async {
      await createWithIdentity();
      final before = fakeStore.storedKeyEnvelope!;

      await expectLater(
        vaultService.changePin('000000', '654321'),
        throwsA(isA<InvalidPinException>()),
      );

      expect(await fakeStore.getFailedUnlockAttempts(), 1);
      expect(fakeStore.storedKeyEnvelope!.wrappedDek, before.wrappedDek);
      await vaultService.lock();
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('wrong current PINs share the unlock lockout', () async {
      await createWithIdentity();
      await fakeStore.setFailedUnlockAttempts(4);

      await expectLater(
        vaultService.changePin('000000', '654321'),
        throwsA(isA<InvalidPinException>()),
      );

      await expectLater(
        vaultService.changePin('123456', '654321'),
        throwsA(isA<VaultLockedOutException>()),
      );
      expect(
        await vaultService.getLockoutRemaining(),
        const Duration(seconds: 30),
      );
    });

    test('a wrong current PIN at the wipe limit erases the vault', () async {
      await createWithIdentity();
      await vaultService.setWipeAfterFailures(10);
      await fakeStore.setFailedUnlockAttempts(9);

      await expectLater(
        vaultService.changePin('000000', '654321'),
        throwsA(isA<VaultWipedException>()),
      );

      expect(vaultService.state, isA<NoVault>());
      expect(await fakeStore.getWrappedDek(), isNull);
    });

    test('a right current PIN resets the count', () async {
      await createWithIdentity();
      await fakeStore.setFailedUnlockAttempts(3);

      await vaultService.changePin('123456', '654321');

      expect(await fakeStore.getFailedUnlockAttempts(), 0);
    });

    test('a failed write leaves the old PIN working', () async {
      await createWithIdentity();
      fakeStore.shouldThrowOnSetKeyEnvelope = true;

      await expectLater(
        vaultService.changePin('123456', '654321'),
        throwsA(isA<VaultStorageException>()),
      );

      fakeStore.shouldThrowOnSetKeyEnvelope = false;
      await vaultService.lock();
      await expectLater(
        vaultService.unlock('654321'),
        throwsA(isA<InvalidPinException>()),
      );
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('is refused while locked', () async {
      await createWithIdentity();
      await vaultService.lock();

      await expectLater(
        vaultService.changePin('123456', '654321'),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('the new PIN must be 6 digits', () async {
      await createWithIdentity();
      for (final pin in ['12345', '1234567', '12345a', '']) {
        await expectLater(
          vaultService.changePin('123456', pin),
          throwsA(isA<VaultStorageException>()),
          reason: pin,
        );
      }
      expect(await fakeStore.getFailedUnlockAttempts(), 0);
    });

    test('an unlock sent during a change waits for it', () async {
      await createWithIdentity();

      final change = vaultService.changePin('123456', '654321');
      await vaultService.lock();
      final unlock = vaultService.unlock('654321');

      await change;
      await unlock;
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('works across background isolates', () async {
      ConcurrencyUtils.useSynchronousTasks = false;
      addTearDown(() => ConcurrencyUtils.useSynchronousTasks = true);
      await createWithIdentity();

      await vaultService.changePin('123456', '654321');

      await vaultService.lock();
      await vaultService.unlock('654321');
      expect(vaultService.state, isA<VaultUnlocked>());
    });
  });

  group('VaultServiceImpl key envelope migration (#16)', () {
    const crypto = PointyCastleVaultCryptoService();
    const weakParams = VaultKdfParams(memory: 8, iterations: 1);
    late Uint8List dek;
    late Uint8List salt;

    setUp(() {
      vaultService = VaultServiceImpl(fakeStore, clock: FakeMonotonicClock());
      dek = crypto.generateDek();
      salt = crypto.generateSalt();
    });

    /// A vault as stored before #16: three separate keys.
    Future<void> storeLegacyVault(VaultKdfParams params) async {
      final kek = crypto.deriveKek('123456', salt, params);
      await fakeStore.setKdfSalt(salt);
      await fakeStore.setKdfParams(params);
      await fakeStore.setWrappedDek(crypto.wrapDek(dek, kek));
    }

    Uint8List unwrapStored() {
      final envelope = fakeStore.storedKeyEnvelope!;
      final kek = crypto.deriveKek('123456', envelope.salt, envelope.params);
      return crypto.unwrapDek(envelope.wrappedDek, kek);
    }

    test('createVault writes one envelope with the default params', () async {
      await vaultService.createVault('123456');

      expect(fakeStore.storedKeyEnvelope?.params, VaultKdfParams.defaultParams);
      expect(fakeStore.hasLegacyKeyFields, isFalse);
      expect(await fakeStore.getVersion(), VaultServiceImpl.storeVersion);
    });

    test('a legacy vault moves onto the envelope on unlock', () async {
      await storeLegacyVault(VaultKdfParams.defaultParams);
      await vaultService.init();

      await vaultService.unlock('123456');

      expect(fakeStore.storedKeyEnvelope, isNotNull);
      expect(fakeStore.hasLegacyKeyFields, isFalse);
      expect(await fakeStore.getVersion(), VaultServiceImpl.storeVersion);
      expect(unwrapStored(), dek);
      await vaultService.lock();
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('weaker params are upgraded, re-wrapping the same DEK', () async {
      await storeLegacyVault(weakParams);
      await vaultService.init();

      await vaultService.unlock('123456');

      final envelope = fakeStore.storedKeyEnvelope!;
      expect(envelope.params, VaultKdfParams.defaultParams);
      expect(envelope.salt, isNot(salt));
      expect(unwrapStored(), dek);
      await vaultService.lock();
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
    });

    test('an envelope already on the default params is left alone', () async {
      await vaultService.createVault('123456');
      await vaultService.lock();
      final writes = fakeStore.keyEnvelopeWrites;

      await vaultService.unlock('123456');

      expect(fakeStore.keyEnvelopeWrites, writes);
    });

    test('a failed upgrade write leaves the old PIN working', () async {
      await storeLegacyVault(weakParams);
      await vaultService.init();
      fakeStore.shouldThrowOnSetKeyEnvelope = true;

      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());
      expect(fakeStore.storedKeyEnvelope, isNull);
      expect(fakeStore.hasLegacyKeyFields, isTrue);

      await vaultService.lock();
      await vaultService.unlock('123456');
      expect(vaultService.state, isA<VaultUnlocked>());

      // Retried, and done, on a later unlock.
      fakeStore.shouldThrowOnSetKeyEnvelope = false;
      await vaultService.lock();
      await vaultService.unlock('123456');
      expect(fakeStore.storedKeyEnvelope?.params, VaultKdfParams.defaultParams);
    });
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

  group('VaultServiceImpl wipe', () {
    late FakeNip55PermissionStore grantStore;
    late FakeNip46SessionStore sessionStore;
    late int nativeWipes;
    late VaultServiceImpl wipingService;

    VaultServiceImpl build({
      Future<void> Function()? wipeNativeState,
      FakeNip46SessionStore? sessions,
    }) => VaultServiceImpl(
      fakeStore,
      nip55PermissionStore: grantStore,
      nip46SessionStore: sessions ?? sessionStore,
      wipeNativeState:
          wipeNativeState ??
          () async {
            nativeWipes++;
          },
    );

    setUp(() {
      grantStore = FakeNip55PermissionStore()
        ..grants.add(
          Nip55PermissionGrant(
            id: 'grant-1',
            identityPubkey: 'pubkey',
            packageName: 'com.example.client',
            scope: const GetPublicKeyScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime(2026, 10, 1),
          ),
        );
      sessionStore = FakeNip46SessionStore([
        Nip46Session(
          id: 'session-1',
          clientPubkey: 'client',
          remoteSignerPubkey: 'remote',
          remoteSignerPrivkey: 'secret',
          relays: const ['wss://relay.example'],
          grantedScopes: const [],
          status: Nip46SessionStatus.active,
          createdAt: DateTime(2026, 10, 1),
        ),
      ]);
      nativeWipes = 0;
      wipingService = build();
    });

    Future<void> expectEverythingErased(VaultServiceImpl service) async {
      expect(service.state, isA<NoVault>());
      expect(service.activeIdentity, isNull);
      expect(await fakeStore.getWrappedDek(), isNull);
      expect(await fakeStore.getIdentities(), isEmpty);
      expect(grantStore.grants, isEmpty);
      expect(sessionStore.sessions, isEmpty);
      expect(nativeWipes, greaterThanOrEqualTo(1));
    }

    test('erases everything while unlocked', () async {
      await wipingService.createVault('123456');
      await wipingService.createIdentity(displayName: 'Alice');

      await wipingService.wipe();

      await expectEverythingErased(wipingService);
      await expectLater(
        wipingService.getActivePrivateKey(),
        completion(isNull),
      );
    });

    test('erases everything while locked', () async {
      await wipingService.createVault('123456');
      await wipingService.createIdentity(displayName: 'Alice');
      await wipingService.lock();

      await wipingService.wipe();

      await expectEverythingErased(wipingService);
    });

    test('a new vault can be created after a wipe', () async {
      await wipingService.createVault('123456');
      await wipingService.wipe();

      await wipingService.createVault('654321');

      expect(wipingService.state, isA<VaultUnlocked>());
      expect(await wipingService.listIdentities(), isEmpty);
    });

    test('a failing step still runs the others and is reported', () async {
      await wipingService.createVault('123456');
      final service = build(
        wipeNativeState: () async => throw Exception('native failed'),
      );
      await service.init();

      await expectLater(
        service.wipe(),
        throwsA(
          isA<VaultWipeIncompleteException>().having(
            (e) => e.failedSteps,
            'failedSteps',
            ['native NIP-55 state'],
          ),
        ),
      );
      expect(service.state, isA<NoVault>());
      expect(await fakeStore.getWrappedDek(), isNull);
      expect(grantStore.grants, isEmpty);
      expect(sessionStore.sessions, isEmpty);
    });

    test('a vault that survives a failed wipe stays locked', () async {
      await wipingService.createVault('123456');
      fakeStore.shouldThrowOnClearAll = true;

      await expectLater(
        wipingService.wipe(),
        throwsA(isA<VaultWipeIncompleteException>()),
      );
      expect(wipingService.state, isA<VaultLocked>());
      expect(await wipingService.getActivePrivateKey(), isNull);
      expect(grantStore.grants, isEmpty);
    });

    test('init with no vault clears what an interrupted wipe left', () async {
      await wipingService.init();
      await pumpEventQueue();

      expect(wipingService.state, isA<NoVault>());
      expect(grantStore.grants, isEmpty);
      expect(sessionStore.sessions, isEmpty);
      expect(nativeWipes, 1);
    });

    test('init with a vault leaves grants and sessions alone', () async {
      await fakeStore.setWrappedDek('wrapped-dek-placeholder');

      await wipingService.init();
      await pumpEventQueue();

      expect(wipingService.state, isA<VaultLocked>());
      expect(grantStore.grants, hasLength(1));
      expect(sessionStore.sessions, hasLength(1));
      expect(nativeWipes, 0);
    });
  });
}

/// The real AES-GCM wrapping over a trivially cheap Argon2id, so tests can
/// make many attempts. [crashOnUnwrap] stands in for the app being killed
/// mid-check.
class _CheapKdfCryptoService extends PointyCastleVaultCryptoService {
  static const _cheap = VaultKdfParams(memory: 8, iterations: 1);

  final bool crashOnUnwrap;

  const _CheapKdfCryptoService({this.crashOnUnwrap = false});

  @override
  Uint8List deriveKek(String pin, Uint8List salt, VaultKdfParams params) =>
      super.deriveKek(pin, salt, _cheap);

  @override
  Uint8List unwrapDek(String wrapped, Uint8List kek) {
    if (crashOnUnwrap) throw StateError('killed mid-check');
    return super.unwrapDek(wrapped, kek);
  }
}
