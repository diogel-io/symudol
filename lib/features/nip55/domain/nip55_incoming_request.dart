import 'nip55_client.dart';
import 'nip55_method.dart';
import 'nip55_payload.dart';
import 'nip55_web_return_options.dart';

class Nip55IncomingRequest {
  final String localId;
  final String requestToken;
  final Nip55Method method;
  final String? content;
  final String? externalId;
  final String? currentUser;
  final String? pubkey;
  final String? permissions;
  final String? sourceHint;
  final Nip55ClientIdentity clientIdentity;
  final String? dataUri;
  final Map<String, Object?>? eventJson;
  final Nip55Payload payload;
  final Nip55WebReturnOptions webReturnOptions;
  final DateTime receivedAt;

  const Nip55IncomingRequest({
    required this.localId,
    required this.requestToken,
    required this.method,
    required this.receivedAt,
    this.content,
    this.externalId,
    this.currentUser,
    this.pubkey,
    this.permissions,
    this.sourceHint,
    this.clientIdentity = const Nip55ClientIdentity(),
    this.dataUri,
    this.eventJson,
    Nip55Payload? payload,
    this.webReturnOptions = const Nip55WebReturnOptions(),
  }) : payload = payload ?? const GetPublicKeyPayload();

  bool get isSignEvent => method == Nip55Method.signEvent;
  bool get isSignMessage => method == Nip55Method.signMessage;
  bool get isGetPublicKey => method == Nip55Method.getPublicKey;
  bool get isCryptoOperation =>
      method == Nip55Method.signMessage ||
      method == Nip55Method.nip04Encrypt ||
      method == Nip55Method.nip04Decrypt ||
      method == Nip55Method.nip44Encrypt ||
      method == Nip55Method.nip44Decrypt ||
      method == Nip55Method.decryptZapEvent;
}
