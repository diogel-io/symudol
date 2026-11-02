import 'nip46_request.dart';

/// A NIP-46 request waiting for the user's review (diogel-io/symudol#27).
class Nip46PendingMethodRequest {
  final String sessionId;
  final Nip46Request request;
  final bool usesNip04;

  /// The identity active when the request arrived, which the user reviews.
  /// Approving under another identity is refused.
  final String identityLocalId;
  final String identityPubkey;
  final DateTime receivedAt;

  /// The session's client as it described itself at connect. Unauthenticated
  /// metadata, shown as unverified.
  final String clientPubkey;
  final String? clientName;
  final String? clientUrl;

  const Nip46PendingMethodRequest({
    required this.sessionId,
    required this.request,
    required this.usesNip04,
    required this.identityLocalId,
    required this.identityPubkey,
    required this.receivedAt,
    required this.clientPubkey,
    this.clientName,
    this.clientUrl,
  });

  /// Unique across sessions: request ids are chosen by each client.
  String get key => '$sessionId/${request.id}';
}
