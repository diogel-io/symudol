import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/backup/domain/nip49.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// NIP-49 against its own test data and draft-irtf-cfrg-xchacha-03
/// (diogel-io/symudol#25).
void main() {
  test('HChaCha20 matches draft-irtf-cfrg-xchacha-03 §2.2.1', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final nonce = _hex('000000090000004a0000000031415927');

    expect(
      _toHex(hChaCha20(key, nonce)),
      '82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc',
    );
  });

  test('passwords are NFKC-normalised as NIP-49 specifies', () {
    expect(utf8.encode('ÅΩẛ̣'), [
      0xE2, 0x84, 0xAB, 0xE2, 0x84, 0xA6, 0xE1, 0xBA, 0x9B, 0xCC, 0xA3, //
    ]);
    expect(utf8.encode(unorm.nfkc('ÅΩẛ̣')), [
      0xC3, 0x85, 0xCE, 0xA9, 0xE1, 0xB9, 0xA9, //
    ]);
  });

  test('decrypts the NIP-49 test vector', () {
    const ncryptsec =
        'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p';

    final payload = nip49Parse(ncryptsec);
    expect(payload.logN, 16);
    expect(
      _toHex(nip49Decrypt(ncryptsec, 'nostr')),
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
    );
  });

  group('at a low cost, for speed', () {
    final privateKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));

    test('a round trip gives the key back', () {
      final key = nip49DeriveKey('correct horse battery', logN: 4);

      final ncryptsec = nip49Encrypt(privateKey, key);

      expect(ncryptsec, startsWith('ncryptsec1'));
      expect(nip49Decrypt(ncryptsec, 'correct horse battery'), privateKey);
      expect(nip49Parse(ncryptsec).keySecurity, Nip49KeySecurity.unknown.byte);
    });

    test('a wrong passphrase is refused', () {
      final ncryptsec = nip49Encrypt(
        privateKey,
        nip49DeriveKey('correct horse battery', logN: 4),
      );

      expect(
        () => nip49Decrypt(ncryptsec, 'wrong horse battery'),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('a changed key-security byte fails authentication', () {
      final key = nip49DeriveKey('pass phrase here', logN: 4);
      final payload = nip49Parse(nip49Encrypt(privateKey, key));
      final tampered = Nip49Payload(
        payload.logN,
        payload.salt,
        payload.nonce,
        Nip49KeySecurity.notKnownInsecure.byte,
        payload.ciphertext,
      );

      expect(
        () => nip49DecryptWith(tampered, key),
        throwsA(isA<Nip49Exception>()),
      );
      expect(nip49DecryptWith(payload, key), privateKey);
    });

    test('keys sharing one derivation each decrypt on their own', () {
      final key = nip49DeriveKey('shared derivation', logN: 4);
      final other = Uint8List.fromList(List.filled(32, 7));

      final first = nip49Encrypt(privateKey, key);
      final second = nip49Encrypt(other, key);

      expect(nip49Parse(first).nonce, isNot(nip49Parse(second).nonce));
      expect(nip49Decrypt(first, 'shared derivation'), privateKey);
      expect(nip49Decrypt(second, 'shared derivation'), other);
    });

    test('rejects text that is not an ncryptsec', () {
      expect(() => nip49Parse('nsec1abc'), throwsA(isA<Nip49Exception>()));
      expect(() => nip49Parse('not bech32'), throwsA(isA<Nip49Exception>()));
    });
  });
}
