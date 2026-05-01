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
  String? rejectedError;
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
  Future<void> completeNip55Intent(Map<String, Object?> extras) async {
    completedExtras = extras;
  }

  @override
  Future<void> rejectNip55Intent({String? error}) async {
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
      expect(gateway.completedExtras?['id'], 'external-id');
      expect(gateway.completedExtras?['event'], contains('"sig"'));
    });

    test('rejection calls gateway reject', () async {
      await controller.handleRawIntent(signEventRaw());
      final request = requestController.state.requests.single;

      await requestController.rejectRequest(request.id);
      await controller.rejectSigningRequest(request.id);

      expect(gateway.rejectedError, contains('rejected'));
    });

    test('malformed intent calls gateway reject', () async {
      await controller.handleRawIntent({
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
        'type': 'get_public_key',
        'permissions': '["sign_event"]',
        'callerPackage': 'com.example.app',
      });

      await controller.approvePublicKeyRequest();

      expect(
        gateway.completedExtras?['result'],
        vaultController.state.activeIdentity!.publicKey,
      );
      expect(gateway.completedExtras?['package'], 'io.threenine.androidiogel');
    });

    test('get_public_key rejection completes as rejected', () async {
      await controller.handleRawIntent({'type': 'get_public_key'});

      await controller.rejectPublicKeyRequest();

      expect(gateway.rejectedError, contains('rejected'));
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

      await emptyController.handleRawIntent({'type': 'get_public_key'});

      expect(emptyGateway.rejectedError, contains('select an identity'));
      expect(emptyController.state.pendingPublicKeyRequest, isNull);
    });
  });
}
