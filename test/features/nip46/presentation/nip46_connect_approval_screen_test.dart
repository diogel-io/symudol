import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/presentation/nip46_connect_approval_screen.dart';
import 'package:symudol/features/nip55/domain/nip55_approval_timeframe.dart';
import 'package:symudol/features/requests/presentation/widgets/remember_row.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';

/// Records the timeframe the connect approval is given (#28).
class _RecordingController extends Nip46Controller {
  _RecordingController(VaultServiceImpl vaultService)
    : super(
        sessionStore: FakeNip46SessionStore([]),
        vaultService: vaultService,
        vaultController: VaultController(vaultService),
        relayService: FakeNip46RelayService(),
        crypto: DartNip46Crypto(const DartNostrCryptoService()),
      );

  final List<Nip55ApprovalTimeframe> approvedWith = [];

  @override
  Future<void> approveConnection({
    Nip55ApprovalTimeframe timeframe = Nip55ApprovalTimeframe.justOnce,
  }) async => approvedWith.add(timeframe);
}

const _nostrconnect =
    'nostrconnect://a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1'
    '?secret=testsecret123&relay=wss%3A%2F%2Frelay.example.com&name=Test%20client';

Nip46Controller _buildController() {
  final vaultService = VaultServiceImpl(FakeVaultStore());
  return Nip46Controller(
    sessionStore: FakeNip46SessionStore([]),
    vaultService: vaultService,
    vaultController: VaultController(vaultService),
    relayService: FakeNip46RelayService(),
    crypto: DartNip46Crypto(const DartNostrCryptoService()),
  );
}

void main() {
  // Remote Signer can open this after the request has ended, for example
  // when it times out between the tap on Review request and the first build
  // (diogel-io/symudol#125).
  testWidgets('says a request that has ended has ended, and Close pops it', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nip46ControllerProvider.overrideWith((ref) => _buildController()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const Nip46ConnectApprovalScreen(),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('This connection request has ended.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Approve'), findsNothing);

    await tester.tap(find.byKey(const Key('nip46RequestEndedClose')));
    await tester.pumpAndSettle();

    expect(find.byType(Nip46ConnectApprovalScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  // The permissions a client asks for are listed, and remembered only for
  // the timeframe the user picks (#28).
  group('requested permissions (#28)', () {
    Future<_RecordingController> pumpRequest(
      WidgetTester tester,
      String perms,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = _RecordingController(
        VaultServiceImpl(FakeVaultStore()),
      );
      await controller.importNostrconnectToken(
        '$_nostrconnect&perms=${Uri.encodeComponent(perms)}',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nip46ControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: Nip46ConnectApprovalScreen()),
        ),
      );
      await tester.pump();
      return controller;
    }

    testWidgets('lists them, flags broad signing, and passes the timeframe', (
      tester,
    ) async {
      final controller = await pumpRequest(
        tester,
        'sign_event:1,sign_event,nip44_encrypt',
      );

      expect(find.text('Requested permissions'), findsOneWidget);
      expect(find.text('Sign kind 1'), findsOneWidget);
      expect(
        find.text(
          'Sign any event kind (reviewed every time, never remembered)',
        ),
        findsOneWidget,
      );
      expect(find.text('NIP-44 encrypt'), findsOneWidget);
      expect(find.byType(TimeframeRow), findsOneWidget);

      await tester.tap(find.text('Always'));
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pump();

      expect(controller.approvedWith, [Nip55ApprovalTimeframe.always]);
      await controller.rejectConnection();
    });

    testWidgets('offers no timeframe when nothing can be remembered', (
      tester,
    ) async {
      final controller = await pumpRequest(tester, 'sign_event');

      expect(find.byType(TimeframeRow), findsNothing);
      await tester.tap(find.text('Approve'));
      await tester.pump();

      expect(controller.approvedWith, [Nip55ApprovalTimeframe.justOnce]);
      await controller.rejectConnection();
    });
  });
}
