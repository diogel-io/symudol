import 'package:symudol/features/nip46/application/nip46_feature.dart';
import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

// Android 1.0 hides NIP-46 in release builds; debug and profile keep it (#26).
void main() {
  Future<void> pumpSettings(WidgetTester tester, {required bool nip46}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(FakeVaultStore()),
          nip46EnabledProvider.overrideWithValue(nip46),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('NIP-46 is shown outside release builds', () {
    // Tests run in debug mode, where kReleaseMode is false.
    expect(kNip46Enabled, isTrue);
  });

  testWidgets('shows the Remote Signer tile when NIP-46 is enabled', (
    tester,
  ) async {
    await pumpSettings(tester, nip46: true);

    expect(find.text('Remote Signer (NIP-46)'), findsOneWidget);
  });

  testWidgets('hides the Remote Signer tile when NIP-46 is disabled', (
    tester,
  ) async {
    await pumpSettings(tester, nip46: false);

    expect(find.text('Remote Signer (NIP-46)'), findsNothing);
    expect(find.textContaining('NIP-46'), findsNothing);
    // The neighbouring tiles are unaffected.
    expect(find.text('Trusted Nostr apps'), findsOneWidget);
    expect(find.text('Session security'), findsOneWidget);
  });
}
