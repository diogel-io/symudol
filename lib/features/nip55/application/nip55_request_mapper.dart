import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/requests/domain/request_provenance.dart';
import 'package:android_diogel/features/requests/domain/request_trust_status.dart';
import 'package:android_diogel/features/requests/domain/signing_action_type.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';

import '../domain/nip55_failure.dart';
import '../domain/nip55_incoming_request.dart';

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

    final source = incoming.callerPackage?.trim().isNotEmpty == true
        ? incoming.callerPackage!.trim()
        : 'External Android app';

    return SigningRequest(
      id: incoming.localId,
      provenance: RequestProvenance(
        sourceDisplayName: source,
        sourceIdentifier: incoming.callerPackage ?? incoming.dataUri,
        trustStatus: RequestTrustStatus.unknown,
      ),
      actionType: SigningActionType.signEvent,
      eventKind: kind,
      eventPayload: eventJson,
      targetIdentityPublicKey: activeIdentity.publicKey,
      targetIdentityLocalId: activeIdentity.localId,
      createdAt: incoming.receivedAt,
      status: SigningRequestStatus.pending,
    );
  }
}
