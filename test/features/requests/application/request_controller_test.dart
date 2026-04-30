import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/data/fake_signer_service.dart';
import 'package:android_diogel/features/requests/domain/request_provenance.dart';
import 'package:android_diogel/features/requests/domain/request_trust_status.dart';
import 'package:android_diogel/features/requests/domain/signing_action_type.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
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

    test('rejectRequest should mark request as rejected and clear pending', () async {
      final request = createSampleRequest();
      await requestController.acceptRequest(request);
      expect(requestController.pendingRequest, isNotNull);

      await requestController.rejectRequest(request.id);

      expect(requestController.state.requests.first.status, SigningRequestStatus.rejected);
      expect(requestController.pendingRequest, isNull);
    });

    test('approveRequest should fail when vault is locked', () async {
      final request = createSampleRequest();
      await requestController.acceptRequest(request);

      // Vault is initially NoVault (not Unlocked)
      await requestController.approveRequest(request.id);

      expect(requestController.failure, isNotNull);
      expect(requestController.failure!.message, contains('Vault is locked'));
      expect(requestController.state.requests.first.status, SigningRequestStatus.pending);
    });

    test('approveRequest should fail when no active identity exists', () async {
      await vaultController.createVault('1234');
      // Vault is unlocked but no identity created yet
      
      final request = createSampleRequest();
      await requestController.acceptRequest(request);

      await requestController.approveRequest(request.id);

      expect(requestController.failure, isNotNull);
      expect(requestController.failure!.message, contains('No active identity'));
      expect(requestController.state.requests.first.status, SigningRequestStatus.pending);
    });

    test('approveRequest should succeed when vault is unlocked and identity exists', () async {
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
      expect(requestController.state.requests.first.status, SigningRequestStatus.approved);
      expect(requestController.pendingRequest, isNull);
    });
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
      expect(requestController.state.requests.first.status, SigningRequestStatus.failed);
    });
    
    test('injectDemoRequest should add a demo request when identity exists', () async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Demo User');
      
      await requestController.injectDemoRequest();
      
      expect(requestController.state.requests, hasLength(1));
      final request = requestController.pendingRequest!;
      expect(request.provenance.sourceDisplayName, equals('Demo DApp'));
      expect(request.provenance.trustStatus, equals(RequestTrustStatus.unknown));
      expect(request.targetIdentityLocalId, isNotNull);
    });

    test('injectDemoRequest should fail when no identity exists', () async {
      await requestController.injectDemoRequest();
      
      expect(requestController.state.requests, isEmpty);
      expect(requestController.failure, isNotNull);
      expect(requestController.failure!.message, contains('No active identity'));
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
      expect(requestController.state.requests.first.status, SigningRequestStatus.pending);
    });
  });
}
