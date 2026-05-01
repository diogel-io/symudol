import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';

abstract interface class NostrCryptoService {
  String derivePublicKey(String privateKeyHex);

  SignedNostrEvent signEvent({
    required String privateKeyHex,
    required NostrEventDraft draft,
  });

  bool verifySignedEvent(SignedNostrEvent event);
}
