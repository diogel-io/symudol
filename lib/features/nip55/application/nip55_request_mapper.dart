import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/requests/domain/request_provenance.dart';
import 'package:symudol/features/requests/domain/request_trust_status.dart';
import 'package:symudol/features/requests/domain/signing_action_type.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';

import '../domain/nip55_failure.dart';
import '../domain/nip55_incoming_request.dart';
import '../domain/nip55_permission_parser.dart';

class Nip55RequestMapper {
  const Nip55RequestMapper();

  SigningRequest mapSignEvent({
    required Nip55IncomingRequest incoming,
    required VaultIdentity activeIdentity,
  }) {
    final eventJson = incoming.eventJson;
    if (eventJson == null) {
      throw const Nip55Failure('NIP-55 sign_event payload is missing');
    }

    final kind = eventJson['kind'];
    if (kind is! int) {
      throw const Nip55Failure('NIP-55 event kind is invalid');
    }

    final currentUser = incoming.currentUser;
    if (currentUser != null && currentUser != activeIdentity.publicKey) {
      throw const Nip55Failure(
        'Requested account does not match active identity.',
      );
    }

    final eventPubkey = eventJson['pubkey'];
    if (eventPubkey != null && eventPubkey != activeIdentity.publicKey) {
      throw const Nip55Failure(
        'Requested event pubkey does not match active identity.',
      );
    }

    final hasClientIdentity =
        incoming.clientIdentity.packageName != null ||
        incoming.clientIdentity.appLabel != null ||
        incoming.clientIdentity.referrer != null;
    final source = hasClientIdentity
        ? incoming.clientIdentity.displayName
        : (incoming.sourceHint?.trim().isNotEmpty == true
              ? 'Source hint: ${incoming.sourceHint!.trim()}'
              : 'Unknown Android caller');
    final parsedPermissions = const Nip55PermissionParser().parse(
      incoming.permissions,
    );
    final sourceIdentifier =
        incoming.clientIdentity.packageName ??
        incoming.sourceHint ??
        incoming.dataUri;

    return SigningRequest(
      id: incoming.localId,
      provenance: RequestProvenance(
        sourceDisplayName: source,
        sourceIdentifier: sourceIdentifier,
        trustStatus: incoming.clientIdentity.provenanceVerified
            ? RequestTrustStatus.knownTrusted
            : RequestTrustStatus.unknown,
      ),
      actionType: SigningActionType.signEvent,
      eventKind: kind,
      eventPayload: _normalizedEventPayload(
        eventJson,
        kind,
        incoming.method.wireName,
        _permissionScopeFor(kind, incoming.permissions),
        parsedPermissions.warnings,
      ),
      targetIdentityPublicKey: activeIdentity.publicKey,
      targetIdentityLocalId: activeIdentity.localId,
      createdAt: incoming.receivedAt,
      status: SigningRequestStatus.pending,
    );
  }

  Map<String, Object?> _normalizedEventPayload(
    Map<String, Object?> eventJson,
    int kind,
    String nip55Method,
    String permissionScope,
    List<String> permissionWarnings,
  ) {
    return {
      'kind': kind,
      'nip55Method': nip55Method,
      'nip55PermissionScope': permissionScope,
      if (eventJson['created_at'] != null)
        'created_at': eventJson['created_at'],
      'tags': eventJson['tags'] ?? const [],
      'content': eventJson['content'],
      if (permissionWarnings.isNotEmpty)
        'permissionWarnings': permissionWarnings,
    };
  }

  String _permissionScopeFor(int kind, String? permissions) {
    final parsed = const Nip55PermissionParser().parse(permissions);
    for (final scope in parsed.scopes) {
      if (scope.wire == 'sign_event:$kind') return scope.wire;
    }
    for (final scope in parsed.scopes) {
      if (scope.wire == 'sign_event') return scope.wire;
    }
    return 'sign_event:$kind';
  }
}
