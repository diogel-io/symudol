import 'package:android_diogel/features/accounts/presentation/widgets/import_identity_dialog.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../fakes/fake_vault_store.dart';

void main() {
  late FakeVaultStore store;
  late VaultServiceImpl service;

  setUp(() async {
    store = FakeVaultStore();
    service = VaultServiceImpl(store);
    await service.init();
    // Setup vault
    await service.createVault('1234');
  });

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [
        vaultServiceProvider.overrideWithValue(service),
        vaultControllerProvider.overrideWith((ref) {
          final controller = VaultController(service);
          return controller;
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ImportIdentityDialog(),
        ),
      ),
    );
  }

  group('ImportIdentityDialog', () {
    testWidgets('should follow the import flow', (WidgetTester tester) async {
      await store.setSentinel('vault_exists');
      await service.init();
      await service.unlock('1234');
      
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle(); // Wait for any initial microtasks
      
      final controller = ProviderScope.containerOf(tester.element(find.byType(ImportIdentityDialog))).read(vaultControllerProvider.notifier);
      await controller.unlock('1234'); // Explicitly unlock the controller
      await tester.pumpAndSettle();

      // Step 1: Warning
      expect(find.text('Import Identity'), findsOneWidget);
      expect(find.textContaining('WARNING'), findsOneWidget);
      expect(find.text('I Understand'), findsOneWidget);

      await tester.tap(find.text('I Understand'));
      await tester.pumpAndSettle();

      // Step 2: Input
      expect(find.text('Enter Private Key'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Key and Display Name
      
      // Use a valid hex key instead of nsec for deterministic test results if needed
      final hexKey = '0000000000000000000000000000000000000000000000000000000000000001';
      
      await tester.enterText(find.byType(TextField).first, hexKey);
      await tester.enterText(find.byType(TextField).last, 'My Imported Key');
      
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 3: Confirm
      expect(find.text('Confirm Import'), findsOneWidget);
      expect(find.text('Are you sure you want to import this identity?'), findsOneWidget);
      
      await tester.tap(find.text('Confirm & Import'));
      await tester.pump(); // Start the async operation
      // Multiple pumps to handle internal state changes and navigator pop
      await tester.pumpAndSettle(); 

      // Success: Dialog should be closed
      expect(find.byType(ImportIdentityDialog), findsNothing);
      
      // Verify in store
      final identities = await service.listIdentities();
      expect(identities, hasLength(1));
      expect(identities.first.displayName, equals('My Imported Key'));
    });

    testWidgets('should show error for invalid key', (WidgetTester tester) async {
      await store.setSentinel('vault_exists');
      await service.init();
      await service.unlock('1234');
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final controller = ProviderScope.containerOf(tester.element(find.byType(ImportIdentityDialog))).read(vaultControllerProvider.notifier);
      await controller.unlock('1234');
      await tester.pumpAndSettle();

      await tester.tap(find.text('I Understand'));
      await tester.pumpAndSettle();

      // Enter something that isn't 64 hex chars
      await tester.enterText(find.byType(TextField).first, 'abc123');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Confirm & Import'));
      await tester.pump(); // Start the async operation
      await tester.pumpAndSettle(); 

      expect(find.textContaining('Invalid private key format'), findsOneWidget);
      expect(find.byType(ImportIdentityDialog), findsOneWidget);
    });

    testWidgets('should show error for duplicate key', (WidgetTester tester) async {
      await store.setSentinel('vault_exists');
      await service.init();
      await service.unlock('1234');
      final hexKey = '0000000000000000000000000000000000000000000000000000000000000001';
      await service.importIdentity(hexKey);
      
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final controller = ProviderScope.containerOf(tester.element(find.byType(ImportIdentityDialog))).read(vaultControllerProvider.notifier);
      await controller.unlock('1234');
      await tester.pumpAndSettle();

      await tester.tap(find.text('I Understand'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, hexKey);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Confirm & Import'));
      await tester.pump(); // Start the async operation
      await tester.pumpAndSettle(); 

      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('should allow toggling key visibility', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle(); // Wait for any initial microtasks

      await tester.tap(find.text('I Understand'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();

      final updatedTextField = tester.widget<TextField>(find.byType(TextField).first);
      expect(updatedTextField.obscureText, isFalse);
    });
  });
}
