import 'package:symudol/features/requests/data/real_signer_service.dart';
import 'package:symudol/features/requests/domain/request_failure.dart';
import 'package:symudol/features/requests/domain/request_provenance.dart';
import 'package:symudol/features/requests/domain/request_trust_status.dart';
import 'package:symudol/features/requests/domain/signed_request_result.dart';
import 'package:symudol/features/requests/domain/signing_action_type.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

void main() {
  late FakeVaultStore store;
  late VaultServiceImpl vaultService;
  late RealSignerService signerService;

  setUp(() async {
    store = FakeVaultStore();
    vaultService = VaultServiceImpl(store);
    await vaultService.createVault('1234');
    signerService = RealSignerService(vaultService);
  });

  SigningRequest request({
    required String targetPublicKey,
    required String targetLocalId,
    Map<String, Object?>? payload,
  }) {
    return SigningRequest(
      id: 'req1',
      provenance: const RequestProvenance(
        sourceDisplayName: 'Test App',
        trustStatus: RequestTrustStatus.unknown,
      ),
      actionType: SigningActionType.signEvent,
      eventKind: 1,
      eventPayload:
          payload ??
          {'kind': 1, 'content': 'hello', 'created_at': 1777618800, 'tags': []},
      targetIdentityPublicKey: targetPublicKey,
      targetIdentityLocalId: targetLocalId,
      createdAt: DateTime.utc(2026, 5, 1),
      status: SigningRequestStatus.pending,
    );
  }

  group('RealSignerService', () {
    test('returns success for a valid request', () async {
      final identity = await vaultService.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000001',
      );

      final result = await signerService.sign(
        request(
          targetPublicKey: identity.publicKey,
          targetLocalId: identity.localId,
        ),
      );

      expect(result, isA<SignedRequestSuccess>());
      final success = result as SignedRequestSuccess;
      expect(success.event, isNotNull);
      expect(success.signedPayload['id'], isNotEmpty);
      expect(success.signedPayload['pubkey'], identity.publicKey);
      expect(success.signedPayload['sig'], isNotEmpty);
    });

    test('maps malformed payload to typed failure', () async {
      final identity = await vaultService.createIdentity();
      final result = await signerService.sign(
        request(
          targetPublicKey: identity.publicKey,
          targetLocalId: identity.localId,
          payload: {'kind': 'bad', 'content': 'hello'},
        ),
      );

      expect(result, isA<SignedRequestFailure>());
      expect(
        (result as SignedRequestFailure).failure,
        isA<InvalidRequestFailure>(),
      );
    });

    test('maps locked vault to typed failure', () async {
      final identity = await vaultService.createIdentity();
      await vaultService.lock();

      final result = await signerService.sign(
        request(
          targetPublicKey: identity.publicKey,
          targetLocalId: identity.localId,
        ),
      );

      expect(result, isA<SignedRequestFailure>());
      expect(
        (result as SignedRequestFailure).failure,
        isA<VaultLockedRequestFailure>(),
      );
    });
  });
}
