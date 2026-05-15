import 'dart:convert';

import 'nip55_failure.dart';

sealed class Nip55Payload {
  const Nip55Payload();
}

final class GetPublicKeyPayload extends Nip55Payload {
  const GetPublicKeyPayload();
}

final class SignEventPayload extends Nip55Payload {
  final Map<String, Object?> unsignedEvent;

  const SignEventPayload(this.unsignedEvent);
}

final class SignMessagePayload extends Nip55Payload {
  final String message;

  const SignMessagePayload(this.message);
}

sealed class Nip55PeerPayload extends Nip55Payload {
  final String content;
  final String peerPubkey;

  const Nip55PeerPayload({required this.content, required this.peerPubkey});
}

final class Nip04EncryptPayload extends Nip55PeerPayload {
  const Nip04EncryptPayload({
    required super.content,
    required super.peerPubkey,
  });
}

final class Nip04DecryptPayload extends Nip55PeerPayload {
  const Nip04DecryptPayload({
    required super.content,
    required super.peerPubkey,
  });
}

final class Nip44EncryptPayload extends Nip55PeerPayload {
  const Nip44EncryptPayload({
    required super.content,
    required super.peerPubkey,
  });
}

final class Nip44DecryptPayload extends Nip55PeerPayload {
  const Nip44DecryptPayload({
    required super.content,
    required super.peerPubkey,
  });
}

final class DecryptZapEventPayload extends Nip55Payload {
  final Map<String, Object?> eventJson;

  const DecryptZapEventPayload(this.eventJson);
}

Map<String, Object?> decodeNip55JsonObject({
  required String methodLabel,
  required String content,
}) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw Nip55ParseException('$methodLabel content must be a JSON object');
    }
    return decoded.cast<String, Object?>();
  } on Nip55ParseException {
    rethrow;
  } catch (error) {
    throw Nip55ParseException('Malformed $methodLabel JSON: $error');
  }
}
