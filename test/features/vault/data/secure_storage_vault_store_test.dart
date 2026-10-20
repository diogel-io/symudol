import 'dart:convert';
import 'dart:typed_data';

import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/vault/data/secure_storage_vault_store.dart';
import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_key_envelope.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late SecureStorageVaultStore vaultStore;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    vaultStore = SecureStorageVaultStore(storage: mockStorage);
  });

  group('SecureStorageVaultStore', () {
    test('getVersion should read from storage', () async {
      when(() => mockStorage.read(key: 'vault_version'))
          .thenAnswer((_) async => '1.0');

      final version = await vaultStore.getVersion();

      expect(version, '1.0');
      verify(() => mockStorage.read(key: 'vault_version')).called(1);
    });

    test('setVersion should write to storage', () async {
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await vaultStore.setVersion('2.0');

      verify(() => mockStorage.write(key: 'vault_version', value: '2.0')).called(1);
    });

    test('getWrappedDek should read the legacy key without an envelope', () async {
      when(() => mockStorage.read(key: 'vault_key_envelope'))
          .thenAnswer((_) async => null);
      when(() => mockStorage.read(key: 'vault_wrapped_dek'))
          .thenAnswer((_) async => 'wrapped_dek_value');

      final wrappedDek = await vaultStore.getWrappedDek();

      expect(wrappedDek, 'wrapped_dek_value');
    });

    test('getActiveIdentityId should read from storage', () async {
      when(() => mockStorage.read(key: 'active_identity_id'))
          .thenAnswer((_) async => 'id_123');

      final id = await vaultStore.getActiveIdentityId();

      expect(id, 'id_123');
    });

    test('saveIdentityRecord should serialize and write to storage', () async {
      final record = VaultIdentityRecord(
        identityId: 'id1',
        publicKey: 'pub1',
        encryptedSecretPayload: 'secret1',
        createdAt: DateTime(2023),
        origin: IdentityOrigin.generated,
      );

      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await vaultStore.saveIdentityRecord(record);

      verify(() => mockStorage.write(
            key: 'identity_id1',
            value: any(named: 'value', that: contains('"identityId":"id1"')),
          )).called(1);
    });

    test('getIdentities should return list of identities', () async {
      final record = VaultIdentityRecord(
        identityId: 'id1',
        publicKey: 'pub1',
        encryptedSecretPayload: 'secret1',
        createdAt: DateTime(2023),
        origin: IdentityOrigin.generated,
      );
      
      when(() => mockStorage.readAll(
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
            lOptions: any(named: 'lOptions'),
            mOptions: any(named: 'mOptions'),
            wOptions: any(named: 'wOptions'),
            webOptions: any(named: 'webOptions'),
          )).thenAnswer((_) async => {
            'identity_id1': jsonEncode(record.toJson()),
            'some_other_key': 'value',
          });

      final identities = await vaultStore.getIdentities();

      expect(identities.length, 1);
      expect(identities.first.identityId, 'id1');
      expect(identities.first, isA<VaultIdentityRecord>());
    });

    test('deleteIdentity should delete from storage', () async {
      when(() => mockStorage.delete(
            key: any(named: 'key'),
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
            lOptions: any(named: 'lOptions'),
            mOptions: any(named: 'mOptions'),
            wOptions: any(named: 'wOptions'),
            webOptions: any(named: 'webOptions'),
          )).thenAnswer((_) async {});

      await vaultStore.deleteIdentity('id1');

      verify(() => mockStorage.delete(
            key: 'identity_id1',
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
            lOptions: any(named: 'lOptions'),
            mOptions: any(named: 'mOptions'),
            wOptions: any(named: 'wOptions'),
            webOptions: any(named: 'webOptions'),
          )).called(1);
    });

    test('clearAll should delete everything', () async {
      when(() => mockStorage.deleteAll(
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
            lOptions: any(named: 'lOptions'),
            mOptions: any(named: 'mOptions'),
            wOptions: any(named: 'wOptions'),
            webOptions: any(named: 'webOptions'),
          )).thenAnswer((_) async {});

      await vaultStore.clearAll();

      verify(() => mockStorage.deleteAll(
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
            lOptions: any(named: 'lOptions'),
            mOptions: any(named: 'mOptions'),
            wOptions: any(named: 'wOptions'),
            webOptions: any(named: 'webOptions'),
          )).called(1);
    });

    group('key envelope (#16)', () {
      final envelope = VaultKeyEnvelope(
        salt: Uint8List.fromList(List.generate(16, (i) => i)),
        params: const VaultKdfParams(memory: 65536, iterations: 3),
        wrappedDek: 'wrapped',
      );
      late Map<String, String> stored;

      setUp(() {
        stored = {};
        when(() => mockStorage.read(key: any(named: 'key')))
            .thenAnswer((i) async => stored[i.namedArguments[#key]]);
        when(() => mockStorage.write(
              key: any(named: 'key'),
              value: any(named: 'value'),
            )).thenAnswer((i) async {
          stored[i.namedArguments[#key] as String] =
              i.namedArguments[#value] as String;
        });
        when(() => mockStorage.delete(key: any(named: 'key')))
            .thenAnswer((i) async {
          stored.remove(i.namedArguments[#key]);
        });
      });

      test('round-trips as one value', () async {
        await vaultStore.setKeyEnvelope(envelope);

        expect(stored.keys, ['vault_key_envelope']);
        final read = await SecureStorageVaultStore(storage: mockStorage)
            .getKeyEnvelope();
        expect(read?.salt, envelope.salt);
        expect(read?.params, envelope.params);
        expect(read?.wrappedDek, 'wrapped');
        expect(
          await SecureStorageVaultStore(storage: mockStorage).getWrappedDek(),
          'wrapped',
        );
      });

      test('falls back to the legacy keys, and replaces them', () async {
        stored.addAll({
          'vault_kdf_salt': base64Encode(envelope.salt),
          'vault_kdf_params': jsonEncode(envelope.params.toJson()),
          'vault_wrapped_dek': 'legacy-wrapped',
        });

        final legacy = await vaultStore.getKeyEnvelope();
        expect(legacy?.wrappedDek, 'legacy-wrapped');
        expect(legacy?.params, envelope.params);
        expect(await vaultStore.getWrappedDek(), 'legacy-wrapped');

        await vaultStore.setKeyEnvelope(envelope);

        expect(stored.keys, ['vault_key_envelope']);
        expect(await vaultStore.getWrappedDek(), 'wrapped');
      });

      test('an incomplete legacy set is no envelope', () async {
        stored['vault_wrapped_dek'] = 'legacy-wrapped';

        expect(await vaultStore.getKeyEnvelope(), isNull);
        expect(await vaultStore.getWrappedDek(), 'legacy-wrapped');
      });

      test('a failed envelope write keeps the legacy keys', () async {
        stored.addAll({
          'vault_kdf_salt': base64Encode(envelope.salt),
          'vault_kdf_params': jsonEncode(envelope.params.toJson()),
          'vault_wrapped_dek': 'legacy-wrapped',
        });
        when(() => mockStorage.write(
              key: 'vault_key_envelope',
              value: any(named: 'value'),
            )).thenThrow(Exception('write failed'));

        await expectLater(
          vaultStore.setKeyEnvelope(envelope),
          throwsA(isA<Exception>()),
        );

        expect((await vaultStore.getKeyEnvelope())?.wrappedDek, 'legacy-wrapped');
        expect(stored.containsKey('vault_kdf_salt'), isTrue);
      });

      test('the lockout round-trips as JSON and clears', () async {
        const lockout = VaultLockout(
          bootCount: 3,
          startElapsedMs: 120000,
          durationMs: 30000,
        );

        await vaultStore.setLockout(lockout);
        expect(
          jsonDecode(stored['vault_lockout']!),
          {'bootCount': 3, 'startElapsedMs': 120000, 'durationMs': 30000},
        );
        expect(
          await SecureStorageVaultStore(storage: mockStorage).getLockout(),
          lockout,
        );

        await vaultStore.setLockout(null);
        expect(await vaultStore.getLockout(), isNull);
      });

      test('reads and deletes the legacy lockout', () async {
        final until = DateTime(2026, 10, 20, 12);
        stored['vault_lockout_until'] = until.toIso8601String();

        expect(await vaultStore.getLegacyLockoutUntil(), until);
        await vaultStore.deleteLegacyLockoutUntil();
        expect(stored.containsKey('vault_lockout_until'), isFalse);
        expect(await vaultStore.getLegacyLockoutUntil(), isNull);
      });

      test('the wipe setting round-trips, with null for off', () async {
        expect(await vaultStore.getWipeAfterFailures(), isNull);
        await vaultStore.setWipeAfterFailures(15);
        expect(
          await SecureStorageVaultStore(storage: mockStorage)
              .getWipeAfterFailures(),
          15,
        );
        await vaultStore.setWipeAfterFailures(null);
        expect(await vaultStore.getWipeAfterFailures(), isNull);
      });

      test('a wrap saved before it had an alias reads as the first key (#108)',
          () async {
        when(() => mockStorage.read(key: 'vault_biometric_wrap')).thenAnswer(
          (_) async => jsonEncode({'iv': 'aXY=', 'ciphertext': 'Y3Q='}),
        );

        final wrap = await vaultStore.getBiometricWrap();

        expect(wrap?.alias, 'symudol_biometric_dek_wrap');
        expect(wrap?.iv, 'aXY=');
        expect(wrap?.ciphertext, 'Y3Q=');
      });
    });
  });
}
