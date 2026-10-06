import 'package:symudol/features/requests/application/request_controller.dart';
import 'package:symudol/features/requests/application/request_providers.dart';
import 'package:symudol/features/requests/data/real_signer_service.dart';
import 'package:symudol/features/requests/data/fake_signer_service.dart';
import 'package:symudol/features/requests/domain/request_provenance.dart';
import 'package:symudol/features/requests/domain/request_trust_status.dart';
import 'package:symudol/features/requests/domain/signing_action_type.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  late FakeVaultStore vaultStore;
  late VaultServiceImpl vaultService;
  late VaultController vaultController;
  late FakeSignerService signerService;
  late RequestController requestController;

  setUp(() async {
    vaultStore = FakeVaultStore();
    vaultService = VaultServiceImpl(vaultStore);
    await vaultService.init();
    vaultController = VaultController(vaultService);
    signerService = FakeSignerService();
    requestController = RequestController(vaultController, signerService);
  });

  SigningRequest createSampleRequest({
    String id = '1',
    SigningRequestStatus status = SigningRequestStatus.pending,
    String targetPublicKey = 'pub1',
    String targetLocalId = 'local1',
  }) {
    return SigningRequest(
      id: id,
      provenance: const RequestProvenance(
        sourceDisplayName: 'Test App',
        trustStatus: RequestTrustStatus.unknown,
      ),
      actionType: SigningActionType.signEvent,
      eventKind: 1,
      eventPayload: {'content': 'hello'},
      targetIdentityPublicKey: targetPublicKey,
      targetIdentityLocalId: targetLocalId,
      createdAt: DateTime.now(),
      status: status,
    );
  }

  group('RequestController', () {
    test('initial state should have no requests', () {
      expect(requestController.state.requests, isEmpty);
      expect(requestController.pendingRequest, isNull);
    });

    test('acceptRequest should add request to state', () async {
      final request = createSampleRequest();
      await requestController.acceptRequest(request);

      expect(requestController.state.requests, hasLength(1));
      expect(requestController.pendingRequest, equals(request));
    });

    test(
      'rejectRequest should mark request as rejected and clear pending',
      () async {
        final request = createSampleRequest();
        await requestController.acceptRequest(request);
        expect(requestController.pendingRequest, isNotNull);

        await requestController.rejectRequest(request.id);

        expect(
          requestController.state.requests.first.status,
          SigningRequestStatus.rejected,
        );
        expect(requestController.pendingRequest, isNull);
      },
    );

    test('approveRequest should fail when vault is locked', () async {
      final request = createSampleRequest();
      await requestController.acceptRequest(request);

      // Vault is initially NoVault (not Unlocked)
      await requestController.approveRequest(request.id);

      expect(requestController.failure, isNotNull);
      expect(requestController.failure!.message, contains('Vault is locked'));
      expect(
        requestController.state.requests.first.status,
        SigningRequestStatus.pending,
      );
    });

    test('approveRequest should fail when no active identity exists', () async {
      await vaultController.createVault('1234');
      // Vault is unlocked but no identity created yet

      final request = createSampleRequest();
      await requestController.acceptRequest(request);

      await requestController.approveRequest(request.id);

      expect(requestController.failure, isNotNull);
      expect(
        requestController.failure!.message,
        contains('No active identity'),
      );
      expect(
        requestController.state.requests.first.status,
        SigningRequestStatus.pending,
      );
    });

    test(
      'approveRequest should succeed when vault is unlocked and identity exists',
      () async {
        await vaultController.createVault('1234');
        await vaultController.createIdentity(displayName: 'Test');
        final activeIdentity = vaultController.state.activeIdentity!;

        final request = createSampleRequest(
          targetPublicKey: activeIdentity.publicKey,
          targetLocalId: activeIdentity.localId,
        );
        await requestController.acceptRequest(request);

        await requestController.approveRequest(request.id);

        expect(requestController.failure, isNull);
        expect(
          requestController.state.requests.first.status,
          SigningRequestStatus.approved,
        );
        expect(requestController.pendingRequest, isNull);
      },
    );

    test(
      'approveRequest stores signed event result for real signer success',
      () async {
        await vaultController.createVault('1234');
        await vaultController.createIdentity(displayName: 'Test');
        final activeIdentity = vaultController.state.activeIdentity!;
        requestController = RequestController(
          vaultController,
          RealSignerService(vaultService),
        );

        final request = createSampleRequest(
          targetPublicKey: activeIdentity.publicKey,
          targetLocalId: activeIdentity.localId,
        );
        await requestController.acceptRequest(request);

        await requestController.approveRequest(request.id);

        expect(requestController.failure, isNull);
        expect(
          requestController.state.requests.first.status,
          SigningRequestStatus.approved,
        );
        final event = requestController.state.signedEvents[request.id]!;
        expect(event.id, isNotEmpty);
        expect(event.pubkey, activeIdentity.publicKey);
        expect(event.sig, isNotEmpty);
      },
    );

    test('approveRequest should fail when signer service fails', () async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test');
      final activeIdentity = vaultController.state.activeIdentity!;

      // Setup failing signer
      signerService = FakeSignerService(shouldFail: true);
      requestController = RequestController(vaultController, signerService);

      final request = createSampleRequest(
        targetPublicKey: activeIdentity.publicKey,
        targetLocalId: activeIdentity.localId,
      );
      await requestController.acceptRequest(request);

      await requestController.approveRequest(request.id);

      expect(requestController.failure, isNotNull);
      expect(requestController.failure!.message, contains('Fake signer error'));
      expect(
        requestController.state.requests.first.status,
        SigningRequestStatus.failed,
      );
    });

    test('dismissRequest clears a failed request from active work', () async {
      final failedRequest = createSampleRequest(
        id: 'failed',
        status: SigningRequestStatus.failed,
      );
      final pendingRequest = createSampleRequest(id: 'pending');
      await requestController.acceptRequest(failedRequest);
      await requestController.acceptRequest(pendingRequest);

      final container = ProviderContainer(
        overrides: [
          requestControllerProvider.overrideWith((ref) => requestController),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(activeRequestProvider)?.id, 'failed');

      await requestController.dismissRequest(failedRequest.id);

      expect(container.read(activeRequestProvider)?.id, 'pending');
      expect(
        requestController.state.requests.first.status,
        SigningRequestStatus.rejected,
      );
    });

    test('approveRequest should handle signer service exceptions', () async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test');
      final activeIdentity = vaultController.state.activeIdentity!;

      // Setup throwing signer
      signerService = FakeSignerService(shouldThrow: true);
      requestController = RequestController(vaultController, signerService);

      final request = createSampleRequest(
        targetPublicKey: activeIdentity.publicKey,
        targetLocalId: activeIdentity.localId,
      );
      await requestController.acceptRequest(request);

      try {
        await requestController.approveRequest(request.id);
      } catch (_) {
        // Expected if not handled
      }

      // If handled, isLoading should be false, failure should be set, and status should be failed
      expect(requestController.state.isLoading, isFalse);
      expect(requestController.failure, isNotNull);
      expect(
        requestController.state.requests.first.status,
        SigningRequestStatus.failed,
      );
    });

    test('approveRequest should fail when identity mismatch occurs', () async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test');
      // activeIdentity will have some publicKey and localId

      final request = createSampleRequest(
        id: 'wrong-id',
        targetPublicKey: 'mismatch-pubkey',
        targetLocalId: 'mismatch-localid',
      );
      await requestController.acceptRequest(request);

      await requestController.approveRequest(request.id);

      expect(requestController.failure, isNotNull);
      expect(requestController.failure!.message, contains('Identity mismatch'));
      expect(
        requestController.state.requests.first.status,
        SigningRequestStatus.pending,
      );
    });

    test(
      'activeRequestProvider does not let signed approvals block pending requests',
      () async {
        await vaultController.createVault('1234');
        await vaultController.createIdentity(displayName: 'Test');
        final activeIdentity = vaultController.state.activeIdentity!;
        requestController = RequestController(
          vaultController,
          RealSignerService(vaultService),
        );

        final approvedRequest = createSampleRequest(
          id: 'approved',
          targetPublicKey: activeIdentity.publicKey,
          targetLocalId: activeIdentity.localId,
        );
        final pendingRequest = createSampleRequest(
          id: 'pending',
          targetPublicKey: activeIdentity.publicKey,
          targetLocalId: activeIdentity.localId,
        );

        await requestController.acceptRequest(approvedRequest);
        await requestController.approveRequest(approvedRequest.id);
        await requestController.acceptRequest(pendingRequest);

        final container = ProviderContainer(
          overrides: [
            requestControllerProvider.overrideWith((ref) => requestController),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(activeRequestProvider)?.id, pendingRequest.id);
      },
    );
  });
}
