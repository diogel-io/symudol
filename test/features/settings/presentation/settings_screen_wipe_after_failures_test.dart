import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';

import '../../../fakes/fake_vault_store.dart';

/// The "Erase after failed PIN attempts" setting (#16).
void main() {
  late FakeVaultStore store;
  late ProviderContainer container;

  setUp(() async {
    store = FakeVaultStore();
    container = ProviderContainer(
      overrides: [vaultStoreProvider.overrideWithValue(store)],
    );
    await container.read(vaultControllerProvider.notifier).initialize();
    await container.read(vaultControllerProvider.notifier).createVault('123456');
  });

  tearDown(() => container.dispose());

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String option) async {
    await tester.tap(find.text('Erase after failed PIN attempts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  testWidgets('is off by default', (tester) async {
    await pumpSettings(tester);

    final tile = find.byKey(const Key('wipeAfterFailuresTile'));
    expect(
      find.descendant(of: tile, matching: find.text('Off')),
      findsOneWidget,
    );
  });

  testWidgets('turning it on asks first', (tester) async {
    await pumpSettings(tester);

    await pick(tester, '10 failed attempts');
    expect(find.text('Erase after 10 failed attempts?'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(await store.getWipeAfterFailures(), 10);
    expect(find.text('After 10 failed attempts'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation leaves it off', (tester) async {
    await pumpSettings(tester);

    await pick(tester, '15 failed attempts');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await store.getWipeAfterFailures(), isNull);
  });

  testWidgets('turning it off does not ask', (tester) async {
    await store.setWipeAfterFailures(20);
    await container.read(vaultControllerProvider.notifier).initialize();
    await pumpSettings(tester);

    await pick(tester, 'Off');

    expect(find.byType(AlertDialog), findsNothing);
    expect(await store.getWipeAfterFailures(), isNull);
  });
}
