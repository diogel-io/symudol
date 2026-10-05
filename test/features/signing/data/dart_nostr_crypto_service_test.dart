import 'dart:convert';
import 'dart:typed_data';

import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:bech32/bech32.dart' as bech32;
import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const crypto = DartNostrCryptoService();

  group('DartNostrCryptoService', () {
    test('signs a Nostr event and verifies it', () {
      final keyPairs = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000001',
      );
      final draft = NostrEventDraft(
        kind: 1,
        content: 'hello',
        tags: const [
          ['t', 'diogel'],
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          1777618800 * 1000,
          isUtc: true,
        ),
      );

      final event = crypto.signEvent(
        privateKeyHex: keyPairs.private,
        draft: draft,
      );

      expect(event.pubkey, keyPairs.public);
      expect(crypto.verifySignedEvent(event), isTrue);
    });

    test('event id matches NIP-01 serialization', () {
      final privateKey =
          '0000000000000000000000000000000000000000000000000000000000000001';
      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        1777618800 * 1000,
        isUtc: true,
      );
      final draft = NostrEventDraft(
        kind: 1,
        content: 'hello',
        tags: const [],
        createdAt: createdAt,
      );

      final event = crypto.signEvent(privateKeyHex: privateKey, draft: draft);
      final expectedId = NostrEvent.getEventId(
        kind: draft.kind,
        content: draft.content,
        createdAt: createdAt,
        tags: draft.tags,
        pubkey: event.pubkey,
      );

      expect(event.id, expectedId);
    });

    test('tampered content fails verification', () {
      final event = crypto.signEvent(
        privateKeyHex:
            '0000000000000000000000000000000000000000000000000000000000000001',
        draft: NostrEventDraft(
          kind: 1,
          content: 'hello',
          tags: const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            1777618800 * 1000,
            isUtc: true,
          ),
        ),
      );

      expect(
        crypto.verifySignedEvent(event.copyWith(content: 'tampered')),
        isFalse,
      );
    });

    test('signMessage signs SHA-256 message digest with Schnorr key', () {
      const privateKey =
          '0000000000000000000000000000000000000000000000000000000000000001';
      const message = 'hello sign_message';

      final signature = crypto.signMessage(
        privateKeyHex: privateKey,
        message: message,
      );

      final digest = crypto_hash.sha256
          .convert(utf8.encode(message))
          .toString();
      final pubkey = NostrKeyPairs(private: privateKey).public;
      expect(signature, matches(RegExp(r'^[0-9a-f]{128}$')));
      expect(NostrKeyPairs.verify(pubkey, digest, signature), isTrue);
    });

    test('signMessage refuses an event serialisation (#8)', () {
      const privateKey =
          '0000000000000000000000000000000000000000000000000000000000000001';
      final pubkey = NostrKeyPairs(private: privateKey).public;
      // Its sha256 is the id of a kind-1 event: the signature would sign it.
      final serialised = '[0,"$pubkey",1700000000,1,[],"hi"]';

      expect(
        () => crypto.signMessage(privateKeyHex: privateKey, message: serialised),
        throwsA(isA<NostrCryptoException>()),
      );
    });

    test('NIP-04 encrypts and decrypts between two identities', () {
      final alice = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000001',
      );
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );
      final deterministicCrypto = DartNostrCryptoService(
        randomBytes: (length) => Uint8List.fromList(
          List<int>.generate(length, (index) => index + 1),
        ),
      );

      final ciphertext = deterministicCrypto.nip04Encrypt(
        privateKeyHex: alice.private,
        peerPubkeyHex: bob.public,
        plaintext: 'hello nip04',
      );

      expect(ciphertext, contains('?iv='));
      expect(
        deterministicCrypto.nip04Decrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: alice.public,
          ciphertext: ciphertext,
        ),
        'hello nip04',
      );
    });

    test('NIP-44 matches published v2 test vector', () {
      final deterministicCrypto = DartNostrCryptoService(
        randomBytes: (_) => Uint8List.fromList([...List<int>.filled(31, 0), 1]),
      );
      final sec1 =
          '0000000000000000000000000000000000000000000000000000000000000001';
      final sec2 =
          '0000000000000000000000000000000000000000000000000000000000000002';
      final pub1 = NostrKeyPairs(private: sec1).public;
      final pub2 = NostrKeyPairs(private: sec2).public;
      const payload =
          'AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb';

      expect(
        deterministicCrypto.nip44Encrypt(
          privateKeyHex: sec1,
          peerPubkeyHex: pub2,
          plaintext: 'a',
        ),
        payload,
      );
      expect(
        deterministicCrypto.nip44Decrypt(
          privateKeyHex: sec2,
          peerPubkeyHex: pub1,
          ciphertext: payload,
        ),
        'a',
      );
    });

    test('decryptZapEvent decrypts private zap anon tag for receiver', () {
      const senderPrivateKey =
          '0000000000000000000000000000000000000000000000000000000000000001';
      const receiverPrivateKey =
          '0000000000000000000000000000000000000000000000000000000000000002';
      const createdAt = 1778170497;
      final receiverPubkey = NostrKeyPairs(private: receiverPrivateKey).public;
      final privateZapKey = _privateZapKey(
        signerPrivateKey: senderPrivateKey,
        id: receiverPubkey,
        createdAt: createdAt,
      );
      final privateZapPubkey = NostrKeyPairs(private: privateZapKey).public;
      final privateEventJson = jsonEncode({
        'id': 'a' * 64,
        'pubkey': privateZapPubkey,
        'created_at': createdAt,
        'kind': 9733,
        'tags': [
          ['p', receiverPubkey],
        ],
        'content': 'private zap details',
        'sig': 'b' * 128,
      });
      final anonPayload = _privateZapPayload(
        privateKeyHex: privateZapKey,
        peerPubkeyHex: receiverPubkey,
        plaintext: privateEventJson,
      );

      final decrypted = crypto.decryptZapEvent(
        privateKeyHex: receiverPrivateKey,
        eventJson: {
          'id': 'c' * 64,
          'pubkey': privateZapPubkey,
          'created_at': createdAt,
          'kind': 9734,
          'tags': [
            ['p', receiverPubkey],
            ['anon', anonPayload],
          ],
          'content': '',
          'sig': 'd' * 128,
        },
      );

      expect(jsonDecode(decrypted), jsonDecode(privateEventJson));
    });

    test('decryptZapEvent decrypts NIP-04 format anon tag (Amethyst style)', () {
      final deterministicCrypto = DartNostrCryptoService(
        randomBytes: (length) =>
            Uint8List.fromList(List<int>.generate(length, (index) => index + 1)),
      );
      const senderEphemeralKey =
          '0000000000000000000000000000000000000000000000000000000000000001';
      const receiverPrivateKey =
          '0000000000000000000000000000000000000000000000000000000000000002';
      final senderEphemeralPubkey =
          NostrKeyPairs(private: senderEphemeralKey).public;
      final receiverPubkey =
          NostrKeyPairs(private: receiverPrivateKey).public;
      final privateEventJson = jsonEncode({
        'id': 'a' * 64,
        'pubkey': senderEphemeralPubkey,
        'created_at': 1778170497,
        'kind': 9733,
        'tags': [
          ['p', receiverPubkey],
        ],
        'content': 'private zap message',
        'sig': 'b' * 128,
      });
      // Standard NIP-04 format as sent by clients like Amethyst
      final nip04AnonPayload = deterministicCrypto.nip04Encrypt(
        privateKeyHex: senderEphemeralKey,
        peerPubkeyHex: receiverPubkey,
        plaintext: privateEventJson,
      );

      final decrypted = deterministicCrypto.decryptZapEvent(
        privateKeyHex: receiverPrivateKey,
        eventJson: {
          'id': 'c' * 64,
          'pubkey': senderEphemeralPubkey,
          'created_at': 1778170497,
          'kind': 9734,
          'tags': [
            ['p', receiverPubkey],
            ['anon', nip04AnonPayload],
          ],
          'content': '',
          'sig': 'd' * 128,
        },
      );

      expect(jsonDecode(decrypted), jsonDecode(privateEventJson));
    });

    test('decryptZapEvent keeps legacy NIP-44 content fallback', () {
      final deterministicCrypto = DartNostrCryptoService(
        randomBytes: (_) => Uint8List.fromList([...List<int>.filled(31, 0), 1]),
      );
      final sec1 =
          '0000000000000000000000000000000000000000000000000000000000000001';
      final sec2 =
          '0000000000000000000000000000000000000000000000000000000000000002';
      final pub1 = NostrKeyPairs(private: sec1).public;
      final pub2 = NostrKeyPairs(private: sec2).public;
      final payload = deterministicCrypto.nip44Encrypt(
        privateKeyHex: sec1,
        peerPubkeyHex: pub2,
        plaintext: '{"bolt11":"lnbc..."}',
      );

      expect(
        deterministicCrypto.decryptZapEvent(
          privateKeyHex: sec2,
          eventJson: {'pubkey': pub1, 'content': payload},
        ),
        '{"bolt11":"lnbc..."}',
      );
    });

    test('NIP-44 rejects tampered ciphertext', () {
      final alice = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000001',
      );
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );
      final ciphertext = crypto.nip44Encrypt(
        privateKeyHex: alice.private,
        peerPubkeyHex: bob.public,
        plaintext: 'hello nip44',
      );
      final replacement = ciphertext.endsWith('A') ? 'B' : 'A';
      final tampered =
          ciphertext.substring(0, ciphertext.length - 1) + replacement;

      expect(
        () => crypto.nip44Decrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: alice.public,
          ciphertext: tampered,
        ),
        throwsA(isA<NostrCryptoException>()),
      );
    });

    test('tampered signature fails verification', () {
      final event = crypto.signEvent(
        privateKeyHex:
            '0000000000000000000000000000000000000000000000000000000000000001',
        draft: NostrEventDraft(
          kind: 1,
          content: 'hello',
          tags: const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            1777618800 * 1000,
            isUtc: true,
          ),
        ),
      );

      final replacement = event.sig.startsWith('0') ? '1' : '0';
      final tamperedSig = replacement + event.sig.substring(1);
      expect(
        crypto.verifySignedEvent(event.copyWith(sig: tamperedSig)),
        isFalse,
      );
    });
  });
}

