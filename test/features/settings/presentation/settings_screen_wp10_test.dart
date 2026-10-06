import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

void main() {
  test('formats approval session duration choices', () {
    expect(formatApprovalSessionDuration(0), 'Ask every time');
    expect(formatApprovalSessionDuration(1), '1 minute');
    expect(formatApprovalSessionDuration(5), '5 minutes');
  });

  testWidgets('biometric unlock is clearly disabled until implemented', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultStoreProvider.overrideWithValue(FakeVaultStore())],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Biometric Unlock'), findsOneWidget);
    expect(
      find.text('Not available yet — PIN unlock remains required'),
      findsOneWidget,
    );

    final biometricSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(biometricSwitch.value, isFalse);
    expect(biometricSwitch.onChanged, isNull);
  });

  testWidgets('approval session setting exposes explicit short choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultStoreProvider.overrideWithValue(FakeVaultStore())],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approval session duration'), findsOneWidget);
    expect(find.textContaining('Not currently used'), findsOneWidget);
    expect(
      find.textContaining(
        'They apply whenever the vault is unlocked',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Ask every time'), findsOneWidget);

    await tester.tap(find.text('Approval session duration'));
    await tester.pumpAndSettle();

    expect(find.text('Ask every time'), findsWidgets);
    expect(find.text('1 minute'), findsOneWidget);
    expect(find.text('5 minutes'), findsOneWidget);
    expect(find.text('15 minutes'), findsOneWidget);
  });
}
