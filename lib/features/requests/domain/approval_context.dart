import 'dart:convert';

import 'package:symudol/features/nip46/domain/nip46_method.dart';
import 'package:symudol/features/nip46/domain/nip46_pending_method_request.dart';
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
/// (diogel-io/symudol#27). Decisions are just once: remembering them is #28.
class RemoteSignerApprovalContext extends ApprovalContext {
  final Nip46PendingMethodRequest pending;

  /// For `sign_event`: the event as it will be signed, only its signed fields,
  /// with the defaults the controller applies (the active pubkey, and kind 1
  /// when none is given), so the review shows what is signed. Null for other methods, or when the
  /// event JSON is invalid, which the controller refuses on approve.
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
        final raw = request.optionalParam(0);
        final decoded = _decodeEvent(raw);
        if (decoded == null) {
          return RemoteSignerApprovalContext._(pending: pending, content: raw);
        }
        final event = _signedFields(decoded, pending.identityPubkey);
        return RemoteSignerApprovalContext._(
          pending: pending,
          eventPayload: event,
          eventReview: const NostrEventPayloadParser().review(event),
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

  /// Only the fields the controller signs, as it signs them. Anything else in
  /// the client's JSON is dropped, so a client cannot put its own text where
  /// the screen shows app data, such as the NIP-55 method or permission
  /// warnings.
  static Map<String, Object?> _signedFields(
    Map<String, Object?> event,
    String activePubkey,
  ) {
    final pubkey = event['pubkey'];
    final kind = event['kind'];
    final content = event['content'];
    final tags = event['tags'];
    return {
      'pubkey': pubkey is String && pubkey.isNotEmpty ? pubkey : activePubkey,
      'kind': kind is int ? kind : 1,
      'content': content is String ? content : '',
      'tags': tags is List
          ? tags
                .whereType<List>()
                .map((t) => t.map((e) => e.toString()).toList())
                .toList()
          : const <List<String>>[],
      if (event['created_at'] is int) 'created_at': event['created_at'],
    };
  }

  static Map<String, Object?>? _decodeEvent(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      return null;
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

  bool get canRemember => false;

  @override
  String get requestKey => pending.key;
}
