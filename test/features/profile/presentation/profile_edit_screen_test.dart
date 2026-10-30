import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/accounts/presentation/accounts_screen.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/presentation/profile_edit_screen.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_profile_relay_client.dart';
import '../../../fakes/fake_vault_store.dart';

/// The profile editor asks before reaching relays, before creating a profile
/// and before publishing (diogel-io/symudol#41, #83).
void main() {
  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeProfileRelayClient relays;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
    await vault.createIdentity(displayName: 'Account 2');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock('123456');
    relays = FakeProfileRelayClient();
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      vaultServiceProvider.overrideWithValue(vault),
      vaultControllerProvider.overrideWith((ref) => controller),
      profileNetworkStoreProvider.overrideWithValue(FakeProfileNetworkStore()),
      relayProfileServiceProvider.overrideWithValue(
        RelayProfileService(client: relays),
      ),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    final identity = controller.state.activeIdentity!;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileEditScreen(identity: identity),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void holdProfile(Map<String, Object?> content) {
    relays.held['wss://purplepag.es'] = [
      NostrEvent(
        id: 'kind0',
        kind: 0,
        content: jsonEncode(content),
        sig: 'sig',
        pubkey: controller.state.activeIdentity!.publicKey,
        createdAt: DateTime.fromMillisecondsSinceEpoch(10000),
        tags: const [],
      ),
    ];
  }

  testWidgets('opening asks before reaching any relay', (tester) async {
    await openEditor(tester);

    expect(find.text('Load profile from relays?'), findsOneWidget);
    expect(relays.queries, isEmpty);
  });

  testWidgets('cancelling closes the editor and fetches nothing', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(relays.queries, isEmpty);
  });

  testWidgets('no profile lists the relays and asks before creating one', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(find.text('No profile found'), findsOneWidget);
    expect(find.text('purplepag.es'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Create a new profile'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('saving names the relays, then shows how each answered', (
    tester,
  ) async {
    holdProfile({'name': 'alice'});
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'alice'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'About'), 'hello');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sign and publish?'), findsOneWidget);
    expect(find.text('relay.damus.io'), findsOneWidget);
    expect(relays.published, isEmpty);

    await tester.tap(find.text('Sign and publish'));
    await tester.pumpAndSettle();

    expect(find.text('Profile published'), findsOneWidget);
    expect(find.text('3 of 3 relays accepted it.'), findsOneWidget);
    expect(jsonDecode(relays.published.single.event.content), {
      'name': 'alice',
      'about': 'hello',
    });
  });

  testWidgets('images in the preview load only when asked', (tester) async {
    holdProfile({'name': 'alice', 'picture': 'https://example.com/a.png'});
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Show images'), findsOneWidget);
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    holdProfile({'name': 'alice'});
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'About'), 'hello');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsNothing);
  });

  testWidgets('only the active identity offers Edit profile', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(app(const AccountsScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit profile'), findsOneWidget);
    expect(find.byTooltip('Load profile'), findsNWidgets(2));
  });
}
