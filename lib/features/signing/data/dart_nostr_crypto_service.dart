import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';
import 'package:android_diogel/features/signing/domain/nostr_crypto_service.dart';
import 'package:dart_nostr/dart_nostr.dart';

class DartNostrCryptoService implements NostrCryptoService {
  const DartNostrCryptoService();

  @override
  String derivePublicKey(String privateKeyHex) {
    return NostrKeyPairs(private: privateKeyHex).public;
  }

  @override
  SignedNostrEvent signEvent({
    required String privateKeyHex,
    required NostrEventDraft draft,
  }) {
    final keyPairs = NostrKeyPairs(private: privateKeyHex);
    final event = NostrEvent.fromPartialData(
      kind: draft.kind,
      content: draft.content,
      keyPairs: keyPairs,
      tags: draft.tags,
      createdAt: draft.createdAt,
    );

    final signed = SignedNostrEvent(
      id: event.id!,
      pubkey: event.pubkey,
      createdAt: event.createdAt!.millisecondsSinceEpoch ~/ 1000,
      kind: event.kind!,
      tags: event.tags ?? const [],
      content: event.content ?? '',
      sig: event.sig!,
    );

    if (!verifySignedEvent(signed)) {
      throw const NostrCryptoException(
        'Produced signature failed verification',
      );
    }

    return signed;
  }

  @override
  bool verifySignedEvent(SignedNostrEvent event) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      event.createdAt * 1000,
      isUtc: true,
    );
    final expectedId = NostrEvent.getEventId(
      kind: event.kind,
      content: event.content,
      createdAt: createdAt,
      tags: event.tags,
      pubkey: event.pubkey,
    );

    if (expectedId != event.id) return false;

    return NostrKeyPairs.verify(event.pubkey, event.id, event.sig);
  }
}

class NostrCryptoException implements Exception {
  final String message;

  const NostrCryptoException(this.message);

  @override
  String toString() => 'NostrCryptoException: $message';
}
