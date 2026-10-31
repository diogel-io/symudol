import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

void main() {
  // Off Android (here, the test host) biometric unlock is unavailable; the
  // tile says so and can't be turned on (#23).
  testWidgets('biometric unlock is disabled where the phone cannot use it', (
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
    expect(find.text('Not available on this phone'), findsOneWidget);

    final biometricSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(biometricSwitch.value, isFalse);
    expect(biometricSwitch.onChanged, isNull);
  });

  // Nothing read the approval session duration, so the setting is gone (#33).
  testWidgets('no approval session duration setting is shown', (
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

    expect(find.text('Approval session duration'), findsNothing);
    expect(find.textContaining('Not currently used'), findsNothing);
    expect(
      find.textContaining(
        'They apply whenever the vault is unlocked',
      ),
      findsOneWidget,
    );
  });
}
