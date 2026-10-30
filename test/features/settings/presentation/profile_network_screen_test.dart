import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/settings/presentation/profile_network_screen.dart';
import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_vault_store.dart';

/// The profile relays, indexers and Blossom server are chosen in Settings
/// (diogel-io/symudol#45).
void main() {
  late FakeProfileNetworkStore store;

  setUp(() => store = FakeProfileNetworkStore());

  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileNetworkStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileNetworkScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> addRelay(WidgetTester tester, String field, String url) async {
    await tester.enterText(find.byKey(Key(field)), url);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved relays and server', (tester) async {
    await openScreen(tester);

    for (final host in [
      'relay.damus.io',
      'nos.lol',
      'relay.primal.net',
      'purplepag.es',
      'profiles.nostr1.com',
      'relay.nos.social',
    ]) {
      expect(find.text(host), findsOneWidget);
    }
    expect(find.text('https://blossom.primal.net'), findsOneWidget);
  });

  testWidgets('adding and removing relays, then saving, stores them', (
    tester,
  ) async {
    await openScreen(tester);

    await addRelay(tester, 'addProfileRelayField', 'wss://One.Example.com/');
    await tester.tap(find.byTooltip('Remove relay.damus.io'));
    await tester.tap(find.byTooltip('Remove purplepag.es'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(store.settings.profileRelays, [
      'wss://nos.lol',
      'wss://relay.primal.net',
      'wss://one.example.com',
    ]);
    expect(store.settings.indexerRelays, [
      'wss://profiles.nostr1.com',
      'wss://relay.nos.social',
    ]);
    expect(find.text('Relay settings saved'), findsOneWidget);
  });

  testWidgets('an invalid or repeated relay is refused with a message', (
    tester,
  ) async {
    await openScreen(tester);

    await addRelay(tester, 'addIndexerRelayField', 'https://example.com');
    expect(
      find.text('Enter a relay address starting with ws:// or wss://'),
      findsOneWidget,
    );

    await addRelay(tester, 'addIndexerRelayField', 'wss://purplepag.es/');
    expect(find.text('That relay is already in the list'), findsOneWidget);
    expect(store.settings, ProfileNetworkSettings.defaults());
  });

  testWidgets('the last profile relay cannot be removed', (tester) async {
    store.settings = ProfileNetworkSettings.defaults().copyWith(
      profileRelays: ['wss://only.example.com'],
    );
    await openScreen(tester);

    final remove = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove_circle_outline).first,
    );
    expect(remove.onPressed, isNull);
    expect(
      find.byTooltip('At least one profile relay is needed'),
      findsOneWidget,
    );
  });

  testWidgets('every indexer can be removed', (tester) async {
    await openScreen(tester);

    for (final host in [
      'purplepag.es',
      'profiles.nostr1.com',
      'relay.nos.social',
    ]) {
      await tester.tap(find.byTooltip('Remove $host'));
      await tester.pumpAndSettle();
    }
    await save(tester);

    expect(store.settings.indexerRelays, isEmpty);
  });

  testWidgets('the Blossom server must be an https address', (tester) async {
    await openScreen(tester);

    await tester.enterText(
      find.byKey(const Key('blossomServerField')),
      'http://media.example.com',
    );
    await tester.pumpAndSettle();
    await save(tester);
    expect(
      find.text('Enter a server address starting with https://'),
      findsOneWidget,
    );
    expect(store.settings, ProfileNetworkSettings.defaults());

    await tester.enterText(
      find.byKey(const Key('blossomServerField')),
      'https://Media.Example.com/',
    );
    await tester.pumpAndSettle();
    await save(tester);
    expect(store.settings.blossomServer, 'https://media.example.com');
  });

  testWidgets('reset brings back the defaults, saved on Save', (tester) async {
    store.settings = const ProfileNetworkSettings(
      profileRelays: ['wss://one.example.com'],
      indexerRelays: [],
      blossomServer: 'https://media.example.com',
    );
    await openScreen(tester);

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(find.text('relay.damus.io'), findsOneWidget);
    expect(store.settings.profileRelays, ['wss://one.example.com']);

    await save(tester);
    expect(store.settings, ProfileNetworkSettings.defaults());
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await openScreen(tester);
    await tester.tap(find.byTooltip('Remove nos.lol'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(store.settings, ProfileNetworkSettings.defaults());
  });

  testWidgets('a failed save says so and keeps the changes', (tester) async {
    store.failWrites = true;
    await openScreen(tester);
    await tester.tap(find.byTooltip('Remove nos.lol'));
    await tester.pumpAndSettle();

    await save(tester);

    expect(find.text("Couldn't save the relay settings"), findsOneWidget);
    expect(find.text('nos.lol'), findsNothing);
  });

  testWidgets('Settings opens the screen from the Network section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(FakeVaultStore()),
          profileNetworkStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('profileNetworkTile'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileNetworkScreen), findsOneWidget);
    expect(find.text('PROFILE RELAYS'), findsOneWidget);
  });
}