String _privateZapKey({
  required String signerPrivateKey,
  required String id,
  required int createdAt,
}) => crypto_hash.sha256
    .convert(utf8.encode('$signerPrivateKey$id$createdAt'))
    .toString();

String _privateZapPayload({
  required String privateKeyHex,
  required String peerPubkeyHex,
  required String plaintext,
}) {
  final deterministicCrypto = DartNostrCryptoService(
    randomBytes: (length) =>
        Uint8List.fromList(List<int>.generate(length, (index) => index + 1)),
  );
  final nip04Payload = deterministicCrypto.nip04Encrypt(
    privateKeyHex: privateKeyHex,
    peerPubkeyHex: peerPubkeyHex,
    plaintext: plaintext,
  );
  final match = RegExp(r'^(.*)\?iv=([^&]+)$').firstMatch(nip04Payload);
  if (match == null) throw StateError('Malformed test NIP-04 payload');
  final encrypted = base64Decode(match.group(1)!);
  final iv = base64Decode(match.group(2)!);
  return '${_bech32Bytes('pzap', encrypted)}_${_bech32Bytes('iv', iv)}';
}

String _bech32Bytes(String hrp, List<int> bytes) => bech32.bech32.encode(
  bech32.Bech32(hrp, _convertBits(bytes, 8, 5, true)),
  2000,
);

List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxv = (1 << toBits) - 1;
  final maxAcc = (1 << (fromBits + toBits - 1)) - 1;
  for (final value in data) {
    acc = ((acc << fromBits) | value) & maxAcc;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) {
    result.add((acc << (toBits - bits)) & maxv);
  }
  return result;
}
