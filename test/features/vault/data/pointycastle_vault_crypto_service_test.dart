import 'dart:typed_data';

import 'package:symudol/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PointyCastleVaultCryptoService();

  // Use minimal Argon2id cost in tests to keep them fast.
  const fastParams = VaultKdfParams(memory: 8, iterations: 1, parallelism: 1);

  group('PointyCastleVaultCryptoService', () {
    test('deriveKek is deterministic for the same pin, salt and params', () {
      final salt = service.generateSalt();

      final kek1 = service.deriveKek('1234', salt, fastParams);
      final kek2 = service.deriveKek('1234', salt, fastParams);

      expect(kek1, equals(kek2));
    });

    test('deriveKek produces different keys for different pins', () {
      final salt = service.generateSalt();

      final kek1 = service.deriveKek('1234', salt, fastParams);
      final kek2 = service.deriveKek('0000', salt, fastParams);

      expect(kek1, isNot(equals(kek2)));
    });

    test('wrapDek/unwrapDek round-trips the DEK', () {
      final salt = service.generateSalt();
      final dek = service.generateDek();
      final kek = service.deriveKek('1234', salt, fastParams);

      final wrapped = service.wrapDek(dek, kek);
      final unwrapped = service.unwrapDek(wrapped, kek);

      expect(unwrapped, equals(dek));
    });

    test('unwrapDek throws on wrong KEK (wrong PIN)', () {
      final salt = service.generateSalt();
      final dek = service.generateDek();
      final correctKek = service.deriveKek('1234', salt, fastParams);
      final wrongKek = service.deriveKek('0000', salt, fastParams);

      final wrapped = service.wrapDek(dek, correctKek);

      expect(
        () => service.unwrapDek(wrapped, wrongKek),
        throwsA(isA<VaultCryptoTamperException>()),
      );
    });

    test('encrypt/decrypt round-trips a string', () {
      final key = service.generateDek();

      final ciphertext = service.encrypt('hello vault', key);
      final plaintext = service.decrypt(ciphertext, key);

      expect(ciphertext, isNot(equals('hello vault')));
      expect(plaintext, equals('hello vault'));
    });

    test('decrypt throws on tampered ciphertext', () {
      final key = service.generateDek();
      final ciphertext = service.encrypt('hello vault', key);

      final tampered =
          '${ciphertext.substring(0, ciphertext.length - 4)}AAAA';

      expect(
        () => service.decrypt(tampered, key),
        throwsA(isA<VaultCryptoTamperException>()),
      );
    });

    group('deriveSubkey (#32)', () {
      test('matches RFC 5869 test case 3 (no salt, no info)', () {
        final ikm = Uint8List.fromList(List.filled(22, 0x0b));

        final subkey = service.deriveSubkey(ikm, '');

        // The first 32 bytes of the test case's 42-byte OKM.
        expect(
          [for (final b in subkey) b.toRadixString(16).padLeft(2, '0')].join(),
          '8da4e775a563c18f715f802a063c5a31'
          'b8a11f5c5ee1879ec3454e5f3c738d2d',
        );
      });

      test('is 32 bytes, the same each time, and not the DEK', () {
        final dek = service.generateDek();

        final a = service.deriveSubkey(dek, 'symudol/test/v1');
        final b = service.deriveSubkey(dek, 'symudol/test/v1');

        expect(a, hasLength(32));
        expect(a, equals(b));
        expect(a, isNot(equals(dek)));
      });

      test('differs for another info or another DEK', () {
        final dek = service.generateDek();
        final key = service.deriveSubkey(dek, 'symudol/test/v1');

        expect(service.deriveSubkey(dek, 'symudol/other/v1'), isNot(key));
        expect(
          service.deriveSubkey(service.generateDek(), 'symudol/test/v1'),
          isNot(key),
        );
      });
    });
  });
}
