import 'dart:async';

import 'package:android_diogel/features/nip55/application/nip55_controller.dart';
import 'package:android_diogel/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client_permission.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_decision.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_scope.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_store.dart';
import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/application/request_providers.dart';
import 'package:android_diogel/features/requests/data/real_signer_service.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
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
  String? rejectedError;
  String? rejectedToken;
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
      vaultService: vaultService,
      requestController: requestController,
    );
  });

  Map<String, Object?> signEventRaw({String? id = 'external-id'}) => {
    'requestToken': 'token-$id',
    'type': 'sign_event',
    'content': '{"kind":1,"content":"hello","tags":[]}',
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
          remember: true,
        );

        expect(permissionStore.grants, hasLength(1));
        final grant = permissionStore.grants.single;
        expect(grant.packageName, 'com.example.app');
        expect(grant.certificateSha256, 'AA:BB');
        expect(grant.decision, Nip55PermissionDecision.allow);
        expect(grant.scope, isA<SignEventScope>());
        expect((grant.scope as SignEventScope).kind, 1);
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
          remember: true,
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
          remember: true,
        );

        expect(permissionStore.grants, isEmpty);
        expect(gateway.rejectedToken, 'token-fail');
      },
    );

    test(
      'remembered allow grant still asks outside approval session',
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

        expect(gateway.completedExtras, isNull);
        expect(permissionController.state.pendingSigningRequestId, isNotNull);
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
          remember: true,
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

    test('concurrent intent is rejected as busy', () async {
      await controller.handleRawIntent(signEventRaw());
      await controller.handleRawIntent(signEventRaw(id: 'second'));

      expect(gateway.rejectedError, contains('already reviewing'));
      expect(requestController.state.requests, hasLength(1));
    });

    test('in-flight intent is rejected as busy before pending UI exists', () async {
      final slowStore = SlowNip55PermissionStore();
      final slowController = Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: slowStore,
      );

      final first = slowController.handleRawIntent(signEventRaw(id: 'first'));
      expect(slowController.state.isLoading, isTrue);

      await slowController.handleRawIntent(signEventRaw(id: 'second'));

      expect(gateway.rejectedToken, 'token-second');
      expect(gateway.rejectedError, contains('already reviewing'));
      expect(requestController.state.requests, isEmpty);

      slowStore.allowListGrants.complete();
      await first;
      expect(requestController.state.requests, hasLength(1));
      expect(requestController.state.requests.single.id, isNot('second'));
    });

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
      expect(gateway.completedExtras?['package'], 'io.threenine.androidiogel');
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

      await permissionController.approvePublicKeyRequest(remember: true);

      expect(permissionStore.grants, hasLength(1));
      expect(permissionStore.grants.single.scope, isA<GetPublicKeyScope>());
      expect(
        permissionStore.grants.single.decision,
        Nip55PermissionDecision.allow,
      );
      expect(gateway.completedToken, 'pk-token');
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

    test('sensitive decrypt requests cannot be remembered by default', () async {
      final bob = NostrKeyPairs(
        private:
            '0000000000000000000000000000000000000000000000000000000000000002',
      );
      final ciphertext = const DartNostrCryptoService().nip44Encrypt(
        privateKeyHex: bob.private,
        peerPubkeyHex: vaultController.state.activeIdentity!.publicKey,
        plaintext: 'secret',
      );

      await controller.handleRawIntent({
        'requestToken': 'decrypt-token',
        'type': 'nip44_decrypt',
        'content': ciphertext,
        'pubkey': bob.public,
        'currentUser': vaultController.state.activeIdentity!.publicKey,
        'packageName': 'com.example.app',
      });

      expect(controller.canRememberPendingCryptoRequest(), isFalse);

      await controller.approveCryptoRequest(remember: true);

      expect(gateway.completedExtras?['result'], 'secret');
    });

    test('provider sign_event returns null without remembered approval session', () async {
      final result = await controller.handleProviderQuery(signEventRaw());

      expect(result, isNull);
      expect(requestController.state.requests, isEmpty);
    });

    test('provider sign_event returns signed event during approval session', () async {
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
    });

    test('provider nip44_encrypt returns result during approval session', () async {
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
