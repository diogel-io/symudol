import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/nip55/application/nip55_request_mapper.dart';
import 'package:android_diogel/features/nip55/domain/nip55_failure.dart';
import 'package:android_diogel/features/nip55/domain/nip55_incoming_request.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/requests/domain/request_trust_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = Nip55RequestMapper();
  final identity = VaultIdentity(
    localId: 'local-id',
    publicKey: 'a' * 64,
    createdAt: DateTime.utc(2026, 5, 1),
    origin: IdentityOrigin.generated,
    isActive: true,
  );

  Nip55IncomingRequest incoming({String? currentUser}) => Nip55IncomingRequest(
    localId: 'nip55-1',
    requestToken: 'token-1',
    method: Nip55Method.signEvent,
    receivedAt: DateTime.utc(2026, 5, 1),
    currentUser: currentUser,
    callerPackage: 'com.example.app',
    eventJson: const {'kind': 1, 'content': 'hello', 'tags': []},
  );

  group('Nip55RequestMapper', () {
    test('creates SigningRequest with unknown provenance', () {
      final request = mapper.mapSignEvent(
        incoming: incoming(currentUser: identity.publicKey),
        activeIdentity: identity,
      );

      expect(request.id, 'nip55-1');
      expect(request.eventKind, 1);
      expect(request.eventPayload.containsKey('id'), isFalse);
      expect(request.eventPayload.containsKey('sig'), isFalse);
      expect(request.eventPayload.containsKey('pubkey'), isFalse);
      expect(request.targetIdentityPublicKey, identity.publicKey);
      expect(request.provenance.sourceDisplayName, 'com.example.app');
      expect(request.provenance.trustStatus, RequestTrustStatus.unknown);
    });

    test('rejects current_user mismatch', () {
      expect(
        () => mapper.mapSignEvent(
          incoming: incoming(currentUser: 'b' * 64),
          activeIdentity: identity,
        ),
        throwsA(isA<Nip55Failure>()),
      );
    });

    test('rejects event pubkey mismatch', () {
      expect(
        () => mapper.mapSignEvent(
          incoming: Nip55IncomingRequest(
            localId: 'nip55-2',
            requestToken: 'token-2',
            method: Nip55Method.signEvent,
            receivedAt: DateTime.utc(2026, 5, 1),
            eventJson: {
              'kind': 1,
              'content': 'hello',
              'tags': [],
              'pubkey': 'b' * 64,
            },
          ),
          activeIdentity: identity,
        ),
        throwsA(isA<Nip55Failure>()),
      );
    });
  });
}
