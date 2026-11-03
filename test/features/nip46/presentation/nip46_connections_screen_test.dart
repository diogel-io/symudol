import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip46/presentation/nip46_connections_screen.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';
import '../../../fakes/fake_nip46_session_store.dart';

// The screen is only shown with the vault unlocked, and sessions are read
// only then (#32).
late VaultServiceImpl vaultService;
late VaultController vaultController;

Nip46Controller _buildController({List<Nip46Session> sessions = const []}) {
  final relayService = FakeNip46RelayService();
  final crypto = DartNip46Crypto(const DartNostrCryptoService());
  return Nip46Controller(
    sessionStore: FakeNip46SessionStore(List.of(sessions)),
    vaultService: vaultService,
    vaultController: vaultController,
    relayService: relayService,
    crypto: crypto,
  );
}

Widget _buildSubject(Nip46Controller controller) {
  return ProviderScope(
    overrides: [
      nip46ControllerProvider.overrideWith((ref) => controller),
    ],
    child: const MaterialApp(
      home: Nip46ConnectionsScreen(),
    ),
  );
}

void main() {
  setUp(() async {
    ConcurrencyUtils.useSynchronousTasks = true;
    vaultService = VaultServiceImpl(FakeVaultStore());
    await vaultService.createVault('1234');
    vaultController = VaultController(vaultService);
    await vaultController.initialize();
  });

  tearDown(() => ConcurrencyUtils.useSynchronousTasks = false);

  group('Nip46ConnectionsScreen', () {
    testWidgets('shows empty state when no sessions exist', (tester) async {
      await tester.pumpWidget(_buildSubject(_buildController()));
      await tester.pump();

      expect(find.text('No remote signer connections'), findsOneWidget);
      expect(find.text('New connection'), findsWidgets);
    });

    testWidgets('shows active session tile', (tester) async {
      final session = _session(clientName: 'Amethyst');
      await tester.pumpWidget(_buildSubject(_buildController(sessions: [session])));
      await tester.pumpAndSettle();

      expect(find.text('Amethyst'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);
    });

    testWidgets('appbar tooltip is New connection', (tester) async {
      await tester.pumpWidget(_buildSubject(_buildController()));
      await tester.pump();

      expect(find.byTooltip('New connection'), findsOneWidget);
    });

    testWidgets('screen title is Remote Signer (NIP-46)', (tester) async {
      await tester.pumpWidget(_buildSubject(_buildController()));
      await tester.pump();

      expect(find.text('Remote Signer (NIP-46)'), findsOneWidget);
    });
  });

  // A lock or Back closes the approval while the request stays pending. Here
  // the request arrives before the screen opens, as after an unlock.
  group('a pending connection request (#125)', () {
    testWidgets('Review request opens it and keeps it pending', (
      tester,
    ) async {
      final controller = _buildController();
      await controller.importNostrconnectToken(_nostrconnect);
      final pending = controller.state.pendingApproval;
      expect(pending, isNotNull);

      await tester.pumpWidget(_buildSubject(controller));
      await tester.pumpAndSettle();
      expect(find.text('Remote Signer Request'), findsNothing);

      await tester.tap(find.byKey(const Key('nip46ReviewRequest')));
      await tester.pumpAndSettle();

      expect(find.text('Remote Signer Request'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(controller.state.pendingApproval?.id, pending!.id);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Remote Signer Request'), findsNothing);
      expect(controller.state.pendingApproval, isNull);
      expect(
        controller.state.sessions.single.status,
        Nip46SessionStatus.active,
      );
    });

    testWidgets('reopening it does not restart the connect timer', (
      tester,
    ) async {
      final controller = _buildController();
      await controller.importNostrconnectToken(_nostrconnect);

      await tester.pumpWidget(_buildSubject(controller));
      await tester.pump(const Duration(seconds: 100));
      await tester.tap(find.byKey(const Key('nip46ReviewRequest')));
      await tester.pumpAndSettle();
      expect(find.text('Remote Signer Request'), findsOneWidget);

      await tester.pump(const Duration(seconds: 18));
      expect(controller.state.pendingApproval, isNotNull);

      // 120 s after the request arrived, not after the reopen.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(controller.state.pendingApproval, isNull);
      expect(controller.state.sessions, isEmpty);
      expect(find.text('Remote Signer Request'), findsNothing);
      expect(find.text('No remote signer connections'), findsOneWidget);
    });

    testWidgets('a bunker session awaiting its client has no Review', (
      tester,
    ) async {
      final controller = _buildController();
      await controller.initiateBunkerSession();

      await tester.pumpWidget(_buildSubject(controller));
      await tester.pumpAndSettle();

      expect(find.text('Awaiting connection…'), findsOneWidget);
      expect(find.byKey(const Key('nip46ReviewRequest')), findsNothing);
    });

    testWidgets('system Back keeps it pending, and Review request reopens it', (
      tester,
    ) async {
      final controller = _buildController();
      await tester.pumpWidget(_buildSubject(controller));
      await tester.pumpAndSettle();

      await controller.importNostrconnectToken(_nostrconnect);
      await tester.pumpAndSettle();
      expect(find.text('Remote Signer Request'), findsOneWidget);
      final pending = controller.state.pendingApproval;

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Remote Signer Request'), findsNothing);
      expect(controller.state.pendingApproval?.id, pending!.id);

      await tester.tap(find.byKey(const Key('nip46ReviewRequest')));
      await tester.pumpAndSettle();

      expect(find.text('Remote Signer Request'), findsOneWidget);
      expect(controller.state.pendingApproval?.id, pending.id);
      await controller.rejectConnection();
    });

    testWidgets('fits a narrow phone with a long client name', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = _buildController();
      await controller.importNostrconnectToken(
        '$_nostrconnectBase&name=A%20remote%20signing%20client%20with%20a%20long%20name',
      );

      await tester.pumpWidget(_buildSubject(controller));
      await tester.pumpAndSettle();

      // A RenderFlex overflow is reported as an exception.
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('nip46ReviewRequest')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsOneWidget);
      await controller.rejectConnection();
    });
  });
}

const _nostrconnectBase =
    'nostrconnect://a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1'
    '?secret=testsecret123&relay=wss%3A%2F%2Frelay.example.com';
const _nostrconnect = '$_nostrconnectBase&name=Test%20client';

Nip46Session _session({String? clientName}) {
  return Nip46Session(
    id: 'sess-1',
    clientPubkey:
        'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1',
    remoteSignerPubkey:
        'b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2',
    remoteSignerPrivkey: '0' * 64,
    relays: const ['wss://relay.example.com'],
    status: Nip46SessionStatus.active,
    createdAt: DateTime(2026),
    clientName: clientName,
  );
}
