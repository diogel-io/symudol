import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/domain/nip46_method.dart';
import 'package:symudol/features/nip46/domain/nip46_pending_method_request.dart';
import 'package:symudol/features/nip46/domain/nip46_request.dart';
import 'package:symudol/features/nip55/application/nip55_controller.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/requests/application/request_controller.dart';
import 'package:symudol/features/requests/application/request_providers.dart';
import 'package:symudol/features/requests/data/real_signer_service.dart';
import 'package:symudol/features/requests/domain/request_provenance.dart';
import 'package:symudol/features/requests/domain/request_trust_status.dart';
import 'package:symudol/features/requests/domain/signing_action_type.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';
import 'package:symudol/features/requests/presentation/approval_screen.dart';
import 'package:symudol/features/requests/presentation/widgets/remember_row.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_relay_profile_service.dart';
import '../../../fakes/fake_signer_service.dart';
import '../../../fakes/fake_vault_store.dart';
import '../../nip46/data/fake_nip46_relay_service.dart';

class FakeNip55Gateway implements Nip55Gateway {
  String? completedToken;
  String? rejectedToken;
  Map<String, Object?>? completedExtras;
  int completeCalls = 0;
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
  Future<Map<String, Object?>?> getInitialNip55Intent() async => null;

  @override
  Future<Map<String, Object?>?> consumeLatestNip55Intent() async => null;

  @override
  Future<void> completeNip55Intent({
    required String requestToken,
    required Map<String, Object?> extras,
  }) async {
    completeCalls += 1;
    completedToken = requestToken;
    completedExtras = extras;
  }

  @override
  Future<void> rejectNip55Intent({
    required String requestToken,
    String? error,
    bool rejected = false,
  }) async {
    rejectedToken = requestToken;
  }

  @override
  Future<Uint8List?> getAppIcon(String packageName) async => null;
}

/// Records which queued NIP-46 requests the screen answers.
class _RecordingNip46Controller extends Nip46Controller {
  _RecordingNip46Controller({
    required super.vaultService,
    required super.vaultController,
  }) : super(
         sessionStore: FakeNip46SessionStore(),
         relayService: FakeNip46RelayService(),
         crypto: const DartNip46Crypto(DartNostrCryptoService()),
       );

  final List<String> approved = [];
  final List<String> rejected = [];

  @override
  Future<void> approveMethodRequest(String key) async => approved.add(key);

  @override
  Future<void> rejectMethodRequest(String key) async => rejected.add(key);
}

