import 'dart:convert';

/// Why a `sign_message` request for an event serialisation is refused.
const refusedEventSerialisationMessage =
    'Refused: the message is a Nostr event serialisation';

/// Whether [message] has the shape of a Nostr event's id serialisation,
/// `[0,pubkey,created_at,kind,tags,content]` (NIP-01).
///
/// `sign_message` signs `sha256(message)`, and the sha256 of that
/// serialisation is the event's id: signing it would sign an event of any
/// kind (diogel-io/symudol#8). Deliberately broad: any JSON array of six
/// elements starting with the number 0 counts, whatever the other fields
/// hold. `Nip55NativeCrypto.isNostrEventSerialisation` is the same rule.
bool isNostrEventSerialisation(String message) {
  final Object? decoded;
  try {
    decoded = jsonDecode(message);
  } on FormatException {
    return false;
  }
  return decoded is List && decoded.length == 6 && decoded.first == 0;
}
