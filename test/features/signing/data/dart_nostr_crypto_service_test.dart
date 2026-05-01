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
