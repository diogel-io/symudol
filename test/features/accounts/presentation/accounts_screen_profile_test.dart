import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/accounts/presentation/accounts_screen.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/domain/nostr_profile.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_relay_profile_service.dart';
import '../../../fakes/fake_vault_store.dart';

/// Profiles are fetched only when the user asks (diogel-io/symudol#83).
void main() {
  late VaultServiceImpl service;
  late VaultController controller;
  late FakeRelayProfileService profiles;

  setUp(() async {
    service = VaultServiceImpl(FakeVaultStore());
    await service.createVault('1234');
    await service.createIdentity(displayName: 'Account 1');
    await service.createIdentity(displayName: 'Account 2');
    controller = VaultController(service);
    await controller.initialize();
    await controller.unlock('1234');
    profiles = FakeRelayProfileService();
  });

  Future<void> pumpAccounts(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vaultServiceProvider.overrideWithValue(service),
        vaultControllerProvider.overrideWith((ref) => controller),
        relayProfileServiceProvider.overrideWithValue(profiles),
      ],
      child: const MaterialApp(home: AccountsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('opening the Accounts screen fetches no profile', (tester) async {
    await pumpAccounts(tester);

    expect(find.byTooltip('Load profile'), findsNWidgets(2));
    expect(profiles.requested, isEmpty);
  });

  testWidgets('the confirmation names the relays and indexers', (tester) async {
    await pumpAccounts(tester);

    await tester.tap(find.byTooltip('Load profile').first);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
          'relay.damus.io, nos.lol, relay.primal.net, purplepag.es, '
          'profiles.nostr1.com, relay.nos.social, and the relays this '
          'identity lists as its own',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('IP address')),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the confirmation fetches nothing', (tester) async {
    await pumpAccounts(tester);

    await tester.tap(find.byTooltip('Load profile').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(profiles.requested, isEmpty);
  });

  testWidgets('confirming fetches only that identity', (tester) async {
    profiles.profile = const NostrProfile(name: 'one');
    await pumpAccounts(tester);
    final first = controller.state.identities.first.publicKey;

    await tester.tap(find.byTooltip('Load profile').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(profiles.requested, [first]);
    expect(find.text('Profile loaded'), findsOneWidget);
  });

  testWidgets('no profile and a failure are reported differently', (
    tester,
  ) async {
    await pumpAccounts(tester);

    await tester.tap(find.byTooltip('Load profile').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();
    expect(find.text('No profile found'), findsOneWidget);
    expect(find.text('relay.damus.io'), findsOneWidget);
    expect(find.text('purplepag.es'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    profiles.fail = true;

    await tester.tap(find.byTooltip('Load profile').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach the relays"), findsOneWidget);
  });
}
