import 'package:android_diogel/app/app.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  Future<ProviderContainer> pumpUnlockedApp(
    WidgetTester tester,
    FakeVaultStore store,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultStoreProvider.overrideWithValue(store)],
        child: const DiogelApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Welcome to Diogel'), findsOneWidget);

    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsWidgets);
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('background delay 0 locks immediately', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultLocked>());
  });

  testWidgets('background delay 5 does not lock before delay', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 4, seconds: 59));

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  testWidgets('background delay 5 expires session after delay', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 5, seconds: 1));
    await tester.pumpAndSettle();

    final state = container.read(vaultStateProvider);
    expect(state, isA<SessionExpired>());
  });

  testWidgets('hidden schedules background lock', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultLocked>());
  });

  testWidgets('background delay -1 does not lock on background', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(-1);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 2));
    await tester.pumpAndSettle();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  testWidgets('resume before delay cancels background lock timer', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(minutes: 4));

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  testWidgets('inactive alone does not immediately lock', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });
}
