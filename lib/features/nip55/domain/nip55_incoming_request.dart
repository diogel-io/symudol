import 'nip55_client.dart';
import 'nip55_method.dart';
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
    this.webReturnOptions = const Nip55WebReturnOptions(),
  });

  bool get isSignEvent => method == Nip55Method.signEvent;
  bool get isGetPublicKey => method == Nip55Method.getPublicKey;
}
