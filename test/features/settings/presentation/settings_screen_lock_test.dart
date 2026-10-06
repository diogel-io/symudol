import 'package:symudol/app/app.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

void main() {
  testWidgets('Manual lock clears state and returns to unlock screen', (WidgetTester tester) async {
    // Set a larger surface size to ensure all buttons are visible
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final store = FakeVaultStore();
    // Pre-populate store with a wrapped DEK so it goes to VaultLocked initially
    // await store.setWrappedDek('wrapped-dek'); // DO NOT pre-populate, we want NoVault -> Setup

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(store),
        ],
        child: const DiogelApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Should be on SetupVaultScreen initially (because controller starts with NoVault from service.state)
    expect(find.text('Symudol'), findsOneWidget);

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

    // 3. Should be on MainNavigationScreen (Accounts)
    expect(find.text('Accounts'), findsWidgets); // Title and Nav item

    // 4. Navigate to Settings
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNWidgets(2)); // Title and Nav item

    // 5. Tap "Lock Vault"
    await tester.tap(find.text('Lock Vault'));
    await tester.pumpAndSettle();

    // 6. Should be back on UnlockVaultScreen
    expect(find.text('Unlock Vault'), findsWidgets);
    
    // 7. Verify back navigation does not go back to Settings
    // We use the system back button (simulated)
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();
    
    // Should still be on UnlockVaultScreen (or app exited if it's the root)
    // In our case, DiogelApp's home is switched, so there is no "back" to Settings.
    expect(find.text('Unlock Vault'), findsWidgets);
    expect(find.text('Settings'), findsNothing);
  });
}
