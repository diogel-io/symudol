import 'package:android_diogel/features/nip55/domain/nip55_incoming_request.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_parser.dart';
import 'package:android_diogel/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';

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

  PublicKeyApprovalContext({
    required this.request,
    required this.parsedPermissions,
    required this.canRemember,
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
