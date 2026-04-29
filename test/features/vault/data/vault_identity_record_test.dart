import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultIdentityRecord', () {
    final now = DateTime.now();
    final record = VaultIdentityRecord(
      version: 1,
      identityId: 'id123',
      publicKey: 'pubkey123',
      secretPayload: 'secret123',
      origin: IdentityOrigin.generated,
      createdAt: now,
    );

    test('should serialize to json correctly', () {
      final json = record.toJson();

      expect(json['version'], 1);
      expect(json['identityId'], 'id123');
      expect(json['publicKey'], 'pubkey123');
      expect(json['secretPayload'], 'secret123');
      expect(json['origin'], 'generated');
      expect(json['createdAt'], now.toIso8601String());
    });

    test('should deserialize from json correctly', () {
      final json = {
        'version': 1,
        'identityId': 'id123',
        'publicKey': 'pubkey123',
        'secretPayload': 'secret123',
        'origin': 'generated',
        'createdAt': now.toIso8601String(),
      };

      final deserialized = VaultIdentityRecord.fromJson(json);

      expect(deserialized.version, 1);
      expect(deserialized.identityId, 'id123');
      expect(deserialized.publicKey, 'pubkey123');
      expect(deserialized.secretPayload, 'secret123');
      expect(deserialized.origin, IdentityOrigin.generated);
      // Comparing DateTime up to second precision to avoid microsecond issues with ISO parsing if any
      expect(deserialized.createdAt.toIso8601String(), now.toIso8601String());
    });

    test('toVaultIdentity should strip secret payload and map correctly', () {
      final vaultIdentity = record.toVaultIdentity();

      expect(vaultIdentity.localId, record.identityId);
      expect(vaultIdentity.publicKey, record.publicKey);
      expect(vaultIdentity.createdAt, record.createdAt);
      expect(vaultIdentity.origin, record.origin);
      
      // Verify that secretPayload is NOT in VaultIdentity
      // VaultIdentity doesn't have secretPayload field, so this is implicitly verified by type system,
      // but we verify the mapped fields are correct.
    });
  });
}
