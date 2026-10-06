import 'package:symudol/app/app.dart';
import 'package:symudol/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/presentation/setup_vault_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

void main() {
  testWidgets('WP1 Regression: Existing vault shows Unlock screen on start', (
    WidgetTester tester,
  ) async {
    final fakeStore = FakeVaultStore();
    // Simulate existing vault by setting a wrapped DEK
    await fakeStore.setWrappedDek('wrapped-dek-placeholder');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(fakeStore),
        ],
        child: const DiogelApp(),
      ),
    );
    
    await tester.pumpAndSettle();

    expect(find.byType(UnlockVaultScreen), findsOneWidget);
    expect(find.byType(SetupVaultScreen), findsNothing);
  });

  testWidgets('WP1 Regression: No vault shows Setup screen on start', (
    WidgetTester tester,
  ) async {
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

    expect(find.byType(SetupVaultScreen), findsOneWidget);
    expect(find.byType(UnlockVaultScreen), findsNothing);
  });
}
