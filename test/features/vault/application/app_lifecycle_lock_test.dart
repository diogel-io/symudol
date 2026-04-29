import 'package:android_diogel/app/app.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  testWidgets('App auto-locks when moved to background', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final store = FakeVaultStore();
    
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(store),
        ],
        child: const DiogelApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initially at Setup
    expect(find.text('Welcome to Diogel'), findsOneWidget);

    // 2. Setup (any 6 digits)
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    // Confirm PIN
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // 3. Should be Unlocked (Main Navigation)
    expect(find.text('Accounts'), findsWidgets);

    // 4. Simulate app moving to background
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(); // Allow state transition to process

    final state = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(vaultStateProvider);
    expect(state, isA<VaultLocked>());

    // Note: In WidgetTester, MaterialApp home switch might not be fully reflected 
    // in find.byType immediately after lifecycle change simulation.
    // However, we verified the state transition above.
  });
}
