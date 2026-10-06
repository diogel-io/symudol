import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:android_diogel/features/nip55/application/nip55_controller.dart';
import 'package:android_diogel/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:android_diogel/features/nip55/domain/nip55_approval_timeframe.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client_permission.dart';
import 'package:android_diogel/features/nip55/domain/nip55_incoming_request.dart';
import 'package:android_diogel/features/nip55/domain/nip55_intent_parser.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_decision.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_scope.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_store.dart';
import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/application/request_providers.dart';
import 'package:android_diogel/features/requests/data/real_signer_service.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:android_diogel/features/signing/domain/nostr_event_serialisation.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

class FakeNip55PermissionStore implements Nip55PermissionStore {
  final grants = <Nip55PermissionGrant>[];

  @override
  Future<void> clearAll() async => grants.clear();

  @override
  Future<void> deleteAllForPackage(String packageName) async {
    grants.removeWhere((grant) => grant.packageName == packageName);
  }

  @override
  Future<void> deleteGrant(String id) async {
    grants.removeWhere((grant) => grant.id == id);
  }

  @override
  Future<List<Nip55PermissionGrant>> listGrants() async => List.of(grants);

  @override
  Future<void> saveGrant(Nip55PermissionGrant grant) async {
    grants.removeWhere((existing) => existing.id == grant.id);
    grants.add(grant);
  }
}

class SlowNip55PermissionStore extends FakeNip55PermissionStore {
  final allowListGrants = Completer<void>();

  @override
  Future<List<Nip55PermissionGrant>> listGrants() async {
    await allowListGrants.future;
    return super.listGrants();
  }
}

class FakeNip55Gateway implements Nip55Gateway {
  Map<String, Object?>? initial;
  Map<String, Object?>? latest;
  Map<String, Object?>? completedExtras;
  String? completedToken;
  final completedTokens = <String>[];
  final completedExtrasByToken = <String, Map<String, Object?>>{};
  String? rejectedError;
  String? rejectedToken;
  final rejectedTokens = <String>[];
  final rejectedErrorsByToken = <String, String?>{};
  void Function(Map<String, Object?> raw)? handler;
  Future<Map<String, Object?>?> Function(Map<String, Object?> raw)?
  providerQueryHandler;

  @override
  void setIncomingIntentHandler(
    void Function(Map<String, Object?> raw)? handler,
  ) {
    this.handler = handler;
  }

  @override
  void setProviderQueryHandler(
    Future<Map<String, Object?>?> Function(Map<String, Object?> raw)? handler,
  ) {
    providerQueryHandler = handler;
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
    completedTokens.add(requestToken);
    completedExtrasByToken[requestToken] = extras;
  }

  @override
  Future<void> rejectNip55Intent({
    required String requestToken,
    String? error,
  }) async {
    rejectedToken = requestToken;
    rejectedError = error;
    rejectedTokens.add(requestToken);
    rejectedErrorsByToken[requestToken] = error;
  }

