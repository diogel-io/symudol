import 'package:android_diogel/app/app.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  testWidgets('Vault auto-locks after inactivity timeout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final store = FakeVaultStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultStoreProvider.overrideWithValue(store)],
        child: const DiogelApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Setup Vault
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // 2. Should be Unlocked
    expect(find.text('Accounts'), findsWidgets);

    // 3. Configure timeout to 1 minute
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('In-app inactivity timeout'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 minute'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 minute'), findsWidgets);

    // Go back to Accounts
    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();

    // 4. Wait for timeout
    await tester.pump(const Duration(minutes: 1, seconds: 1));

    final state = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(vaultStateProvider);
    expect(
      state,
      isA<SessionExpired>(),
      reason: 'Vault should be in SessionExpired state after timeout',
    );
    expect(find.text('Session Expired'), findsWidgets);
  });

  testWidgets('Rebuilds do not extend inactivity timeout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final store = FakeVaultStore();
    StateSetter? rebuildHost;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultStoreProvider.overrideWithValue(store)],
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return const DiogelApp();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In-app inactivity timeout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 minute'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 30));
    rebuildHost!(() {});
    await tester.pump();

    await tester.pump(const Duration(seconds: 31));

    final state = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(vaultStateProvider);
    expect(
      state,
      isA<SessionExpired>(),
      reason: 'A non-user rebuild must not refresh the inactivity timer',
    );
  });
}
