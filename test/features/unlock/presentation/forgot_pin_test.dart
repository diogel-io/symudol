import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/app.dart';
import 'package:symudol/features/backup/application/backup_providers.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/unlock/presentation/pin_lockout_countdown.dart';
import 'package:symudol/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:symudol/features/unlock/presentation/widgets/forgot_pin_dialog.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/presentation/setup_vault_screen.dart';

import '../../../fakes/fake_backup_files.dart';
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

/// Identity records that can't be read, as after a Keystore failure.
class _UnreadableIdentitiesStore extends FakeVaultStore {
  bool failIdentityReads = false;

  @override
  Future<List<VaultIdentityRecord>> getIdentities() {
    if (failIdentityReads) throw PlatformException(code: 'read_failed');
    return super.getIdentities();
  }
}

/// Records whether the vault was already gone when a request was answered,
/// and can fail the answer as the method channel might.
class _AnsweringGateway extends FakeNip55Gateway {
  _AnsweringGateway(this.store);

  final FakeVaultStore store;
  bool failRejects = false;
  bool? vaultGoneWhenAnswered;

  @override
  Future<void> rejectNip55Intent({
    required String requestToken,
    String? error,
    bool rejected = false,
  }) async {
    vaultGoneWhenAnswered = await store.getWrappedDek() == null;
    if (failRejects) throw PlatformException(code: 'reject_failed');
    return super.rejectNip55Intent(
      requestToken: requestToken,
      error: error,
      rejected: rejected,
    );
  }
}

/// The unlock screen's "Forgot PIN?" (#22): an explanation, then the same
/// erase as Settings → Wipe Vault, while the vault is locked.
void main() {
  late _UnreadableIdentitiesStore store;
  late _AnsweringGateway gateway;
  late String pubkey;
  late FakeBackupFiles backupFiles;

  setUp(() async {
    backupFiles = FakeBackupFiles();
    PinLockoutCountdown.stopwatchFactory = () => clock.stopwatch();
    store = _UnreadableIdentitiesStore();
    gateway = _AnsweringGateway(store);
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
          backupFilesProvider.overrideWithValue(backupFiles),
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

  testWidgets('Restore from a backup erases, then opens the restore after a '
      'new PIN (#25)', (tester) async {
    await pumpApp(tester);
    await openForgotPin(tester);

    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wipeVaultConfirmationField')),
      'WIPE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe vault'));
    await tester.pumpAndSettle();
    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(backupFiles.picks, 0);

    for (var round = 0; round < 2; round++) {
      for (var digit = 1; digit <= 6; digit++) {
        await tester.tap(find.text('$digit'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    // The file picker opens on the new, empty vault.
    expect(backupFiles.picks, 1);
  });

  testWidgets('a restore whose wipe is cancelled is forgotten (#25)', (
    tester,
  ) async {
    await pumpApp(tester);
    await openForgotPin(tester);

    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UnlockVaultScreen)),
    );
    expect(container.read(restoreAfterSetupProvider), isFalse);
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

  testWidgets('answers the waiting NIP-55 request only after the wipe', (
    tester,
  ) async {
    gateway.initial = {
      'requestToken': 'token-waiting',
      'type': 'sign_message',
      'content': 'hello',
      'currentUser': pubkey,
    };
    await pumpApp(tester);

    await openForgotPin(tester);
    await eraseThroughDialogs(tester);

    expect(gateway.vaultGoneWhenAnswered, isTrue);
    expect(
      gateway.rejectedErrorsByToken['token-waiting'],
      'The Symudol vault was erased',
    );
  });

  testWidgets('still erases when the waiting request cannot be answered', (
    tester,
  ) async {
    gateway
      ..failRejects = true
      ..initial = {
        'requestToken': 'token-waiting',
        'type': 'sign_message',
        'content': 'hello',
        'currentUser': pubkey,
      };
    await pumpApp(tester);

    await openForgotPin(tester);
    await eraseThroughDialogs(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(await store.getWrappedDek(), isNull);
  });

  testWidgets('still erases when the identity records cannot be read', (
    tester,
  ) async {
    await pumpApp(tester);
    store.failIdentityReads = true;

    await openForgotPin(tester);
    await tester.tap(find.text('Erase and start again'));
    await tester.pumpAndSettle();
    expect(find.text('• Every identity and its private key'), findsOneWidget);
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
  });
}