  @override
  Future<Uint8List?> getAppIcon(String packageName) async => null;
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
      vaultService: vaultService,
      requestController: requestController,
    );
  });

  Map<String, Object?> signEventRaw({
    String? id = 'external-id',
    int kind = 1,
  }) => {
    'requestToken': 'token-$id',
    'type': 'sign_event',
    'content': '{"kind":$kind,"content":"hello","tags":[]}',
    'id': id,
    'currentUser': vaultController.state.activeIdentity!.publicKey,
    'sourceHint': 'com.example.app',
  };

  group('Nip55Controller', () {
    test('initial sign_event is accepted into request controller', () async {
      gateway.initial = signEventRaw();

      await controller.consumePendingNativeIntent();

      expect(requestController.state.requests, hasLength(1));
      expect(
        requestController.state.requests.single.provenance.sourceDisplayName,
        'Source hint: com.example.app',
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

    test(
      'sign_event approve and remember persists scoped allow grant',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final request = requestController.state.requests.single;

        await permissionController.approveSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(permissionStore.grants, hasLength(1));
        final grant = permissionStore.grants.single;
        expect(grant.packageName, 'com.example.app');
        expect(grant.certificateSha256, 'AA:BB');
        expect(grant.decision, Nip55PermissionDecision.allow);
        expect(grant.scope, isA<SignEventScope>());
        expect((grant.scope as SignEventScope).kind, 1);
        expect(grant.expiresAt, isNull);
        expect(gateway.completedExtras?['event'], contains('"sig"'));
      },
    );

    test(
      'sign_event reject and remember persists scoped reject grant',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
        });
        final request = requestController.state.requests.single;

        await requestController.rejectRequest(request.id);
        await permissionController.rejectSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(permissionStore.grants, hasLength(1));
        expect(
          permissionStore.grants.single.decision,
          Nip55PermissionDecision.reject,
        );
        expect(gateway.rejectedToken, 'token-external-id');
      },
    );

    test(
      'failed sign_event approve and remember does not persist allow grant',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'token-fail',
          'type': 'sign_event',
          'content': '{"kind":1,"content":42,"tags":[]}',
          'id': 'fail',
          'currentUser': vaultController.state.activeIdentity!.publicKey,
          'callingPackage': 'com.example.app',
        });
        final request = requestController.state.requests.single;

        await permissionController.approveSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(permissionStore.grants, isEmpty);
        expect(gateway.rejectedToken, 'token-fail');
      },
    );

    test(
      'remembered allow grant auto-approves without an active approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'grant-1',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        // Bug fix: saved grants now auto-approve outside the approval session.
        expect(gateway.completedExtras?['event'], contains('"sig"'));
        expect(permissionController.state.pendingSigningRequestId, isNull);
      },
    );

    test(
      'remembered kind 22242 signs immediately outside approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'grant-client-auth',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(22242),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(gateway.completedToken, 'token-auth');
        expect(gateway.completedExtras?['event'], contains('"kind":22242'));
        expect(permissionController.state.pendingSigningRequestId, isNull);
        expect(
          requestController.state.requests.where(
            (request) => request.status == SigningRequestStatus.pending,
          ),
          isEmpty,
        );
      },
    );

    test(
      'busy controller auto-completes remembered kind 22242 burst request',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'grant-client-auth',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(22242),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'interactive', kind: 1),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(permissionController.state.pendingSigningRequestId, isNotNull);

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-one', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-two', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(
          gateway.completedTokens,
          containsAll(['token-auth-one', 'token-auth-two']),
        );
        expect(gateway.rejectedTokens, isNot(contains('token-auth-one')));
        expect(gateway.rejectedTokens, isNot(contains('token-auth-two')));
        expect(permissionController.state.pendingSigningRequestId, isNotNull);
      },
    );

    test(
      'kind 22242 burst waits for first sign and remember instead of busy rejecting',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-first', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final first = requestController.state.requests.single;

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-second', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-third', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(gateway.rejectedTokens, isEmpty);
        expect(gateway.completedTokens, isEmpty);

        await permissionController.approveSigningRequest(
          first.id,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(
          gateway.completedTokens,
          containsAll([
            'token-auth-first',
            'token-auth-second',
            'token-auth-third',
          ]),
        );
        expect(gateway.rejectedTokens, isEmpty);
        expect(
          gateway.completedExtrasByToken['token-auth-second']?['event'],
          contains('"kind":22242'),
        );
      },
    );

    test(
      'kind 22242 burst rejects deferred auth when approval is not remembered',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-first', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final first = requestController.state.requests.single;

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-second', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'auth-third', kind: 22242),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        await permissionController.approveSigningRequest(first.id);

        expect(gateway.completedTokens, contains('token-auth-first'));
        expect(
          gateway.rejectedTokens,
          containsAll(['token-auth-second', 'token-auth-third']),
        );
        expect(
          gateway.rejectedErrorsByToken['token-auth-second'],
          'Client authentication request was not remembered.',
        );
      },
    );

    test(
      'manual approval opens short session for remembered low-risk approvals',
      () async {
        await vaultController.setApprovalSessionDurationMinutes(5);
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'first'),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final first = requestController.state.requests.single;
        await permissionController.approveSigningRequest(
          first.id,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(permissionController.state.approvalSessionExpiresAt, isNotNull);
        expect(permissionStore.grants, hasLength(1));
        gateway.completedExtras = null;
        gateway.completedToken = null;

        await permissionController.handleRawIntent({
          ...signEventRaw(id: 'second'),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(gateway.completedToken, 'token-second');
        expect(gateway.completedExtras?['event'], contains('"sig"'));
        expect(permissionController.state.pendingSigningRequestId, isNull);
        expect(permissionStore.grants.single.lastUsedAt, isNotNull);
      },
    );

    test('browser-style requests cannot be remembered', () async {
      final permissionController = Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: FakeNip55PermissionStore(),
      );

      await permissionController.handleRawIntent({
        ...signEventRaw(id: 'browser'),
        'callingPackage': 'com.android.chrome',
        'callerCertificateSha256': 'AA:BB',
        'callbackUrl': 'https://example.com/callback',
        'returnType': 'event',
      });
      final request = requestController.state.requests.single;

      expect(
        permissionController.canRememberPendingSigningRequest(request.id),
        isFalse,
      );
    });

    test('callback-less browser requests cannot be remembered', () async {
      final permissionController = Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: FakeNip55PermissionStore(),
      );

      await permissionController.handleRawIntent({
        ...signEventRaw(id: 'browser-no-callback'),
        'callingPackage': 'com.android.chrome',
        'callerCertificateSha256': 'AA:BB',
        'isBrowserFlow': true,
      });
      final request = requestController.state.requests.single;

      expect(
        permissionController.canRememberPendingSigningRequest(request.id),
        isFalse,
      );
    });

    test('signing failure rejects external caller safely', () async {
      await controller.handleRawIntent({
        'requestToken': 'token-fail',
        'type': 'sign_event',
        'content': '{"kind":1,"content":42,"tags":[]}',
        'id': 'fail',
        'currentUser': vaultController.state.activeIdentity!.publicKey,
        'sourceHint': 'com.example.app',
      });
      final request = requestController.state.requests.single;

      await requestController.approveRequest(request.id);
      await controller.completeApprovedSigningRequest(request.id);

      expect(gateway.completedExtras, isNull);
      expect(gateway.rejectedToken, 'token-fail');
      expect(gateway.rejectedError, 'Signing failed. No event was returned.');
      expect(controller.state.pendingSigningRequestId, isNull);
      expect(requestController.state.requests.single.status.name, 'rejected');
    });

    test(
      'settled NIP-55 signing failure reveals next pending request',
      () async {
        await controller.handleRawIntent({
          'requestToken': 'token-fail',
          'type': 'sign_event',
          'content': '{"kind":1,"content":42,"tags":[]}',
          'id': 'fail',
          'currentUser': vaultController.state.activeIdentity!.publicKey,
        });
        final failedRequest = requestController.state.requests.single;

        await requestController.approveRequest(failedRequest.id);
        await controller.completeApprovedSigningRequest(failedRequest.id);
        await requestController.acceptRequest(
          failedRequest.copyWith(
            id: 'next-pending',
            status: SigningRequestStatus.pending,
          ),
        );

        final container = ProviderContainer(
          overrides: [
            requestControllerProvider.overrideWith((ref) => requestController),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(activeRequestProvider)?.id, 'next-pending');
      },
    );

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

    test('multiple sequential requests preserve id/result pairing', () async {
      await controller.handleRawIntent(signEventRaw(id: 'first'));
      final firstRequestId = controller.state.pendingSigningRequestId!;
      await requestController.approveRequest(firstRequestId);
      await controller.completeApprovedSigningRequest(firstRequestId);

      expect(gateway.completedToken, 'token-first');
      expect(gateway.completedExtras?['id'], 'first');
      final firstResult = gateway.completedExtras?['result'];
      expect(firstResult, isA<String>());

      await controller.handleRawIntent(signEventRaw(id: 'second'));
      final secondRequestId = controller.state.pendingSigningRequestId!;
      await requestController.approveRequest(secondRequestId);
      await controller.completeApprovedSigningRequest(secondRequestId);

      expect(gateway.completedToken, 'token-second');
      expect(gateway.completedExtras?['id'], 'second');
      expect(gateway.completedExtras?['result'], isA<String>());
      expect(gateway.completedExtras?['result'], isNot(firstResult));
    });

    test('concurrent intent is rejected as busy', () async {
      await controller.handleRawIntent(signEventRaw());
      await controller.handleRawIntent(signEventRaw(id: 'second'));

      expect(gateway.rejectedToken, 'token-second');
      expect(gateway.rejectedError, contains('already reviewing'));
      expect(requestController.state.requests, hasLength(1));
    });

    test(
      'concurrent busy rejection does not poison first request result',
      () async {
        final isolatedGateway = FakeNip55Gateway();
        final isolatedController = Nip55Controller(
          gateway: isolatedGateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
        );

        await isolatedController.handleRawIntent(signEventRaw(id: 'first'));
        final firstRequestId =
            isolatedController.state.pendingSigningRequestId!;

        await isolatedController.handleRawIntent(signEventRaw(id: 'second'));
        expect(isolatedGateway.rejectedToken, 'token-second');

        await requestController.approveRequest(firstRequestId);
        await isolatedController.completeApprovedSigningRequest(firstRequestId);

        expect(isolatedGateway.completedToken, 'token-first');
        expect(isolatedGateway.completedExtras?['id'], 'first');
        expect(isolatedGateway.completedExtras?['event'], contains('"sig"'));
      },
    );

    test(
      'in-flight intent is rejected as busy before pending UI exists',
      () async {
        final slowStore = SlowNip55PermissionStore();
        final localGateway = FakeNip55Gateway();
        final localVaultService = VaultServiceImpl(FakeVaultStore());
        final localVaultController = VaultController(localVaultService);
        await localVaultController.createVault('1234');
        await localVaultController.importIdentity(
          '0000000000000000000000000000000000000000000000000000000000000001',
        );
        final localRequestController = RequestController(
          localVaultController,
          RealSignerService(localVaultService),
        );

        final slowController = Nip55Controller(
          gateway: localGateway,
          vaultController: localVaultController,
          vaultService: localVaultService,
          requestController: localRequestController,
          permissionStore: slowStore,
        );

        final firstRaw = {
          'requestToken': 'token-first',
          'type': 'sign_event',
          'content': '{"kind":1,"content":"first","tags":[]}',
          'id': 'first',
          'currentUser': localVaultController.state.activeIdentity!.publicKey,
        };
        final secondRaw = {
          'requestToken': 'token-second',
          'type': 'sign_event',
          'content': '{"kind":1,"content":"second","tags":[]}',
          'id': 'second',
          'currentUser': localVaultController.state.activeIdentity!.publicKey,
        };

        final first = slowController.handleRawIntent(firstRaw);

        // Since handleRawIntent is async but starts synchronously,
        // we check state immediately.
        expect(slowController.state.isLoading, isTrue);

        await slowController.handleRawIntent(secondRaw);

        expect(localGateway.rejectedToken, 'token-second');
        expect(localGateway.rejectedError, contains('already reviewing'));
        expect(localRequestController.state.requests, isEmpty);

        slowStore.allowListGrants.complete();
        await first;
        expect(localRequestController.state.requests, hasLength(1));
        expect(
          localRequestController.state.requests.single.id,
          isNot('second'),
        );
      },
    );

    test('get_public_key approval returns pubkey', () async {
      await controller.handleRawIntent({
        'requestToken': 'pk-token',
        'type': 'get_public_key',
        'permissions': '["sign_event"]',
        'sourceHint': 'com.example.app',
      });

      await controller.approvePublicKeyRequest();

      expect(
        gateway.completedExtras?['result'],
        vaultController.state.activeIdentity!.publicKey,
      );
      expect(gateway.completedToken, 'pk-token');
      expect(gateway.completedExtras?['package'], 'io.diogel.symudol');
    });

    test('get_public_key approve and remember persists grant', () async {
      final permissionStore = FakeNip55PermissionStore();
      final permissionController = Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: permissionStore,
      );

      await permissionController.handleRawIntent({
        'requestToken': 'pk-token',
        'type': 'get_public_key',
        'callingPackage': 'com.example.app',
      });

      await permissionController.approvePublicKeyRequest(
        timeframe: Nip55ApprovalTimeframe.always,
      );

      expect(permissionStore.grants, hasLength(1));
      expect(permissionStore.grants.single.scope, isA<GetPublicKeyScope>());
      expect(
        permissionStore.grants.single.decision,
        Nip55PermissionDecision.allow,
      );
      expect(permissionStore.grants.single.expiresAt, isNull);
      expect(gateway.completedToken, 'pk-token');
    });

    group('a broad sign_event is never remembered (#5)', () {
      Nip55Controller withStore(FakeNip55PermissionStore store) =>
          Nip55Controller(
            gateway: gateway,
            vaultController: vaultController,
            vaultService: vaultService,
            requestController: requestController,
            permissionStore: store,
          );

      for (final permissions in [
        'sign_event,sign_event:1',
        '[{"type":"sign_event"},{"type":"sign_event","kind":1}]',
      ]) {
        test(
          'connect-time permissions keep specific kinds only: $permissions',
          () async {
            final store = FakeNip55PermissionStore();
            final controller = withStore(store);
            await controller.handleRawIntent({
              'requestToken': 'pk-token',
              'type': 'get_public_key',
              'callingPackage': 'com.example.app',
              'permissions': permissions,
            });

            await controller.approvePublicKeyRequest(
              timeframe: Nip55ApprovalTimeframe.always,
            );

            final signScopes = store.grants
                .map((grant) => grant.scope)
                .whereType<SignEventScope>()
                .toList();
            expect(signScopes.map((scope) => scope.kind), [1]);
            expect(store.grants.where((grant) => grant.scope.isBroad), isEmpty);
            expect(gateway.completedToken, 'pk-token');
          },
        );
      }

      test(
        'a signing request with no kind is rejected before review (#10)',
        () async {
          final store = FakeNip55PermissionStore();
          final controller = withStore(store);
          await controller.handleRawIntent({
            ...signEventRaw(),
            'content': '{"content":"hello","tags":[]}',
            'callingPackage': 'com.example.app',
          });

          expect(requestController.state.requests, isEmpty);
          expect(controller.state.pendingSigningRequestId, isNull);
          expect(gateway.rejectedToken, 'token-external-id');
          expect(gateway.rejectedError, 'NIP-55 event kind is invalid');
          expect(store.grants, isEmpty);
        },
      );

      test('no timeframe is offered for a pending event with no kind (#10)', () {
        final controller = withStore(FakeNip55PermissionStore());
        Nip55IncomingRequest pending(String content) =>
            const Nip55IntentParser().parse({
              ...signEventRaw(),
              'content': content,
              'callingPackage': 'com.example.app',
            });

        controller.state = controller.state.copyWith(
          pendingIncoming: pending('{"kind":1,"content":"hello","tags":[]}'),
          pendingSigningRequestId: 'request-1',
        );
        expect(
          controller.canSelectTimeframeForPendingSigningRequest('request-1'),
          isTrue,
        );

        for (final content in [
          '{"content":"hello","tags":[]}',
          '{"kind":"1","content":"hello","tags":[]}',
          '{"kind":1.5,"content":"hello","tags":[]}',
        ]) {
          controller.state = controller.state.copyWith(
            pendingIncoming: pending(content),
            pendingSigningRequestId: 'request-1',
          );
          expect(
            controller.canSelectTimeframeForPendingSigningRequest('request-1'),
            isFalse,
            reason: content,
          );
        }
      });

      test('a provider query for another account is not answered (#10)', () async {
        final store = FakeNip55PermissionStore();
        final controller = withStore(store);
        final identity = vaultController.state.activeIdentity!;
        await store.saveGrant(
          Nip55PermissionGrant(
            id: 'allow-kind-1',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        );
        final query = {
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        };

        final other = await controller.handleProviderQuery({
          ...query,
          'currentUser':
              'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5',
        });

        expect(other, isNull);
        final same = await controller.handleProviderQuery(query);
        expect(same?['result'], isNotNull, reason: 'the active account is answered');
      });

      test('a broad rejection is still remembered', () async {
        final grant = Nip55PermissionGrant(
          id: 'g',
          identityPubkey: 'pk',
          packageName: 'com.example.app',
          scope: const SignEventScope(),
          decision: Nip55PermissionDecision.reject,
          createdAt: DateTime(2026),
        );
        expect(grant.isRememberable, isTrue);
        expect(
          Nip55PermissionGrant(
            id: 'g',
            identityPubkey: 'pk',
            packageName: 'com.example.app',
            scope: const SignEventScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime(2026),
          ).isRememberable,
          isFalse,
        );
      });
    });

    group('a rejection remembered for 8 hours expires (#5)', () {
      test('public key', () async {
        final store = FakeNip55PermissionStore();
        final controller = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: store,
        );
        await controller.handleRawIntent({
          'requestToken': 'pk-token',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
        });
        final before = DateTime.now();

        await controller.rejectPublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.eightHours,
        );

        final expiresAt = store.grants.single.expiresAt;
        expect(store.grants.single.decision, Nip55PermissionDecision.reject);
        expect(expiresAt, isNotNull);
        expect(
          expiresAt!.isAfter(before.add(const Duration(hours: 7))),
          isTrue,
        );
        expect(
          expiresAt.isBefore(before.add(const Duration(hours: 9))),
          isTrue,
        );
      });

      test('signing', () async {
        final store = FakeNip55PermissionStore();
        final controller = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: store,
        );
        await controller.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
        });
        final request = requestController.state.requests.single;
        await requestController.rejectRequest(request.id);

        await controller.rejectSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.eightHours,
        );

        expect(store.grants.single.expiresAt, isNotNull);
      });

      test('"Always" still never expires', () async {
        final store = FakeNip55PermissionStore();
        final controller = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: store,
        );
        await controller.handleRawIntent({
          'requestToken': 'pk-token',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
        });

        await controller.rejectPublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(store.grants.single.expiresAt, isNull);
      });
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
        vaultService: emptyVaultService,
        requestController: emptyRequestController,
      );

      await emptyController.handleRawIntent({
        'requestToken': 'pk-token',
        'type': 'get_public_key',
      });

      expect(emptyGateway.rejectedError, contains('Select an identity'));
      expect(emptyController.state.pendingPublicKeyRequest, isNull);
    });

    test('get_public_key current_user mismatch rejects immediately', () async {
      await controller.handleRawIntent({
        'requestToken': 'pk-token-mismatch',
        'type': 'get_public_key',
        'currentUser': 'b' * 64,
      });

      expect(gateway.rejectedToken, 'pk-token-mismatch');
      expect(gateway.rejectedError, contains('does not match active identity'));
      expect(controller.state.pendingPublicKeyRequest, isNull);
    });

    test('nip44_encrypt can be manually approved', () async {
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );

      await controller.handleRawIntent({
        'requestToken': 'crypto-token',
        'type': 'nip44_encrypt',
        'content': 'hello encrypted world',
        'pubkey': bob.public,
        'currentUser': vaultController.state.activeIdentity!.publicKey,
      });

      expect(
        controller.state.pendingCryptoRequest?.method.wireName,
        'nip44_encrypt',
      );

      await controller.approveCryptoRequest();

      expect(gateway.completedToken, 'crypto-token');
      final ciphertext = gateway.completedExtras?['result'] as String?;
      expect(ciphertext, isNotNull);
      expect(
        const DartNostrCryptoService().nip44Decrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: vaultController.state.activeIdentity!.publicKey,
          ciphertext: ciphertext!,
        ),
        'hello encrypted world',
      );
      expect(controller.state.pendingCryptoRequest, isNull);
    });

    test('sign_message can be manually approved', () async {
      final identity = vaultController.state.activeIdentity!;
      await controller.handleRawIntent({
        'requestToken': 'sign-message-token',
        'type': 'sign_message',
        'content': 'hello message',
        'currentUser': identity.publicKey,
      });

      expect(
        controller.state.pendingCryptoRequest?.method,
        Nip55Method.signMessage,
      );

      await controller.approveCryptoRequest();

      final signature = gateway.completedExtras?['result'] as String?;
      final digest = crypto_hash.sha256
          .convert(utf8.encode('hello message'))
          .toString();
      expect(gateway.completedToken, 'sign-message-token');
      expect(signature, isNotNull);
      expect(
        NostrKeyPairs.verify(identity.publicKey, digest, signature!),
        isTrue,
      );
    });

    test(
      'sign_message of an event serialisation is rejected without review (#8)',
      () async {
        final identity = vaultController.state.activeIdentity!;
        await controller.handleRawIntent({
          'requestToken': 'sign-message-event-token',
          'type': 'sign_message',
          'content': '[0,"${identity.publicKey}",1700000000,1,[],"hi"]',
          'currentUser': identity.publicKey,
        });

        expect(controller.state.pendingCryptoRequest, isNull);
        expect(gateway.completedToken, isNull);
        expect(gateway.rejectedToken, 'sign-message-event-token');
        expect(gateway.rejectedError, refusedEventSerialisationMessage);
      },
    );

    group('review timeout (#9)', () {
      Nip55Controller timedController() => Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        reviewTimeout: const Duration(milliseconds: 50),
      );

      Future<void> openReview(Nip55Controller controller) =>
          controller.handleRawIntent({
            'requestToken': 'review-token',
            'type': 'sign_message',
            'content': 'hello message',
            'currentUser': vaultController.state.activeIdentity!.publicKey,
          });

      test('an abandoned review is rejected when it times out', () async {
        final controller = timedController();
        await openReview(controller);
        expect(controller.state.pendingCryptoRequest, isNotNull);
        expect(controller.pendingReviewExpiresAt, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(gateway.rejectedToken, 'review-token');
        expect(
          gateway.rejectedError,
          'NIP-55 request timed out waiting for review',
        );
        expect(controller.state.hasPendingExternalRequest, isFalse);
        expect(controller.pendingReviewExpiresAt, isNull);
      });

      test('a settled review is not timed out', () async {
        final controller = timedController();
        await openReview(controller);

        await controller.approveCryptoRequest();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(gateway.completedToken, 'review-token');
        expect(gateway.rejectedToken, isNull);
        expect(controller.pendingReviewExpiresAt, isNull);
      });

      test('a signing review that times out is dismissed', () async {
        final controller = timedController();
        await controller.handleRawIntent({
          'requestToken': 'sign-review-token',
          'type': 'sign_event',
          'content': '{"kind":1,"content":"hello","tags":[]}',
          'currentUser': vaultController.state.activeIdentity!.publicKey,
        });
        final requestId = controller.state.pendingSigningRequestId;
        expect(requestId, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(gateway.rejectedToken, 'sign-review-token');
        expect(
          requestController.state.requests
              .singleWhere((r) => r.id == requestId)
              .status,
          SigningRequestStatus.rejected,
        );
      });
    });

    test('peer-scoped decrypt requests can be remembered', () async {
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );
      final ciphertext = const DartNostrCryptoService().nip44Encrypt(
        privateKeyHex: bob.private,
        peerPubkeyHex: vaultController.state.activeIdentity!.publicKey,
        plaintext: 'secret',
      );

      final permissionStore = FakeNip55PermissionStore();
      final permissionController = Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: permissionStore,
      );

      await permissionController.handleRawIntent({
        'requestToken': 'decrypt-token',
        'type': 'nip44_decrypt',
        'content': ciphertext,
        'pubkey': bob.public,
        'currentUser': vaultController.state.activeIdentity!.publicKey,
        'callingPackage': 'com.example.app',
        'callerCertificateSha256': 'AA:BB',
      });

      expect(permissionController.canRememberPendingCryptoRequest(), isTrue);

      await permissionController.approveCryptoRequest(
        timeframe: Nip55ApprovalTimeframe.always,
      );

      expect(gateway.completedExtras?['result'], 'secret');
      expect(permissionStore.grants.single.scope, isA<Nip44DecryptScope>());
    });

    test(
      'remembered peer-scoped decrypt grant works through provider',
      () async {
        final bob = NostrKeyPairs(
          private:
              '0000000000000000000000000000000000000000000000000000000000000002',
        );
        final ciphertext = const DartNostrCryptoService().nip04Encrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: vaultController.state.activeIdentity!.publicKey,
          plaintext: 'secret nip04',
        );
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'grant-nip04-decrypt',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: Nip04DecryptScope(bob.public),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        final result = await permissionController.handleProviderQuery({
          'requestToken': 'provider-decrypt-token',
          'type': 'nip04_decrypt',
          'content': ciphertext,
          'pubkey': bob.public,
          'currentUser': vaultController.state.activeIdentity!.publicKey,
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
          'transport': 'content_provider',
        });

        expect(result?['result'], 'secret nip04');
      },
    );

    test('decrypt_zap_event requests can be remembered', () async {
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );
      final identity = vaultController.state.activeIdentity!;
      // NIP-57 zap receipt: legacy format has NIP-44 ciphertext in the
      // event content field, signed by the zapper's pubkey.
      final ciphertext = const DartNostrCryptoService().nip44Encrypt(
        privateKeyHex: bob.private,
        peerPubkeyHex: identity.publicKey,
        plaintext: 'zap-content',
      );
      final zapEventJson = jsonEncode({
        'kind': 9734,
        'pubkey': bob.public,
        'content': ciphertext,
        'tags': [
          ['p', identity.publicKey],
        ],
        'created_at': 1700000000,
      });

      final permissionStore = FakeNip55PermissionStore();
      final permissionController = Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: permissionStore,
      );

      await permissionController.handleRawIntent({
        'requestToken': 'zap-token',
        'type': 'decrypt_zap_event',
        'content': zapEventJson,
        'currentUser': identity.publicKey,
        'callingPackage': 'com.example.app',
        'callerCertificateSha256': 'AA:BB',
      });

      expect(permissionController.canRememberPendingCryptoRequest(), isTrue);

      await permissionController.approveCryptoRequest(
        timeframe: Nip55ApprovalTimeframe.always,
      );

      expect(gateway.completedExtras?['result'], isNotNull);
      expect(
        permissionStore.grants.single.scope,
        isA<DecryptZapEventScope>(),
      );
    });

    test(
      'remembered decrypt_zap_event grant works through provider',
      () async {
        final bob = NostrKeyPairs(
          private:
              '0000000000000000000000000000000000000000000000000000000000000002',
        );
        final identity = vaultController.state.activeIdentity!;
        final ciphertext = const DartNostrCryptoService().nip44Encrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: identity.publicKey,
          plaintext: 'zap-from-provider',
        );
        final zapEventJson = jsonEncode({
          'kind': 9734,
          'pubkey': bob.public,
          'content': ciphertext,
          'tags': [
            ['p', identity.publicKey],
          ],
          'created_at': 1700000000,
        });
        final permissionStore = FakeNip55PermissionStore();
        // Pre-existing decrypt_zap_event grant.
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'grant-zap-decrypt',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const DecryptZapEventScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        final result = await permissionController.handleProviderQuery({
          'requestToken': 'provider-zap-token',
          'type': 'decrypt_zap_event',
          'content': zapEventJson,
          'currentUser': identity.publicKey,
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
          'transport': 'content_provider',
        });

        expect(result?['result'], isNotNull);
      },
    );

    test(
      'remembered nip04_decrypt grant satisfies decrypt_zap_event through provider',
      () async {
        final bob = NostrKeyPairs(
          private:
              '0000000000000000000000000000000000000000000000000000000000000002',
        );
        final identity = vaultController.state.activeIdentity!;
        final ciphertext = const DartNostrCryptoService().nip44Encrypt(
          privateKeyHex: bob.private,
          peerPubkeyHex: identity.publicKey,
          plaintext: 'cross-scope-zap',
        );
        final zapEventJson = jsonEncode({
          'kind': 9734,
          'pubkey': bob.public,
          'content': ciphertext,
          'tags': [
            ['p', identity.publicKey],
          ],
          'created_at': 1700000000,
        });
        final permissionStore = FakeNip55PermissionStore();
        // Pre-existing nip04_decrypt grant (no specific peer — wildcard).
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'grant-nip04-decrypt-wildcard',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const Nip04DecryptScope(null),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        final result = await permissionController.handleProviderQuery({
          'requestToken': 'provider-cross-scope-zap',
          'type': 'decrypt_zap_event',
          'content': zapEventJson,
          'currentUser': identity.publicKey,
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
          'transport': 'content_provider',
        });

        expect(result?['result'], isNotNull);
      },
    );

    test(
      'crypto approval failure rejects caller instead of escaping',
      () async {
        await controller.handleRawIntent({
          'requestToken': 'bad-nip04-token',
          'type': 'nip04_decrypt',
          'content': 'ciphertext-without-iv',
          'pubkey': 'b' * 64,
          'currentUser': vaultController.state.activeIdentity!.publicKey,
        });

        await controller.approveCryptoRequest();

        expect(gateway.rejectedToken, 'bad-nip04-token');
        expect(gateway.rejectedError, 'Unable to complete NIP-55 operation');
        expect(controller.state.pendingCryptoRequest, isNull);
      },
    );

    test(
      'provider sign_event defers to foreground without remembered approval session',
      () async {
        final result = await controller.handleProviderQuery(signEventRaw());

        expect(result, isNull);
        expect(requestController.state.requests, isEmpty);
      },
    );

    test(
      'provider get_public_key current_user mismatch defers to foreground',
      () async {
        final result = await controller.handleProviderQuery({
          'requestToken': 'provider-pk-mismatch',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
          'currentUser': 'b' * 64,
          'transport': 'content_provider',
        });

        expect(result, isNull);
      },
    );

    test(
      'provider sign_event returns signed event during approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final providerController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );
        final identity = vaultController.state.activeIdentity!;
        await permissionStore.saveGrant(
          Nip55PermissionGrant(
            id: 'allow-sign-1',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        );
        providerController.state = providerController.state.copyWith(
          approvalSessionExpiresAt: DateTime.now().add(
            const Duration(minutes: 1),
          ),
        );

        final result = await providerController.handleProviderQuery({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(result, isNotNull);
        expect(result?['result'], isA<String>());
        expect(result?['event'], isA<String>());
        expect(requestController.state.requests, isEmpty);
      },
    );

    test(
      'provider nip44_encrypt returns result during approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final providerController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );
        final identity = vaultController.state.activeIdentity!;
        final bob = NostrKeyPairs(
          private:
              '0000000000000000000000000000000000000000000000000000000000000002',
        );
        await permissionStore.saveGrant(
          Nip55PermissionGrant(
            id: 'allow-nip44-1',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const Nip44EncryptScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        );
        providerController.state = providerController.state.copyWith(
          approvalSessionExpiresAt: DateTime.now().add(
            const Duration(minutes: 1),
          ),
        );

        final result = await providerController.handleProviderQuery({
          'requestToken': 'provider-token',
          'type': 'nip44_encrypt',
          'content': 'hello provider',
          'pubkey': bob.public,
          'currentUser': identity.publicKey,
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(result?['result'], isA<String>());
        expect(
          const DartNostrCryptoService().nip44Decrypt(
            privateKeyHex: bob.private,
            peerPubkeyHex: identity.publicKey,
            ciphertext: result!['result']! as String,
          ),
          'hello provider',
        );
      },
    );

    test(
      'provider sign_message returns signature during approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final providerController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );
        final identity = vaultController.state.activeIdentity!;
        await permissionStore.saveGrant(
          Nip55PermissionGrant(
            id: 'allow-sign-message-1',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignMessageScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        );
        providerController.state = providerController.state.copyWith(
          approvalSessionExpiresAt: DateTime.now().add(
            const Duration(minutes: 1),
          ),
        );

        final result = await providerController.handleProviderQuery({
          'requestToken': 'provider-sign-message-token',
          'type': 'sign_message',
          'content': 'provider message',
          'currentUser': identity.publicKey,
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        final digest = crypto_hash.sha256
            .convert(utf8.encode('provider message'))
            .toString();
        final signature = result?['result'] as String?;
        expect(signature, isNotNull);
        expect(
          NostrKeyPairs.verify(identity.publicKey, digest, signature!),
          isTrue,
        );
      },
    );

    test(
      'provider sign_message of an event serialisation is rejected (#8)',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final providerController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );
        final identity = vaultController.state.activeIdentity!;
        await permissionStore.saveGrant(
          Nip55PermissionGrant(
            id: 'allow-sign-message-1',
            identityPubkey: identity.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignMessageScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        );
        providerController.state = providerController.state.copyWith(
          approvalSessionExpiresAt: DateTime.now().add(
            const Duration(minutes: 1),
          ),
        );

        final result = await providerController.handleProviderQuery({
          'requestToken': 'provider-sign-message-event-token',
          'type': 'sign_message',
          'content': '[0,"${identity.publicKey}",1700000000,1,[],"hi"]',
          'currentUser': identity.publicKey,
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        expect(result, {'rejected': refusedEventSerialisationMessage});
      },
    );

    test('locked vault keeps request pending until unlock', () async {
      final activePubkey = vaultController.state.activeIdentity!.publicKey;
      await vaultController.lock();

      await controller.handleRawIntent({
        'requestToken': 'token-locked',
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'id': 'locked',
        'currentUser': activePubkey,
        'sourceHint': 'com.example.app',
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

    // -------------------------------------------------------------------------
    // Timeframe-based approval tests
    // -------------------------------------------------------------------------

    test(
      'justOnce leaves no grant in the store',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final request = requestController.state.requests.single;

        await permissionController.approveSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.justOnce,
        );

        expect(permissionStore.grants, isEmpty);
        expect(gateway.completedExtras?['event'], contains('"sig"'));
      },
    );

    test(
      'eightHours stores grant with expiresAt approximately now + 8h',
      () async {
        final now = DateTime.utc(2026, 6, 1, 12);
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
          now: () => now,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final request = requestController.state.requests.single;

        await permissionController.approveSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.eightHours,
        );

        expect(permissionStore.grants, hasLength(1));
        final grant = permissionStore.grants.single;
        expect(grant.expiresAt, isNotNull);
        expect(
          grant.expiresAt!.difference(now).inMinutes,
          closeTo(480, 1),
        );
        expect(gateway.completedExtras?['event'], contains('"sig"'));
      },
    );

    test(
      'always stores grant with null expiresAt',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });
        final request = requestController.state.requests.single;

        await permissionController.approveSigningRequest(
          request.id,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(permissionStore.grants, hasLength(1));
        expect(permissionStore.grants.single.expiresAt, isNull);
      },
    );

    test(
      'non-expired saved grant auto-approves without an approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'saved-grant',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const GetPublicKeyScope(),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 8)),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'pk-auto',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        // No approval session set — grant alone should suffice.
        expect(permissionController.state.approvalSessionExpiresAt, isNull);
        expect(gateway.completedToken, 'pk-auto');
        expect(permissionController.state.pendingPublicKeyRequest, isNull);
      },
    );

    test(
      'expired 8-hour grant does not auto-approve',
      () async {
        final past = DateTime.utc(2026, 6, 1, 3);
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'expired-grant',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.utc(2026, 6, 1),
            // Saved 9 hours ago, already expired.
            expiresAt: past,
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        // Expired grant — must show review UI.
        expect(gateway.completedExtras, isNull);
        expect(permissionController.state.pendingSigningRequestId, isNotNull);
      },
    );

    test(
      'broad sign_event (null kind) grant still requires approval session',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        permissionStore.grants.add(
          Nip55PermissionGrant(
            id: 'broad-grant',
            identityPubkey: vaultController.state.activeIdentity!.publicKey,
            packageName: 'com.example.app',
            certificateSha256: 'AA:BB',
            scope: const SignEventScope(null),
            decision: Nip55PermissionDecision.allow,
            createdAt: DateTime.now(),
          ),
        );
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          ...signEventRaw(),
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
        });

        // Broad wildcard scope: no active session → must show review.
        expect(gateway.completedExtras, isNull);
        expect(permissionController.state.pendingSigningRequestId, isNotNull);
      },
    );

    // ── Connect-time permission persistence ────────────────────────────

    test(
      'remembered get_public_key approval saves requested sign_event and crypto grants',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'token-connect',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
          'permissions':
              '[{"type":"sign_event","kind":1},{"type":"sign_event","kind":4},'
              '{"type":"sign_event","kind":22242},'
              '{"type":"nip04_encrypt"},{"type":"nip04_decrypt"},'
              '{"type":"nip44_encrypt"},{"type":"nip44_decrypt"},'
              '{"type":"decrypt_zap_event"}]',
        });

        await permissionController.approvePublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.eightHours,
        );

        // One get_public_key grant + 8 connect-time permission grants
        expect(permissionStore.grants.length, greaterThanOrEqualTo(9));

        final scopes = permissionStore.grants.map((g) => g.scope).toList();
        expect(scopes.whereType<GetPublicKeyScope>(), hasLength(1));
        expect(scopes.whereType<SignEventScope>().map((s) => s.kind),
            containsAll(<int>[1, 4, 22242]));
        expect(scopes.whereType<Nip04EncryptScope>(), hasLength(1));
        expect(scopes.whereType<Nip04DecryptScope>(), hasLength(1));
        expect(scopes.whereType<Nip44EncryptScope>(), hasLength(1));
        expect(scopes.whereType<Nip44DecryptScope>(), hasLength(1));
        expect(scopes.whereType<DecryptZapEventScope>(), hasLength(1));

        // All grants must have the same expiry window (eightHours)
        final nonExpiring = permissionStore.grants.where((g) => g.expiresAt == null);
        expect(nonExpiring, isEmpty);
      },
    );

    test(
      'remembered get_public_key with justOnce does not save connect-time grants',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'token-connect-once',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'permissions': '[{"type":"sign_event","kind":1}]',
        });

        await permissionController.approvePublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.justOnce,
        );

        expect(permissionStore.grants, isEmpty);
      },
    );

    test(
      'connect-time grants have same expiry and package as get_public_key grant',
      () async {
        final fixedNow = DateTime.utc(2026, 7, 1, 12);
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
          now: () => fixedNow,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'token-expiry',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'callerCertificateSha256': 'AA:BB',
          'permissions': '[{"type":"sign_event","kind":1},{"type":"nip44_decrypt"}]',
        });

        await permissionController.approvePublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.eightHours,
        );

        final expectedExpiry = fixedNow.add(const Duration(hours: 8));
        for (final grant in permissionStore.grants) {
          expect(grant.packageName, 'com.example.app');
          expect(grant.certificateSha256, 'AA:BB');
          expect(grant.expiresAt, expectedExpiry);
        }
      },
    );

    test(
      'connect-time permissions with ping are silently ignored',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'token-ping',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'permissions': 'ping get_public_key',
        });

        await permissionController.approvePublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.always,
        );

        // Only get_public_key is saved; ping is stateless and ignored
        expect(permissionStore.grants, hasLength(1));
        expect(permissionStore.grants.single.scope, isA<GetPublicKeyScope>());
      },
    );

    test(
      'connect-time unsupported permissions produce no grant and no crash',
      () async {
        final permissionStore = FakeNip55PermissionStore();
        final permissionController = Nip55Controller(
          gateway: gateway,
          vaultController: vaultController,
          vaultService: vaultService,
          requestController: requestController,
          permissionStore: permissionStore,
        );

        await permissionController.handleRawIntent({
          'requestToken': 'token-unknown',
          'type': 'get_public_key',
          'callingPackage': 'com.example.app',
          'permissions': 'unknown_token get_public_key',
        });

        await permissionController.approvePublicKeyRequest(
          timeframe: Nip55ApprovalTimeframe.always,
        );

        // unknown_token is not saved; get_public_key is
        final scopes = permissionStore.grants.map((g) => g.scope).toList();
        expect(scopes.whereType<GetPublicKeyScope>(), hasLength(1));
        expect(scopes.whereType<UnsupportedScope>(), isEmpty);
      },
    );

    test('locked pending request times out', () async {
      final activePubkey = vaultController.state.activeIdentity!.publicKey;
      await vaultController.lock();
      final timeoutGateway = FakeNip55Gateway();
      final timeoutController = Nip55Controller(
        gateway: timeoutGateway,
        vaultController: vaultController,
        vaultService: vaultService,
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
