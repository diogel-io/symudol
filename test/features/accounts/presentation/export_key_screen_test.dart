import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/sensitive_clipboard.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/accounts/presentation/accounts_screen.dart';
import 'package:symudol/features/accounts/presentation/export_key_screen.dart';
import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_vault_store.dart';

const _pin = '123456';
const _hexKey =
    '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';

/// Exporting one identity's nsec (diogel-io/symudol#24).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late VaultServiceImpl vault;
  late VaultController controller;
  late VaultIdentity identity;
  late String nsec;
  late List<MethodCall> copies;

  setUp(() async {
    ConcurrencyUtils.useSynchronousTasks = true;
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault(_pin);
    identity = await vault.importIdentity(_hexKey, displayName: 'Work');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock(_pin);
    nsec = await vault.exportPrivateKey(
      pin: _pin,
      identityLocalId: identity.localId,
    );
    copies = [];
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, (call) async {
      copies.add(call);
      return null;
    });
  });

  tearDown(() {
    ConcurrencyUtils.useSynchronousTasks = false;
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, null);
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultServiceProvider.overrideWithValue(vault),
          vaultControllerProvider.overrideWith((ref) => controller),
          profileNetworkStoreProvider.overrideWithValue(
            FakeProfileNetworkStore(),
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the PIN check finish: the Continue button shows a spinner
  /// meanwhile, so pumpAndSettle alone would never settle.
  Future<void> finishWork(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      final busy = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      if (!busy && i > 0) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    await tester.tap(find.byKey(const Key('exportKeyContinue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exportKeyPinField')), pin);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await finishWork(tester);
  }

  testWidgets('the warning shows first, and nothing is read before the PIN', (
    tester,
  ) async {
    await pump(tester, ExportKeyScreen(identity: identity));

    expect(find.byKey(const Key('exportKeyWarning')), findsOneWidget);
    expect(find.byKey(const Key('exportKeyPinField')), findsNothing);
    expect(find.byKey(const Key('exportKeyValue')), findsNothing);
    expect(find.textContaining('nsec1'), findsNothing);
  });

  testWidgets('the right PIN shows the key hidden until Show', (tester) async {
    await pump(tester, ExportKeyScreen(identity: identity));
    await enterPin(tester, _pin);

    expect(find.byKey(const Key('exportKeyValue')), findsOneWidget);
    expect(find.text(nsec), findsNothing);

    await tester.tap(find.byKey(const Key('exportKeyToggle')));
    await tester.pump();
    expect(find.text(nsec), findsOneWidget);

    await tester.tap(find.byKey(const Key('exportKeyToggle')));
    await tester.pump();
    expect(find.text(nsec), findsNothing);
  });

  testWidgets('Copy marks the key sensitive and clears it in 60 seconds', (
    tester,
  ) async {
    await pump(tester, ExportKeyScreen(identity: identity));
    await enterPin(tester, _pin);

    await tester.tap(find.byKey(const Key('exportKeyCopy')));
    await tester.pumpAndSettle();

    expect(copies.single.method, 'copySensitiveText');
    expect(copies.single.arguments, {
      'label': 'Nostr private key',
      'text': nsec,
      'clearAfterMs': 60000,
    });
    expect(find.textContaining('clears in 60 seconds'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a wrong PIN shows the failure and no key', (tester) async {
    await pump(tester, ExportKeyScreen(identity: identity));
    await enterPin(tester, '654321');

    expect(find.text('Invalid PIN. Please try again.'), findsOneWidget);
    expect(find.byKey(const Key('exportKeyValue')), findsNothing);
    expect(find.byKey(const Key('exportKeyContinue')), findsOneWidget);
    expect(await vault.getFailedUnlockAttempts(), 1);
  });

  testWidgets('cancelling the PIN shows nothing', (tester) async {
    await pump(tester, ExportKeyScreen(identity: identity));
    await tester.tap(find.byKey(const Key('exportKeyContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exportKeyValue')), findsNothing);
    expect(copies, isEmpty);
  });

  testWidgets('each identity tile opens the export screen', (tester) async {
    await pump(tester, const AccountsScreen());

    await tester.tap(find.byTooltip('Export private key'));
    await tester.pumpAndSettle();

    expect(find.byType(ExportKeyScreen), findsOneWidget);
    expect(find.byKey(const Key('exportKeyWarning')), findsOneWidget);
  });
}
