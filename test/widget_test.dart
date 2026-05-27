import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_diogel/app/app.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'fakes/fake_vault_store.dart';

void main() {
  testWidgets('app smoke test renders Android Diogel setup screen', (
    WidgetTester tester,
  ) async {
    final fakeStore = FakeVaultStore();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vaultStoreProvider.overrideWithValue(fakeStore),
      ],
      child: const DiogelApp(),
    ));
    
    // First pump to start initialization
    await tester.pump();
    
    // Wait for the async initialization to complete
    // Since FakeVaultStore is synchronous in its methods but VaultController.initialize is async,
    // we need to wait for the microtasks to complete.
    await tester.pumpAndSettle();

    expect(find.text('Diogel'), findsOneWidget);
    expect(find.text('Local Access PIN'), findsOneWidget);
    expect(find.text('Create a security PIN'), findsOneWidget);
  });
}
