import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultIdentity', () {
    final now = DateTime.now();
    
    test('should compare identities by public key', () {
      final identity1 = VaultIdentity(
        localId: '1',
        publicKey: 'pub1',
        createdAt: now,
        origin: IdentityOrigin.generated,
      );
      
      final identity2 = VaultIdentity(
        localId: '2',
        publicKey: 'pub1',
        createdAt: now,
        origin: IdentityOrigin.imported,
        displayName: 'Different Name',
      );
      
      final identity3 = VaultIdentity(
        localId: '3',
        publicKey: 'pub2',
        createdAt: now,
        origin: IdentityOrigin.generated,
      );

      expect(identity1, equals(identity2));
      expect(identity1, isNot(equals(identity3)));
      expect(identity1.hashCode, equals(identity2.hashCode));
    });

    test('copyWith should work correctly', () {
      final identity = VaultIdentity(
        localId: '1',
        publicKey: 'pub1',
        createdAt: now,
        origin: IdentityOrigin.generated,
      );

      final updated = identity.copyWith(displayName: 'New Name', isActive: false);

      expect(updated.localId, equals('1'));
      expect(updated.publicKey, equals('pub1'));
      expect(updated.displayName, equals('New Name'));
      expect(updated.isActive, isFalse);
      expect(updated.createdAt, equals(now));
      expect(updated.origin, equals(IdentityOrigin.generated));
    });
  });
}
