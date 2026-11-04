import 'package:symudol/features/settings/presentation/privacy_policy_link.dart';
import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';

// Settings links to Symudol's privacy policy on the website (#39).
void main() {
  Future<List<Uri>> pumpSettings(
    WidgetTester tester, {
    Future<bool> Function(Uri uri)? launch,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final launched = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(FakeVaultStore()),
          externalLinkLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return launch == null ? true : launch(uri);
          }),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return launched;
  }

  Future<void> tapPrivacyPolicy(WidgetTester tester) async {
    final tile = find.byKey(const Key('privacyPolicyTile'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Privacy policy tile', (tester) async {
    await pumpSettings(tester);

    expect(find.byKey(const Key('privacyPolicyTile')), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('opens the privacy policy on diogel.io', (tester) async {
    final launched = await pumpSettings(tester);

    await tapPrivacyPolicy(tester);

    expect(launched, [Uri.parse('https://diogel.io/privacy/symudol')]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('says where the policy is when no browser opens it', (
    tester,
  ) async {
    await pumpSettings(tester, launch: (_) async => false);

    await tapPrivacyPolicy(tester);

    expect(
      find.text(
        "Couldn't open a browser. The privacy policy is at "
        'diogel.io/privacy/symudol',
      ),
      findsOneWidget,
    );
  });

  testWidgets('says where the policy is when the launcher fails', (
    tester,
  ) async {
    await pumpSettings(tester, launch: (_) async => throw Exception('none'));

    await tapPrivacyPolicy(tester);

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
