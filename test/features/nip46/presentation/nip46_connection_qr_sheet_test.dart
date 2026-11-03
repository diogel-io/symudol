import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/presentation/nip46_connection_qr_sheet.dart';
import 'package:symudol/features/nip46/presentation/nip46_qr_scan_screen.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';

const _clientPubkey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _nostrconnect =
    'nostrconnect://$_clientPubkey?relay=wss%3A%2F%2Frelay.example.com'
    '&secret=s1&name=Scanned';

/// Returns [result] from a scan, or reports no camera (#31).
class _FakeScanner implements Nip46QrScanner {
  final bool available;
  final String? result;
  int scans = 0;

  _FakeScanner({this.available = true, this.result});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> scan(BuildContext context) async {
    scans++;
    return result;
  }
}

void main() {
  late VaultServiceImpl vaultService;
  late VaultController vaultController;
  late Nip46Controller controller;

  // The sheet is only shown with the vault unlocked (#32).
  setUp(() async {
    ConcurrencyUtils.useSynchronousTasks = true;
    vaultService = VaultServiceImpl(FakeVaultStore());
    await vaultService.createVault('1234');
    vaultController = VaultController(vaultService);
    await vaultController.initialize();
  });

  tearDown(() => ConcurrencyUtils.useSynchronousTasks = false);

  /// Opens the sheet as Remote Signer does, so an import closes it.
  Future<void> openSheet(
    WidgetTester tester, {
    Nip46QrScanner? scanner,
  }) async {
    controller = Nip46Controller(
      sessionStore: FakeNip46SessionStore([]),
      vaultService: vaultService,
      vaultController: vaultController,
      relayService: FakeNip46RelayService(),
      crypto: const DartNip46Crypto(DartNostrCryptoService()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nip46ControllerProvider.overrideWith((ref) => controller),
          nip46QrScannerProvider.overrideWithValue(scanner ?? _FakeScanner()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const Nip46ConnectionQrSheet(),
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
  }

  testWidgets('the nostrconnect:// field offers no Copy or Cut (#96)', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Connect to a client'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nostrconnect://abc?secret=xyz');

    // Select the URI and open the toolbar; the sheet sits in a small test view.
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    field.userUpdateTextEditingValue(
      field.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 29),
      ),
      SelectionChangedCause.longPress,
    );
    field.showToolbar();
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });

  group('QR codes (#31)', () {
    testWidgets('shows the generated bunker:// token as a QR code', (tester) async {
      await openSheet(tester);
      expect(find.byType(QrImageView), findsNothing);

      await tester.tap(find.text('Generate bunker:// token'));
      await tester.pumpAndSettle();

      final session = controller.state.sessions.single;
      expect(find.byKey(const Key('nip46BunkerQrCode')), findsOneWidget);
      // The text and Copy stay beside it.
      expect(
        find.textContaining('bunker://${session.remoteSignerPubkey}'),
        findsOneWidget,
      );
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('a scanned nostrconnect:// code is imported for approval', (tester) async {
      final scanner = _FakeScanner(result: _nostrconnect);
      await openSheet(tester, scanner: scanner);
      await tester.tap(find.text('Connect to a client'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nip46ScanQrCode')));
      await tester.pumpAndSettle();

      expect(scanner.scans, 1);
      final pending = controller.state.pendingApproval;
      expect(pending?.clientPubkey, _clientPubkey);
      expect(pending?.clientName, 'Scanned');
      expect(pending?.pendingSecret, 's1');
    });

    testWidgets('leaving the scanner imports nothing', (tester) async {
      await openSheet(tester, scanner: _FakeScanner());
      await tester.tap(find.text('Connect to a client'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nip46ScanQrCode')));
      await tester.pumpAndSettle();

      expect(controller.state.pendingApproval, isNull);
      expect(controller.state.sessions, isEmpty);
    });

    testWidgets('with no camera there is no Scan button, and paste still works', (tester) async {
      await openSheet(tester, scanner: _FakeScanner(available: false));
      await tester.tap(find.text('Connect to a client'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nip46ScanQrCode')), findsNothing);

      await tester.enterText(find.byType(TextField), _nostrconnect);
      await tester.tap(find.text('Import and connect'));
      await tester.pumpAndSettle();

      expect(controller.state.pendingApproval?.clientPubkey, _clientPubkey);
    });
  });
}
