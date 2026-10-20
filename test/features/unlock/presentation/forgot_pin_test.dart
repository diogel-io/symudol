import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/app.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/unlock/presentation/pin_lockout_countdown.dart';
import 'package:symudol/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:symudol/features/unlock/presentation/widgets/forgot_pin_dialog.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/presentation/setup_vault_screen.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_nip55_permission_store.dart';
import '../../../fakes/fake_vault_store.dart';
import '../../nip55/application/nip55_controller_test.dart'
    show FakeNip55Gateway;

/// Native mirror calls do nothing: in widget tests the real ones
/// wait on a platform channel that never answers in fake time.
class _QuietNativeSync extends Nip55NativeMirrorSync {
  @override
  Future<void> wipeNativeState() async {}

  @override
  Future<void> syncGrants(List<Nip55PermissionGrant> grants) async {}

  @override
  Future<void> setActiveIdentityPubkey(String? pubkey) async {}

  @override
  Future<void> setActiveKey({
    required String privateKey,
    required String publicKey,
    required String localId,
  }) async {}

  @override
  Future<void> clearActiveKey() async {}

  @override
  Future<void> setLockDeadline(Duration delay) async {}

  @override
  Future<void> clearLockDeadline() async {}
}

/// The unlock screen's "Forgot PIN?" (#22): an explanation, then the same
/// erase as Settings → Wipe Vault, while the vault is locked.
void main() {
  late FakeVaultStore store;
  late FakeNip55Gateway gateway;
  late String pubkey;

  setUp(() async {
    PinLockoutCountdown.stopwatchFactory = () => clock.stopwatch();
    store = FakeVaultStore();
    gateway = FakeNip55Gateway();
    // An existing vault with two identities, left locked.
    final setup = VaultServiceImpl(store);
    await setup.createVault('123456');
    pubkey = (await setup.createIdentity(displayName: 'Alice')).publicKey;
    await setup.createIdentity(displayName: 'Bob');
  });

  tearDown(() => PinLockoutCountdown.stopwatchFactory = Stopwatch.new);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(store),
          nip55GatewayProvider.overrideWithValue(gateway),
          nip55PermissionStoreProvider.overrideWithValue(
            FakeNip55PermissionStore(),
          ),
          nip46SessionStoreProvider.overrideWithValue(FakeNip46SessionStore()),
          nip55NativeSyncProvider.overrideWithValue(_QuietNativeSync()),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UnlockVaultScreen), findsOneWidget);
  }

  Future<void> openForgotPin(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('forgotPinButton')));
    await tester.pumpAndSettle();
  }

  Future<void> eraseThroughDialogs(WidgetTester tester) async {
    await tester.tap(find.text('Erase and start again'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wipeVaultConfirmationField')),
      'WIPE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe vault'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the PIN cannot be recovered; Cancel keeps the vault', (
    tester,
  ) async {
    await pumpApp(tester);

    await openForgotPin(tester);
    expect(find.byType(ForgotPinDialog), findsOneWidget);
    expect(
      find.textContaining("Symudol can't recover or reset your PIN"),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPinDialog), findsNothing);
    expect(find.byType(UnlockVaultScreen), findsOneWidget);
    expect(await store.getWrappedDek(), isNotNull);
  });

  testWidgets('erasing, while locked, names what is lost and returns to setup', (
    tester,
  ) async {
    await pumpApp(tester);

    await openForgotPin(tester);
    await tester.tap(find.text('Erase and start again'));
    await tester.pumpAndSettle();
    // Counted from the stored records, though the vault is locked.
    expect(find.text('• 2 identities and their private keys'), findsOneWidget);
    expect(find.text('• 0 NIP-46 connections'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('wipeVaultConfirmationField')),
      'WIPE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe vault'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(await store.getWrappedDek(), isNull);
    expect(await store.getIdentities(), isEmpty);
  });

  testWidgets('works during a PIN lockout', (tester) async {
    await store.setLockout(
      VaultLockout(
        bootCount: 0,
        startElapsedMs: DateTime.now().millisecondsSinceEpoch,
        durationMs: const Duration(minutes: 15).inMilliseconds,
      ),
    );
    await pumpApp(tester);
    expect(find.byKey(const Key('unlockLockoutMessage')), findsOneWidget);

    await openForgotPin(tester);
    await eraseThroughDialogs(tester);

    expect(find.byType(SetupVaultScreen), findsOneWidget);
  });

  testWidgets('answers a NIP-55 request that was waiting for unlock', (
    tester,
  ) async {
    gateway.initial = {
      'requestToken': 'token-waiting',
      'type': 'sign_message',
      'content': 'hello',
      'currentUser': pubkey,
    };
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UnlockVaultScreen)),
    );
    expect(container.read(nip55ControllerProvider).isWaitingForUnlock, isTrue);

    await openForgotPin(tester);
    await eraseThroughDialogs(tester);

    expect(gateway.rejectedTokens, contains('token-waiting'));
    expect(gateway.rejectedFlagsByToken['token-waiting'], isFalse);
    expect(container.read(nip55ControllerProvider).isWaitingForUnlock, isFalse);
  });
}
