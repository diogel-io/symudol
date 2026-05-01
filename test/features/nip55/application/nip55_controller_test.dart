import 'package:android_diogel/features/nip55/application/nip55_controller.dart';
import 'package:android_diogel/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/data/real_signer_service.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

class FakeNip55Gateway implements Nip55Gateway {
  Map<String, Object?>? initial;
  Map<String, Object?>? latest;
  Map<String, Object?>? completedExtras;
  String? completedToken;
  String? rejectedError;
  String? rejectedToken;
  void Function(Map<String, Object?> raw)? handler;

  @override
  void setIncomingIntentHandler(
    void Function(Map<String, Object?> raw)? handler,
  ) {
    this.handler = handler;
  }

  @override
  Future<Map<String, Object?>?> getInitialNip55Intent() async {
    final value = initial;
    initial = null;
    return value;
  }

  @override
  Future<Map<String, Object?>?> consumeLatestNip55Intent() async {
    final value = latest;
    latest = null;
    return value;
  }

  @override
  Future<void> completeNip55Intent({
    required String requestToken,
    required Map<String, Object?> extras,
  }) async {
    completedToken = requestToken;
    completedExtras = extras;
  }

  @override
  Future<void> rejectNip55Intent({
    required String requestToken,
    String? error,
  }) async {
    rejectedToken = requestToken;
    rejectedError = error;
  }
}

