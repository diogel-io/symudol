import 'nip55_method.dart';

class Nip55IncomingRequest {
  final String localId;
  final String requestToken;
  final Nip55Method method;
  final String? content;
  final String? externalId;
  final String? currentUser;
  final String? pubkey;
  final String? permissions;
  final String? callerPackage;
  final String? dataUri;
  final Map<String, Object?>? eventJson;
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
    this.callerPackage,
    this.dataUri,
    this.eventJson,
  });

  bool get isSignEvent => method == Nip55Method.signEvent;
  bool get isGetPublicKey => method == Nip55Method.getPublicKey;
}
