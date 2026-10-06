import 'package:symudol/app/app.dart';
import 'package:symudol/features/navigation/presentation/main_navigation_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/presentation/setup_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

void main() {
  testWidgets('WP0 Regression: Matching setup PIN twice routes to main navigation screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeStore = FakeVaultStore();

    // Start with a clean state (NoVault)
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(fakeStore),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify we are on SetupVaultScreen
    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(find.text('Create a security PIN'), findsOneWidget);

    final pin = ['1', '2', '3', '4', '5', '6'];

    // Enter first PIN
    for (var digit in pin) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Should now ask for confirmation
    expect(find.text('Confirm your PIN'), findsOneWidget);

    // Enter confirmation PIN
    for (var digit in pin) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    
    // Pump several times to allow the async createVault and state transitions
    for(int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify we are now on the MainNavigationScreen
    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.text('Accounts'), findsAtLeastNWidgets(1));
    expect(find.byType(SetupVaultScreen), findsNothing);
  });

  testWidgets('WP0 Regression: Mismatched setup PIN shows error and remains on setup', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeStore = FakeVaultStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(fakeStore),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();

    final pin1 = ['1', '2', '3', '4', '5', '6'];
    final pin2 = ['6', '5', '4', '3', '2', '1'];

    // Enter first PIN
    for (var digit in pin1) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Enter mismatched confirmation PIN
    for (var digit in pin2) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Verify error message and still on SetupVaultScreen
    expect(find.text('PINs do not match. Try again.'), findsOneWidget);
    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsNothing);
  });
}
