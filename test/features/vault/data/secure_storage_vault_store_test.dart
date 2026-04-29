import 'dart:convert';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/data/secure_storage_vault_store.dart';
import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
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

    test('getSentinel should read from storage', () async {
      when(() => mockStorage.read(key: 'vault_sentinel'))
          .thenAnswer((_) async => 'sentinel_value');

      final sentinel = await vaultStore.getSentinel();

      expect(sentinel, 'sentinel_value');
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
        secretPayload: 'secret1',
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

    test('getIdentities should return list of identities (safe summaries)', () async {
      final record = VaultIdentityRecord(
        identityId: 'id1',
        publicKey: 'pub1',
        secretPayload: 'secret1',
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
      expect(identities.first.localId, 'id1');
      // Verify it's a VaultIdentity and doesn't have secretPayload
      expect(identities.first, isA<VaultIdentity>());
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
  });
}
