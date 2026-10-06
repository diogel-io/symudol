import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/request_provenance.dart';
import 'package:symudol/features/requests/domain/request_trust_status.dart';
import 'package:symudol/features/requests/domain/signing_action_type.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';

void main() {
  group('SigningRequest', () {
    test('should construct correctly', () {
      final now = DateTime.now();
      final provenance = RequestProvenance(
        sourceDisplayName: 'Test App',
        sourceIdentifier: 'https://test.app',
        trustStatus: RequestTrustStatus.knownTrusted,
      );

      final request = SigningRequest(
        id: 'req123',
        provenance: provenance,
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'hello'},
        targetIdentityPublicKey: 'pubkey123',
        targetIdentityLocalId: 'local123',
        createdAt: now,
        status: SigningRequestStatus.pending,
      );

      expect(request.id, 'req123');
      expect(request.provenance.sourceDisplayName, 'Test App');
      expect(request.provenance.trustStatus, RequestTrustStatus.knownTrusted);
      expect(request.status, SigningRequestStatus.pending);
      expect(request.eventPayload['content'], 'hello');
    });

    test('should support JSON serialization', () {
      final now = DateTime.utc(2023, 1, 1);
      final provenance = RequestProvenance(
        sourceDisplayName: 'Test App',
        trustStatus: RequestTrustStatus.unknown,
      );

      final request = SigningRequest(
        id: 'req123',
        provenance: provenance,
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'hello'},
        targetIdentityPublicKey: 'pubkey123',
        targetIdentityLocalId: 'local123',
        createdAt: now,
        status: SigningRequestStatus.pending,
      );

      final json = request.toJson();
      final fromJson = SigningRequest.fromJson(json);

      expect(fromJson.id, request.id);
      expect(fromJson.provenance.sourceDisplayName, request.provenance.sourceDisplayName);
      expect(fromJson.provenance.trustStatus, request.provenance.trustStatus);
      expect(fromJson.createdAt, request.createdAt);
      expect(fromJson.status, request.status);
    });

    test('trust status labels should be explicit', () {
      expect(RequestTrustStatus.knownTrusted.name, 'knownTrusted');
      expect(RequestTrustStatus.knownUntrusted.name, 'knownUntrusted');
      expect(RequestTrustStatus.unknown.name, 'unknown');
      expect(RequestTrustStatus.invalid.name, 'invalid');
    });

    test('status labels should be explicit', () {
      expect(SigningRequestStatus.pending.name, 'pending');
      expect(SigningRequestStatus.approved.name, 'approved');
      expect(SigningRequestStatus.rejected.name, 'rejected');
      expect(SigningRequestStatus.failed.name, 'failed');
      expect(SigningRequestStatus.expired.name, 'expired');
    });
  });
}