void main() {
  late FakeVaultStore vaultStore;
  late VaultServiceImpl vaultService;
  late VaultController vaultController;
  late FakeSignerService signerService;
  late RequestController requestController;
  late FakeNip55Gateway nip55Gateway;
  late Nip55Controller nip55Controller;
  late FakeRelayProfileService profileService;

  setUp(() async {
    vaultStore = FakeVaultStore();
    vaultService = VaultServiceImpl(vaultStore);
    await vaultService.init();
    vaultController = VaultController(vaultService);
    signerService = FakeSignerService();
    profileService = FakeRelayProfileService();
    requestController = RequestController(vaultController, signerService);
    nip55Gateway = FakeNip55Gateway();
    nip55Controller = Nip55Controller(
      gateway: nip55Gateway,
      vaultController: vaultController,
      vaultService: vaultService,
      requestController: requestController,
    );
  });

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [
        vaultControllerProvider.overrideWith((ref) => vaultController),
        signerServiceProvider.overrideWithValue(signerService),
        requestControllerProvider.overrideWith((ref) => requestController),
        nip55GatewayProvider.overrideWithValue(nip55Gateway),
        nip55ControllerProvider.overrideWith((ref) => nip55Controller),
        relayProfileServiceProvider.overrideWithValue(profileService),
      ],
      child: const MaterialApp(home: ApprovalScreen()),
    );
  }

  group('ApprovalScreen', () {
    testWidgets('shows empty state when no active requests', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No active requests'), findsOneWidget);
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

      expect(find.text('Approval Request'), findsOneWidget);
      expect(find.text('Example App'), findsOneWidget);
      // Opening the screen with an active identity fetches no profile
      // (diogel-io/symudol#83).
      expect(profileService.requested, isEmpty);

      await tester.tap(find.text('Show details'));
      await tester.pump();

      expect(find.text('Hello Nostr'), findsAtLeastNWidgets(1));
      expect(find.text('1234567890'), findsOneWidget);
    });

    testWidgets('shows WP8 NIP-55 review summary without requiring raw JSON', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test User');
      final activeIdentity = vaultController.state.activeIdentity!;

      final request = SigningRequest(
        id: 'req-wp8',
        provenance: const RequestProvenance(
          sourceDisplayName: 'Example Nostr',
          sourceIdentifier: 'com.example.nostr',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 22242,
        eventPayload: const {
          'kind': 22242,
          'nip55Method': 'sign_event',
          'nip55PermissionScope': 'sign_event:22242',
          'content': 'auth challenge',
          'created_at': 1777618800,
          'tags': [
            ['relay', 'wss://relay.example'],
            ['challenge', 'abc'],
          ],
        },
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Client authentication'), findsOneWidget);
      expect(find.text('Risk note'), findsOneWidget);
      expect(find.textContaining('proves control of this key'), findsOneWidget);
      expect(find.text('Show details'), findsOneWidget);

      await tester.tap(find.text('Show details'));
      await tester.pump();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pump();

      expect(find.text('sign_event'), findsOneWidget);
      expect(
        find.text('Remember permission: sign kind 22242 only'),
        findsOneWidget,
      );
      expect(find.text('2 tag(s): relay:1, challenge:1'), findsOneWidget);
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

      expect(find.text('Approval Request'), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(find.text('No active requests'), findsOneWidget);
    });

    testWidgets(
      'approving a request calls signer and clears pending on success',
      (tester) async {
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

        await tester.tap(find.text('Sign event'));
        await tester.pump();

        // The fake signer has a 100ms delay
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();

        expect(find.text('No active requests'), findsOneWidget);
      },
    );

    testWidgets('a signing request shows no demo wording (#34)', (
      tester,
    ) async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'User');
      final activeIdentity = vaultController.state.activeIdentity!;

      await requestController.acceptRequest(
        SigningRequest(
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
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.widgetWithText(FilledButton, 'Sign event'), findsOneWidget);
      expect(find.textContaining('DEMO'), findsNothing);
    });

    testWidgets('approving with real signer completes the active request', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'User');
      final activeIdentity = vaultController.state.activeIdentity!;
      final realSigner = RealSignerService(vaultService);
      final realRequestController = RequestController(
        vaultController,
        realSigner,
      );

      final request = SigningRequest(
        id: 'req1',
        provenance: const RequestProvenance(
          sourceDisplayName: 'App',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 1,
        eventPayload: const {
          'kind': 1,
          'content': 'test',
          'created_at': 1777618800,
          'tags': [],
        },
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await realRequestController.acceptRequest(request);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultControllerProvider.overrideWith((ref) => vaultController),
            signerServiceProvider.overrideWithValue(realSigner),
            requestControllerProvider.overrideWith(
              (ref) => realRequestController,
            ),
            relayProfileServiceProvider.overrideWithValue(
              FakeRelayProfileService(),
            ),
          ],
          child: const MaterialApp(home: ApprovalScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Sign event'));
      await tester.pumpAndSettle();

      expect(find.text('No active requests'), findsOneWidget);
      expect(realRequestController.state.signedEvents[request.id], isNotNull);
      expect(find.textContaining(activeIdentity.localId), findsNothing);
    });

    testWidgets('a sign_message request is shown as signing (#8)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test User');
      final identity = vaultController.state.activeIdentity!;
      await nip55Controller.handleRawIntent({
        'requestToken': 'sign-message-token',
        'type': 'sign_message',
        'content': 'hello message',
        'currentUser': identity.publicKey,
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Sign'), findsOneWidget);
      expect(find.text('Signs this exact text with your key'), findsOneWidget);
      expect(find.text('MESSAGE'), findsOneWidget);
      expect(find.text('hello message'), findsOneWidget);
      expect(find.text('Encrypt'), findsNothing);
      expect(find.text('Encryption operation'), findsNothing);
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

      await tester.tap(find.text('Sign event'));
      await tester.pump(); // This SHOULD show the error immediately
      await tester.pump();

      // Should show failure message
      expect(find.textContaining('Vault is locked'), findsOneWidget);
      // Still on the same screen (not cleared)
      expect(find.text('Approval Request'), findsOneWidget);
    });

    testWidgets('signing failure displays safe failure message', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'User');
      final activeIdentity = vaultController.state.activeIdentity!;

      // Setup failing signer
      final failingSigner = FakeSignerService(shouldFail: true);
      // Create a NEW controller with the failing signer
      final failingRequestController = RequestController(
        vaultController,
        failingSigner,
      );

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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultControllerProvider.overrideWith((ref) => vaultController),
            signerServiceProvider.overrideWithValue(failingSigner),
            requestControllerProvider.overrideWith(
              (ref) => failingRequestController,
            ),
            relayProfileServiceProvider.overrideWithValue(
              FakeRelayProfileService(),
            ),
          ],
          child: const MaterialApp(home: ApprovalScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Sign event'));

      // FakeSignerService has 100ms delay.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fake signer error'), findsOneWidget);
      expect(find.text('Approval Request'), findsOneWidget);
    });

    testWidgets(
      'public-key NIP-55 completion removes action buttons and unsupported blank permissions',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        await vaultController.createVault('1234');
        await vaultController.createIdentity(displayName: 'User');

        await nip55Controller.handleRawIntent({
          'requestToken': 'pk-token',
          'type': 'get_public_key',
          'permissions': '["connect","get_public_key",""]',
          'callingPackage': 'com.example.amethyst',
          'callerAppLabel': 'Amethyst',
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        expect(find.text('Approval Request'), findsOneWidget);
        expect(find.text('Reject'), findsOneWidget);
        expect(find.text('Share public key'), findsOneWidget);

        await tester.tap(find.text('Show details'));
        await tester.pumpAndSettle();

        expect(find.textContaining('REQUESTED PERMISSIONS'), findsOneWidget);
        expect(
          find.textContaining('Unsupported permission'),
          findsNothing,
        );

        await tester.tap(find.text('Share public key'));
        await tester.pumpAndSettle();

        expect(find.text('No active requests'), findsOneWidget);
        expect(find.text('Reject'), findsNothing);
        expect(find.text('Share public key'), findsNothing);
        expect(nip55Gateway.completedToken, 'pk-token');
      },
    );

    for (final callingPackage in [null, 'com.example.amethyst']) {
      testWidgets(
        'public-key details show the active key that will be shared '
        '(calling package: $callingPackage) (diogel-io/workspace#39)',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.reset());

          await vaultController.createVault('1234');
          await vaultController.createIdentity(displayName: 'User');
          final pubkey = vaultController.state.activeIdentity!.publicKey;
          final npub = Nostr.instance.services.bech32.encodePublicKeyToNpub(
            pubkey,
          );

          // NIP-55 get_public_key carries no current_user: the client is
          // asking for the key because it doesn't know it yet.
          await nip55Controller.handleRawIntent({
            'requestToken': 'pk-token',
            'type': 'get_public_key',
            'callingPackage': ?callingPackage,
          });

          await tester.pumpWidget(createTestWidget());
          await tester.pump();
          await tester.tap(find.text('Show details'));
          await tester.pumpAndSettle();

          expect(find.text('No active identity'), findsNothing);
          expect(
            find.text(
              '${npub.substring(0, 8)}...${npub.substring(npub.length - 8)}',
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('shows kind 31234 NIP-37 Draft Wrap approval summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test User');
      final activeIdentity = vaultController.state.activeIdentity!;

      final request = SigningRequest(
        id: 'req-nip37',
        provenance: const RequestProvenance(
          sourceDisplayName: 'Amethyst',
          sourceIdentifier: 'com.vitorpamplona.amethyst',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 31234,
        eventPayload: const {
          'kind': 31234,
          'nip55Method': 'sign_event',
          'nip55PermissionScope': 'sign_event:31234',
          'content': 'encrypted-payload',
          'tags': [
            ['d', 'draft-id'],
            ['k', '1'],
            ['expiration', '1777618800'],
          ],
        },
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Draft wrap / NIP-37'), findsOneWidget);
      expect(find.text('Encrypted draft payload'), findsOneWidget);
      expect(find.text('Risk note'), findsOneWidget);
      expect(find.textContaining('Unknown event kind'), findsNothing);

      await tester.tap(find.text('Show details'));
      await tester.pump();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pump();

      expect(find.text('sign_event'), findsOneWidget);
      expect(
        find.text('Remember permission: sign kind 31234 only'),
        findsOneWidget,
      );
    });

    testWidgets('shows kind 5 NIP-09 Event Deletion Request approval summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test User');
      final activeIdentity = vaultController.state.activeIdentity!;

      final request = SigningRequest(
        id: 'req-nip09',
        provenance: const RequestProvenance(
          sourceDisplayName: 'Amethyst',
          sourceIdentifier: 'com.vitorpamplona.amethyst',
          trustStatus: RequestTrustStatus.knownTrusted,
        ),
        actionType: SigningActionType.signEvent,
        eventKind: 5,
        eventPayload: const {
          'kind': 5,
          'nip55Method': 'sign_event',
          'nip55PermissionScope': 'sign_event:5',
          'content': '',
          'tags': [
            ['e', '<event-id>'],
            ['k', '1'],
          ],
        },
        targetIdentityPublicKey: activeIdentity.publicKey,
        targetIdentityLocalId: activeIdentity.localId,
        createdAt: DateTime.now(),
        status: SigningRequestStatus.pending,
      );

      await requestController.acceptRequest(request);
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Event deletion request / NIP-09'), findsOneWidget);
      expect(find.text('Deletion request with no reason text.'), findsOneWidget);
      expect(find.text('Risk note'), findsOneWidget);
      expect(find.textContaining('Unknown event kind'), findsNothing);

      await tester.tap(find.text('Show details'));
      await tester.pump();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pump();

      expect(find.text('sign_event'), findsOneWidget);
      expect(
        find.text('Remember permission: sign kind 5 only'),
        findsOneWidget,
      );
      expect(find.text('2 tag(s): e:1, k:1'), findsOneWidget);
    });

    testWidgets(
      'crypto NIP-55 completion failure removes stale action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        await vaultController.createVault('1234');
        await vaultController.createIdentity(displayName: 'User');
        final activeIdentity = vaultController.state.activeIdentity!;

        await nip55Controller.handleRawIntent({
          'requestToken': 'crypto-token',
          'type': 'nip04_decrypt',
          'content': 'not-valid-nip04-ciphertext',
          'pubkey': 'b' * 64,
          'currentUser': activeIdentity.publicKey,
          'callingPackage': 'com.example.amethyst',
          'callerAppLabel': 'Amethyst',
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        expect(find.text('Approval Request'), findsOneWidget);
        expect(find.text('Reject'), findsOneWidget);
        expect(find.text('Decrypt'), findsOneWidget);

        await tester.tap(find.text('Decrypt'));
        await tester.pumpAndSettle();

        expect(find.text('No active requests'), findsOneWidget);
        expect(find.text('Reject'), findsNothing);
        expect(find.text('Decrypt'), findsNothing);
        expect(find.text('Encrypt'), findsNothing);
        expect(nip55Gateway.rejectedToken, 'crypto-token');
      },
    );
  });

  // A NIP-46 client's request on the shared Approval screen (#27).
  group('a NIP-46 request', () {
    late _RecordingNip46Controller nip46Controller;
    late ProviderContainer container;

    Nip46PendingMethodRequest pending(
      String id,
      Nip46Method method,
      List<String> params, {
      String clientUrl = 'https://notes.example.com',
    }) {
      final identity = vaultController.state.activeIdentity!;
      return Nip46PendingMethodRequest(
        sessionId: 'session-1',
        request: Nip46Request(id: id, method: method, params: params),
        usesNip04: false,
        identityLocalId: identity.localId,
        identityPubkey: identity.publicKey,
        receivedAt: DateTime(2026),
        clientPubkey: 'c' * 64,
        clientName: 'Remote Notes',
        clientUrl: clientUrl,
      );
    }

    Nip46PendingMethodRequest note(String id, String content) => pending(
      id,
      Nip46Method.signEvent,
      [
        jsonEncode({
          'kind': 1,
          'content': content,
          'tags': <Object>[],
          'created_at': 1700000000,
        }),
      ],
    );

    Future<void> pumpWithQueue(
      WidgetTester tester,
      List<Nip46PendingMethodRequest> queue,
    ) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());
      nip46Controller = _RecordingNip46Controller(
        vaultService: vaultService,
        vaultController: vaultController,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultControllerProvider.overrideWith((ref) => vaultController),
            signerServiceProvider.overrideWithValue(signerService),
            requestControllerProvider.overrideWith((ref) => requestController),
            nip55GatewayProvider.overrideWithValue(nip55Gateway),
            nip55ControllerProvider.overrideWith((ref) => nip55Controller),
            relayProfileServiceProvider.overrideWithValue(profileService),
            nip46ControllerProvider.overrideWith((ref) => nip46Controller),
            nip46ReviewQueueProvider.overrideWith((ref) => queue),
          ],
          child: const MaterialApp(home: ApprovalScreen()),
        ),
      );
      await tester.pump();
      container = ProviderScope.containerOf(
        tester.element(find.byType(ApprovalScreen)),
      );
    }

    setUp(() async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity(displayName: 'Test User');
    });

    testWidgets('a sign_event shows the event and the unverified client', (
      tester,
    ) async {
      await pumpWithQueue(tester, [note('sign-1', 'hello from remote')]);

      expect(find.text('Remote Notes'), findsOneWidget);
      expect(find.textContaining('hello from remote'), findsWidgets);
      expect(find.text('Sign event'), findsOneWidget);
      // Just once: NIP-46 decisions are not remembered yet (#28).
      expect(find.byType(TimeframeRow), findsNothing);

      await tester.tap(find.text('Show details'));
      await tester.pump();

      expect(find.text('NIP-46 METHOD'), findsOneWidget);
      expect(find.text('PERMISSION IF REMEMBERED'), findsNothing);
    });

    testWidgets('a client cannot add its own text to the review', (
      tester,
    ) async {
      await pumpWithQueue(tester, [
        pending('sign-1', Nip46Method.signEvent, [
          jsonEncode({
            'kind': 1,
            'content': 'hello',
            'tags': <Object>[],
            'created_at': 1700000000,
            'nip55Method': 'get_public_key',
            'nip55PermissionScope': 'get_public_key',
            'permissionWarnings': ['Symudol has verified this app'],
          }),
        ]),
      ]);
      await tester.tap(find.text('Show details'));
      await tester.pump();

      expect(find.text('NIP-46 METHOD'), findsOneWidget);
      expect(find.text('sign_event'), findsOneWidget);
      expect(find.textContaining('get_public_key'), findsNothing);
      expect(
        find.textContaining('Symudol has verified this app'),
        findsNothing,
      );
    });

    testWidgets('a client claiming a known app package is not shown as it', (
      tester,
    ) async {
      await pumpWithQueue(tester, [
        pending(
          'sign-1',
          Nip46Method.signEvent,
          [jsonEncode({'kind': 1, 'content': 'hello', 'tags': <Object>[]})],
          clientUrl: 'com.vitorpamplona.amethyst',
        ),
      ]);

      expect(find.text('Remote Notes'), findsOneWidget);
      // Amethyst's entry in the known-app directory.
      expect(find.text('Nostr client with TOR support and zaps'), findsNothing);
      expect(find.text('Unknown Provenance'), findsOneWidget);
    });

    testWidgets('an encrypt request shows the peer and payload', (
      tester,
    ) async {
      await pumpWithQueue(tester, [
        pending('encrypt-1', Nip46Method.nip44Encrypt, [
          'd' * 64,
          'secret text',
        ]),
      ]);

      expect(find.text('NIP-44 Encrypt'), findsOneWidget);
      expect(find.text('Encrypt'), findsOneWidget);
      expect(find.text('PEER PUBLIC KEY'), findsOneWidget);
      expect(find.text('secret text'), findsOneWidget);
    });

    testWidgets('Approve and Reject answer the request by its key', (
      tester,
    ) async {
      final request = note('sign-1', 'hello');
      await pumpWithQueue(tester, [request]);

      await tester.tap(find.text('Sign event'));
      await tester.pump();
      await tester.tap(find.text('Reject'));
      await tester.pump();

      expect(nip46Controller.approved, [request.key]);
      expect(nip46Controller.rejected, [request.key]);
    });

    testWidgets('the next queued request follows the first', (tester) async {
      final first = note('sign-1', 'first note');
      final second = note('sign-2', 'second note');
      await pumpWithQueue(tester, [first, second]);
      expect(find.textContaining('first note'), findsWidgets);
      expect(find.textContaining('second note'), findsNothing);

      await tester.tap(find.text('Sign event'));
      container.read(nip46ReviewQueueProvider.notifier).state = [second];
      await tester.pump();

      expect(nip46Controller.approved, [first.key]);
      expect(find.textContaining('first note'), findsNothing);
      expect(find.textContaining('second note'), findsWidgets);
    });

    testWidgets('a NIP-55 request is shown before a NIP-46 one', (
      tester,
    ) async {
      await nip55Controller.handleRawIntent({
        'requestToken': 'sign-message-token',
        'type': 'sign_message',
        'content': 'hello message',
        'currentUser': vaultController.state.activeIdentity!.publicKey,
      });

      await pumpWithQueue(tester, [note('sign-1', 'remote note')]);

      expect(find.text('hello message'), findsOneWidget);
      expect(find.text('Remote Notes'), findsNothing);
    });
  });
}
