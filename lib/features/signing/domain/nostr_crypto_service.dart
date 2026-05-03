import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';

abstract interface class NostrCryptoService {
  String derivePublicKey(String privateKeyHex);

  SignedNostrEvent signEvent({
    required String privateKeyHex,
    required NostrEventDraft draft,
  });

  String nip04Encrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String plaintext,
  });

  String nip04Decrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String ciphertext,
  });

  String nip44Encrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String plaintext,
  });

  String nip44Decrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String ciphertext,
  });

  String decryptZapEvent({
    required String privateKeyHex,
    required Map<String, Object?> eventJson,
  });

  bool verifySignedEvent(SignedNostrEvent event);
}
