import 'package:symudol/features/nip46/domain/nip46_method.dart';
import 'package:symudol/features/nip46/domain/nip46_pending_method_request.dart';
import 'package:symudol/features/nip46/domain/nip46_sign_event.dart';
import 'package:symudol/features/nip55/domain/nip55_incoming_request.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_parser.dart';
import 'package:symudol/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';

sealed class ApprovalContext {
  String get requestKey;
}

class SigningApprovalContext extends ApprovalContext {
  final SigningRequest request;
  final NostrEventPayloadReview? eventReview;
  final bool isNip55Request;
  final bool canRemember;
  final SignedNostrEvent? signedEvent;

  SigningApprovalContext({
    required this.request,
    required this.eventReview,
    required this.isNip55Request,
    required this.canRemember,
    this.signedEvent,
  });

  bool get isFailed => request.status == SigningRequestStatus.failed;

  @override
  String get requestKey => request.id;
}

class PublicKeyApprovalContext extends ApprovalContext {
  final Nip55IncomingRequest request;
  final Nip55ParsedPermissions parsedPermissions;
  final bool canRemember;

  /// The active identity's key, which approving shares. Not the request's
  /// current_user: NIP-55 get_public_key carries none (diogel-io/workspace#39).
  final String? publicKeyToShare;

  PublicKeyApprovalContext({
    required this.request,
    required this.parsedPermissions,
    required this.canRemember,
    required this.publicKeyToShare,
  });

  @override
  String get requestKey => request.requestToken;
}

class CryptoApprovalContext extends ApprovalContext {
  final Nip55IncomingRequest request;
  final bool canRemember;

  CryptoApprovalContext({
    required this.request,
    required this.canRemember,
  });

  @override
  String get requestKey => request.requestToken;
}

/// A request from a NIP-46 client over a remote signer connection
/// (diogel-io/symudol#27). Its decision can be remembered (#28).
class RemoteSignerApprovalContext extends ApprovalContext {
  final Nip46PendingMethodRequest pending;

  /// For `sign_event`: the event as it will be signed, from
  /// [Nip46SignEvent], the parser the controller signs with. Null for other
  /// methods.
  final Map<String, Object?>? eventPayload;
  final NostrEventPayloadReview? eventReview;

  /// For encrypt and decrypt: the other party's pubkey.
  final String? peerPubkey;

  /// The plaintext or ciphertext, the zap event, or invalid event JSON.
  final String? content;

  RemoteSignerApprovalContext._({
    required this.pending,
    this.eventPayload,
    this.eventReview,
    this.peerPubkey,
    this.content,
  });

  factory RemoteSignerApprovalContext.fromPending(
    Nip46PendingMethodRequest pending,
  ) {
    final request = pending.request;
    switch (request.method) {
      case Nip46Method.signEvent:
        // The controller refuses a sign_event it cannot parse before queueing
        // it, so this is the event that approving signs.
        final Map<String, Object?> event;
        try {
          event = Nip46SignEvent.parse(
            request.optionalParam(0),
            activePubkey: pending.identityPubkey,
          ).reviewPayload;
        } on Nip46SignEventException {
          return RemoteSignerApprovalContext._(
            pending: pending,
            content: request.optionalParam(0),
          );
        }
        return RemoteSignerApprovalContext._(
          pending: pending,
          eventPayload: event,
          // What remembering would keep: this kind only (#28). Given to the
          // review alone, so the raw JSON stays what is signed.
          eventReview: const NostrEventPayloadParser().review({
            ...event,
            'nip55PermissionScope': 'sign_event:${event['kind']}',
          }),
        );
      case Nip46Method.decryptZapEvent:
        return RemoteSignerApprovalContext._(
          pending: pending,
          content: request.optionalParam(0),
        );
      default:
        return RemoteSignerApprovalContext._(
          pending: pending,
          peerPubkey: request.optionalParam(0),
          content: request.optionalParam(1),
        );
    }
  }

  Nip46Method get method => pending.request.method;

  /// The client's name, or a short form of its key when it gave none.
  String get clientDisplayName {
    final name = pending.clientName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final key = pending.clientPubkey;
    return key.length > 12 ? '${key.substring(0, 8)}…' : 'Remote client';
  }

  /// Every reviewed NIP-46 request can be remembered: a `sign_event` always
  /// has a kind by now, and a decision covers that kind only (#28).
  bool get canRemember => true;

  @override
  String get requestKey => pending.key;
}
