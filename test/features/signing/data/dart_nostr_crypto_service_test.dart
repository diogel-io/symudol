import 'dart:typed_data';

import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
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

    test('decryptZapEvent decrypts NIP-44 event content from event pubkey', () {
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
