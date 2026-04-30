import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/application/request_providers.dart';
import 'package:android_diogel/features/requests/data/fake_signer_service.dart';
import 'package:android_diogel/features/requests/domain/request_provenance.dart';
import 'package:android_diogel/features/requests/domain/request_trust_status.dart';
import 'package:android_diogel/features/requests/domain/signing_action_type.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:android_diogel/features/requests/presentation/requests_screen.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:flutter/material.dart';
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

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [
        vaultControllerProvider.overrideWith((ref) => vaultController),
        signerServiceProvider.overrideWithValue(signerService),
        requestControllerProvider.overrideWith((ref) => requestController),
      ],
      child: const MaterialApp(
        home: RequestsScreen(),
      ),
    );
  }

  group('RequestsScreen', () {
    testWidgets('shows empty state when no active requests', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No active requests'), findsOneWidget);
      expect(find.text('Load Demo Request (Dev)'), findsOneWidget);
    });

    testWidgets('shows pending request details', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test User');
      final activeIdentity = vaultController.state.activeIdentity!;

      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'Example App',
          sourceIdentifier: 'https://example.com',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {
          'content': 'Hello Nostr',
          'created_at': 1234567890,
          'tags': [],
        },
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);

      await tester.pumpWidget(createTestWidget());
      await tester.pump(); 

      expect(find.text('Signing Request'), findsOneWidget);
      expect(find.text('Example App'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);
      expect(find.text('Sign Kind 1 Event'), findsOneWidget);
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('Hello Nostr'), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
    });

    testWidgets('shows unknown provenance warning', (tester) async {
      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'Unknown App',
          trustStatus: RequestTrustStatus.unknown,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'test'},
        targetIdentityPublicKey: 'pubkey',
        targetIdentityLocalId: 'localId',
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Unknown Provenance'), findsOneWidget);
      expect(find.textContaining('Exercise caution'), findsOneWidget);
    });

    testWidgets('rejecting a request clears it from view', (tester) async {
      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'App',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'test'},
        targetIdentityPublicKey: 'pubkey',
        targetIdentityLocalId: 'localId',
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Signing Request'), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(find.text('No active requests'), findsOneWidget);
    });

    testWidgets('approving a request calls signer and clears pending on success', (tester) async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'User');
      final activeIdentity = vaultController.state.activeIdentity!;

      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'App',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'test'},
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Sign event (DEMO)'));
      await tester.pump(); 
      
      // The fake signer has a 100ms delay
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.text('No active requests'), findsOneWidget);
    });

    testWidgets('approving while locked fails safely', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      // Vault is NOT unlocked
      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'App',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'test'},
        targetIdentityPublicKey: 'pubkey',
        targetIdentityLocalId: 'localId',
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Sign event (DEMO)'));
      await tester.pump(); // This SHOULD show the error immediately
      await tester.pump();

      // Should show failure message
      expect(find.textContaining('Vault is locked'), findsOneWidget);
      // Still on the same screen (not cleared)
      expect(find.text('Signing Request'), findsOneWidget);
    });

    testWidgets('signing failure displays safe failure message', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'User');
      final activeIdentity = vaultController.state.activeIdentity!;

      // Setup failing signer
      final failingSigner = FakeSignerService(shouldFail: true);
      // Create a NEW controller with the failing signer
      final failingRequestController = RequestController(vaultController, failingSigner);

      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'App',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: {'content': 'test'},
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await failingRequestController.acceptRequest(request);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          vaultControllerProvider.overrideWith((ref) => vaultController),
          signerServiceProvider.overrideWithValue(failingSigner),
          requestControllerProvider.overrideWith((ref) => failingRequestController),
        ],
        child: const MaterialApp(
          home: RequestsScreen(),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Sign event (DEMO)'));
      
      // FakeSignerService has 100ms delay.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fake signer error'), findsOneWidget);
      expect(find.text('Signing Request'), findsOneWidget);
    });
  });
}
