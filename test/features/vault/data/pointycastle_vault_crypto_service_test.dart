import 'package:android_diogel/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:android_diogel/features/vault/domain/vault_crypto_service.dart';
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
  });
}