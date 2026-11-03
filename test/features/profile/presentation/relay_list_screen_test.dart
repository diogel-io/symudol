import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/presentation/relay_list_screen.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_profile_relay_client.dart';
import '../../../fakes/fake_vault_store.dart';

/// The Relays screen asks before reaching relays, and before publishing
/// (diogel-io/symudol#88, #83).
void main() {
  const indexer = 'wss://purplepag.es';

  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeProfileRelayClient relays;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock('123456');
    relays = FakeProfileRelayClient();
  });

  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    final identity = controller.state.activeIdentity!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultServiceProvider.overrideWithValue(vault),
          vaultControllerProvider.overrideWith((ref) => controller),
          profileNetworkStoreProvider.overrideWithValue(
            FakeProfileNetworkStore(),
          ),
          relayProfileServiceProvider.overrideWithValue(
            RelayProfileService(client: relays),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RelayListScreen(identity: identity),
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

  void holdList(List<List<String>> tags) {
    relays.held[indexer] = [
      NostrEvent(
        id: 'kind10002',
        kind: 10002,
        content: '',
        sig: 'sig',
        pubkey: controller.state.activeIdentity!.publicKey,
        createdAt: DateTime.fromMillisecondsSinceEpoch(10000),
        tags: tags,
      ),
    ];
  }

  Future<void> load(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Load relays'));
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, String host, String label) {
    final row = find.ancestor(of: find.text(host), matching: find.byType(Card));
    return tester
        .widget<FilterChip>(
          find.descendant(
            of: row,
            matching: find.widgetWithText(FilterChip, label),
          ),
        )
        .selected;
  }

  testWidgets('opening asks before reaching any relay', (tester) async {
    await openScreen(tester);

    expect(find.text('Load relays from the network?'), findsOneWidget);
    expect(find.textContaining('purplepag.es'), findsOneWidget);
    expect(relays.queries, isEmpty);
  });

  testWidgets('cancelling closes the screen and fetches nothing', (
    tester,
  ) async {
    await openScreen(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(RelayListScreen), findsNothing);
    expect(relays.queries, isEmpty);
  });

  testWidgets('the list shows each relay and its markers', (tester) async {
    holdList([
      ['r', 'wss://a.example.com'],
      ['r', 'wss://b.example.com', 'read'],
    ]);
    await openScreen(tester);
    await load(tester);

    expect(selected(tester, 'a.example.com', 'Read'), isTrue);
    expect(selected(tester, 'a.example.com', 'Write'), isTrue);
    expect(selected(tester, 'b.example.com', 'Read'), isTrue);
    expect(selected(tester, 'b.example.com', 'Write'), isFalse);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('a.example.com'),
          matching: find.byType(Card),
        ),
        matching: find.widgetWithText(FilterChip, 'Write'),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected(tester, 'a.example.com', 'Write'), isFalse);
  });

  testWidgets('an invalid relay address is refused with a message', (
    tester,
  ) async {
    holdList([
      ['r', 'wss://a.example.com'],
    ]);
    await openScreen(tester);
    await load(tester);

    await tester.enterText(
      find.byKey(const Key('relayListAddField')),
      'https://a.example.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text("That isn't a relay address (wss://…)."), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('relayListAddField')),
      'b.example.com',
    );
    await tester.tap(find.byTooltip('Add relay'));
    await tester.pumpAndSettle();

    expect(find.text('b.example.com'), findsOneWidget);
    expect(find.text("That isn't a relay address (wss://…)."), findsNothing);
  });

  testWidgets('saving names the relays, then shows how each answered', (
    tester,
  ) async {
    holdList([
      ['r', 'wss://a.example.com'],
    ]);
    await openScreen(tester);
    await load(tester);
    await tester.tap(find.byTooltip('Remove a.example.com'));
    await tester.enterText(
      find.byKey(const Key('relayListAddField')),
      'b.example.com',
    );
    await tester.tap(find.byTooltip('Add relay'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sign and publish?'), findsOneWidget);
    expect(find.text('a.example.com'), findsWidgets);
    expect(relays.published, isEmpty);

    await tester.tap(find.text('Sign and publish'));
    await tester.pumpAndSettle();

    expect(find.text('Relays published'), findsOneWidget);
    expect(relays.published.single.event.tags, [
      ['r', 'wss://b.example.com'],
    ]);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    holdList([
      ['r', 'wss://a.example.com'],
    ]);
    await openScreen(tester);
    await load(tester);
    await tester.tap(find.byTooltip('Remove a.example.com'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(RelayListScreen), findsNothing);
  });
}
