import 'package:symudol/app/app.dart';
import 'package:symudol/features/nip46/application/nip46_feature.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_scope.dart';
import 'package:symudol/features/settings/presentation/widgets/wipe_vault_dialog.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/presentation/setup_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_nip55_permission_store.dart';
import '../../../fakes/fake_vault_store.dart';

class _RecordingNativeSync extends Nip55NativeMirrorSync {
  int wipes = 0;

  @override
  Future<void> wipeNativeState() async => wipes++;

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

Nip46Session _session(String id) => Nip46Session(
  id: id,
  clientPubkey: 'client-$id',
  remoteSignerPubkey: 'remote-$id',
  remoteSignerPrivkey: 'secret-$id',
  relays: const ['wss://relay.example'],
  grantedScopes: const [],
  status: Nip46SessionStatus.active,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  Future<void> showWipeDialog(
    WidgetTester tester, {
    required int identityCount,
    required int connectionCount,
    bool showConnections = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => WipeVaultDialog(
                  identityCount: identityCount,
                  connectionCount: connectionCount,
                  showConnections: showConnections,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton wipeButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Wipe vault'),
  );

  testWidgets('names what is lost, with counts', (tester) async {
    await showWipeDialog(tester, identityCount: 2, connectionCount: 1);

    expect(find.text('• 2 identities and their private keys'), findsOneWidget);
    expect(find.text('• Every Trusted app permission'), findsOneWidget);
    expect(find.text('• 1 NIP-46 connection'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });

  // Release builds hide NIP-46 for Android 1.0 (#26).
  testWidgets('leaves NIP-46 connections out when NIP-46 is hidden', (
    tester,
  ) async {
    await showWipeDialog(
      tester,
      identityCount: 2,
      connectionCount: 1,
      showConnections: false,
    );

    expect(find.text('• 2 identities and their private keys'), findsOneWidget);
    expect(find.text('• Every Trusted app permission'), findsOneWidget);
    expect(find.textContaining('NIP-46'), findsNothing);
  });

  testWidgets('wipe stays disabled until WIPE is typed', (tester) async {
    await showWipeDialog(tester, identityCount: 1, connectionCount: 0);
    final field = find.byKey(const Key('wipeVaultConfirmationField'));

    expect(wipeButton(tester).onPressed, isNull);

    await tester.enterText(field, 'WIP');
    await tester.pump();
    expect(wipeButton(tester).onPressed, isNull);

    await tester.enterText(field, 'wipe');
    await tester.pump();
    expect(wipeButton(tester).onPressed, isNull);

    await tester.enterText(field, 'WIPE');
    await tester.pump();
    expect(wipeButton(tester).onPressed, isNotNull);
  });

  testWidgets('cancel keeps the vault', (tester) async {
    await showWipeDialog(tester, identityCount: 1, connectionCount: 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(WipeVaultDialog), findsNothing);
  });

  testWidgets('wiping from Settings erases everything and returns to setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final vaultStore = FakeVaultStore();
    final grantStore = FakeNip55PermissionStore()
      ..grants.add(
        Nip55PermissionGrant(
          id: 'grant-1',
          identityPubkey: 'pubkey',
          packageName: 'com.example.client',
          scope: const GetPublicKeyScope(),
          decision: Nip55PermissionDecision.allow,
          createdAt: DateTime(2026, 10, 1),
        ),
      );
    final sessionStore = FakeNip46SessionStore([_session('s1')]);
    final nativeSync = _RecordingNativeSync();

    // An existing vault with two identities, unlocked.
    final setup = VaultServiceImpl(vaultStore);
    await setup.createVault('123456');
    await setup.createIdentity(displayName: 'Alice');
    await setup.createIdentity(displayName: 'Bob');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(vaultStore),
          nip55PermissionStoreProvider.overrideWithValue(grantStore),
          nip46SessionStoreProvider.overrideWithValue(sessionStore),
          nip55NativeSyncProvider.overrideWithValue(nativeSync),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Unlock through the app's own service.
    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Wipe Vault'), 200);
    await tester.tap(find.text('Wipe Vault'));
    await tester.pumpAndSettle();

    expect(find.text('• 2 identities and their private keys'), findsOneWidget);
    expect(find.text('• 1 NIP-46 connection'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('wipeVaultConfirmationField')),
      'WIPE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe vault'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(await vaultStore.getWrappedDek(), isNull);
    expect(await vaultStore.getIdentities(), isEmpty);
    expect(grantStore.grants, isEmpty);
    expect(sessionStore.sessions, isEmpty);
    expect(nativeSync.wipes, greaterThanOrEqualTo(1));
  });

  // A build that hides NIP-46 never names it, but still erases sessions an
  // earlier build stored (#26).
  testWidgets('wiping with NIP-46 hidden still erases its sessions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final vaultStore = FakeVaultStore();
    final sessionStore = FakeNip46SessionStore([_session('s1')]);

    final setup = VaultServiceImpl(vaultStore);
    await setup.createVault('123456');
    await setup.createIdentity(displayName: 'Alice');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(vaultStore),
          nip55PermissionStoreProvider.overrideWithValue(
            FakeNip55PermissionStore(),
          ),
          nip46SessionStoreProvider.overrideWithValue(sessionStore),
          nip55NativeSyncProvider.overrideWithValue(_RecordingNativeSync()),
          nip46EnabledProvider.overrideWithValue(false),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Wipe Vault'), 200);
    await tester.tap(find.text('Wipe Vault'));
    await tester.pumpAndSettle();

    expect(find.text('• 1 identity and its private key'), findsOneWidget);
    expect(find.textContaining('NIP-46'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('wipeVaultConfirmationField')),
      'WIPE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe vault'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(sessionStore.sessions, isEmpty);
  });
}
