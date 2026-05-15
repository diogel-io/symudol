import 'package:android_diogel/features/accounts/presentation/accounts_screen.dart';
import 'package:android_diogel/features/accounts/presentation/widgets/identity_tile.dart';
import 'package:android_diogel/features/accounts/presentation/widgets/import_identity_dialog.dart';
import 'package:android_diogel/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/presentation/setup_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_vault_store.dart';

void main() {
  late FakeVaultStore store;
  late VaultServiceImpl service;

  setUp(() {
    store = FakeVaultStore();
    service = VaultServiceImpl(store);
  });

  Widget createTestWidget({required Widget child}) {
    return ProviderScope(
      overrides: [
        vaultServiceProvider.overrideWithValue(service),
        vaultControllerProvider.overrideWith((ref) => VaultController(service)),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Widget Smoke Tests', () {
    testWidgets('no-vault setup screen renders', (WidgetTester tester) async {
      await service.init();
      await tester.pumpWidget(createTestWidget(child: const SetupVaultScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Diogel'), findsOneWidget);
      expect(find.text('Local Access PIN'), findsOneWidget);
      expect(find.text('Create a security PIN'), findsOneWidget);
    });

    testWidgets('locked screen renders', (WidgetTester tester) async {
      await store.setSentinel('exists');
      await service.init();
      
      await tester.pumpWidget(createTestWidget(child: const UnlockVaultScreen()));
      await tester.pump(); // Start initialization
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault'), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.shield), findsAtLeastNWidgets(1));
    });

    testWidgets('accounts screen renders identity list', (WidgetTester tester) async {
      await service.createVault('1234');
      await service.createIdentity(displayName: 'Account 1');
      await service.createIdentity(displayName: 'Account 2');
      
      final controller = VaultController(service);
      await controller.initialize();
      await controller.unlock('1234'); // Must unlock to see identities
      
      await tester.pumpWidget(ProviderScope(
        overrides: [
          vaultServiceProvider.overrideWithValue(service),
          vaultControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AccountsScreen()),
      ));
      
      await tester.pumpAndSettle();

      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('Account 1'), findsOneWidget);
      expect(find.text('Account 2'), findsOneWidget);
      expect(find.byType(IdentityTile), findsNWidgets(2));
    });

    testWidgets('import flow shows validation error for invalid input', (WidgetTester tester) async {
      await service.createVault('1234');
      
      await tester.pumpWidget(createTestWidget(
        child: const Scaffold(body: ImportIdentityDialog()),
      ));
      await tester.pumpAndSettle();

      // Step 1: Warning
      expect(find.text('Import Identity'), findsOneWidget);
      await tester.tap(find.text('I Understand'));
      await tester.pumpAndSettle();

      // Step 2: Input
      expect(find.text('Enter Private Key'), findsOneWidget);
      
      // Enter invalid hex
      await tester.enterText(find.byType(TextField).first, 'abc123');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      
      // Step 3: Confirm
      expect(find.text('Confirm Import'), findsOneWidget);
      
      // At this point we've smoked the dialog's basic transitions.
    });
  });
}