void main() {
  late FakeVaultStore store;
  late VaultServiceImpl vaultService;
  late VaultController vaultController;
  late RequestController requestController;
  late FakeNip55Gateway gateway;
  late Nip55Controller controller;

  setUp(() async {
    store = FakeVaultStore();
    vaultService = VaultServiceImpl(store);
    vaultController = VaultController(vaultService);
    await vaultController.createVault('1234');
    await vaultController.importIdentity(
      '0000000000000000000000000000000000000000000000000000000000000001',
      displayName: 'User',
    );
    requestController = RequestController(
      vaultController,
      RealSignerService(vaultService),
    );
    gateway = FakeNip55Gateway();
    controller = Nip55Controller(
      gateway: gateway,
      vaultController: vaultController,
      requestController: requestController,
    );
  });

  Map<String, Object?> signEventRaw({String? id = 'external-id'}) => {
    'requestToken': 'token-$id',
    'type': 'sign_event',
    'content': '{"kind":1,"content":"hello","tags":[]}',
    'id': id,
    'currentUser': vaultController.state.activeIdentity!.publicKey,
    'callerPackage': 'com.example.app',
  };

  group('Nip55Controller', () {
    test('initial sign_event is accepted into request controller', () async {
      gateway.initial = signEventRaw();

      await controller.consumePendingNativeIntent();

      expect(requestController.state.requests, hasLength(1));
      expect(
        requestController.state.requests.single.provenance.sourceDisplayName,
        'com.example.app',
      );
      expect(
        controller.state.pendingSigningRequestId,
        requestController.state.requests.single.id,
      );
    });

    test('approval completes gateway with signature id and event', () async {
      await controller.handleRawIntent(signEventRaw());
      final request = requestController.state.requests.single;

      await requestController.approveRequest(request.id);
      await controller.completeApprovedSigningRequest(request.id);

      expect(gateway.completedExtras?['result'], isNotEmpty);
      expect(gateway.completedToken, 'token-external-id');
      expect(gateway.completedExtras?['id'], 'external-id');
      expect(gateway.completedExtras?['event'], contains('"sig"'));
    });

    test('signing failure rejects external caller safely', () async {
      await controller.handleRawIntent({
        'requestToken': 'token-fail',
        'type': 'sign_event',
        'content': '{"kind":1,"content":42,"tags":[]}',
        'id': 'fail',
        'currentUser': vaultController.state.activeIdentity!.publicKey,
        'callerPackage': 'com.example.app',
      });
      final request = requestController.state.requests.single;

      await requestController.approveRequest(request.id);
      await controller.completeApprovedSigningRequest(request.id);

      expect(gateway.completedExtras, isNull);
      expect(gateway.rejectedToken, 'token-fail');
      expect(gateway.rejectedError, 'Signing failed. No event was returned.');
      expect(controller.state.pendingSigningRequestId, isNull);
    });

    test('rejection calls gateway reject', () async {
      await controller.handleRawIntent(signEventRaw());
      final request = requestController.state.requests.single;

      await requestController.rejectRequest(request.id);
      await controller.rejectSigningRequest(request.id);

      expect(gateway.rejectedError, contains('rejected'));
      expect(gateway.rejectedToken, 'token-external-id');
    });

    test('malformed intent calls gateway reject', () async {
      await controller.handleRawIntent({
        'requestToken': 'bad-token',
        'type': 'sign_event',
        'content': '{bad',
      });

      expect(gateway.rejectedError, isNotNull);
      expect(requestController.state.requests, isEmpty);
    });

    test('concurrent intent is rejected as busy', () async {
      await controller.handleRawIntent(signEventRaw());
      await controller.handleRawIntent(signEventRaw(id: 'second'));

      expect(gateway.rejectedError, contains('already reviewing'));
      expect(requestController.state.requests, hasLength(1));
    });

    test('get_public_key approval returns pubkey', () async {
      await controller.handleRawIntent({
        'requestToken': 'pk-token',
        'type': 'get_public_key',
        'permissions': '["sign_event"]',
        'callerPackage': 'com.example.app',
      });

      await controller.approvePublicKeyRequest();

      expect(
        gateway.completedExtras?['result'],
        vaultController.state.activeIdentity!.publicKey,
      );
      expect(gateway.completedToken, 'pk-token');
      expect(gateway.completedExtras?['package'], 'io.threenine.androidiogel');
    });

    test('get_public_key rejection completes as rejected', () async {
      await controller.handleRawIntent({
        'requestToken': 'pk-token',
        'type': 'get_public_key',
      });

      await controller.rejectPublicKeyRequest();

      expect(gateway.rejectedError, contains('rejected'));
      expect(gateway.rejectedToken, 'pk-token');
    });

    test('get_public_key with no identity fails safely', () async {
      final emptyVaultService = VaultServiceImpl(FakeVaultStore());
      final emptyVaultController = VaultController(emptyVaultService);
      await emptyVaultController.createVault('1234');
      final emptyRequestController = RequestController(
        emptyVaultController,
        RealSignerService(emptyVaultService),
      );
      final emptyGateway = FakeNip55Gateway();
      final emptyController = Nip55Controller(
        gateway: emptyGateway,
        vaultController: emptyVaultController,
        requestController: emptyRequestController,
      );

      await emptyController.handleRawIntent({
        'requestToken': 'pk-token',
        'type': 'get_public_key',
      });

      expect(emptyGateway.rejectedError, contains('Select an identity'));
      expect(emptyController.state.pendingPublicKeyRequest, isNull);
    });

    test('locked vault keeps request pending until unlock', () async {
      final activePubkey = vaultController.state.activeIdentity!.publicKey;
      await vaultController.lock();

      await controller.handleRawIntent({
        'requestToken': 'token-locked',
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'id': 'locked',
        'currentUser': activePubkey,
        'callerPackage': 'com.example.app',
      });

      expect(gateway.rejectedError, isNull);
      expect(controller.state.isWaitingForUnlock, isTrue);

      await vaultController.unlock('1234');
      await controller.resumePendingAfterUnlock();

      expect(requestController.state.requests, hasLength(1));
      expect(controller.state.pendingSigningRequestId, isNotNull);
    });

    test('locked pending request can be cancelled', () async {
      final activePubkey = vaultController.state.activeIdentity!.publicKey;
      await vaultController.lock();

      await controller.handleRawIntent({
        'requestToken': 'token-cancel',
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'id': 'cancel',
        'currentUser': activePubkey,
      });

      await controller.cancelPendingExternalRequest();

      expect(gateway.rejectedToken, 'token-cancel');
      expect(gateway.rejectedError, contains('cancelled'));
      expect(controller.state.pendingIncoming, isNull);
    });

    test('locked pending request times out', () async {
      final activePubkey = vaultController.state.activeIdentity!.publicKey;
      await vaultController.lock();
      final timeoutGateway = FakeNip55Gateway();
      final timeoutController = Nip55Controller(
        gateway: timeoutGateway,
        vaultController: vaultController,
        requestController: requestController,
        pendingUnlockTimeout: const Duration(milliseconds: 1),
      );

      await timeoutController.handleRawIntent({
        'requestToken': 'token-timeout',
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'id': 'timeout',
        'currentUser': activePubkey,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(timeoutGateway.rejectedToken, 'token-timeout');
      expect(timeoutGateway.rejectedError, contains('timed out'));
      expect(timeoutController.state.pendingIncoming, isNull);
      timeoutController.dispose();
    });
  });
}
