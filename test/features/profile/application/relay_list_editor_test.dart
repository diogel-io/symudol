import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/application/relay_list_editor.dart';
import 'package:symudol/features/profile/data/profile_relay_client.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';
import 'package:symudol/features/profile/domain/relay_list.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_profile_relay_client.dart';
import '../../../fakes/fake_vault_store.dart';

/// Saving applies the user's changes to the newest relay list, signs it with
/// the active identity and publishes it; it refuses when that could
/// overwrite a list it never read (diogel-io/symudol#88).
void main() {
  const indexer = 'wss://purplepag.es';
  const a = 'wss://a.example.com';
  const b = 'wss://b.example.com';
  const c = 'wss://c.example.com';

  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeProfileRelayClient relays;
  late ProviderContainer container;
  late String pubkey;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
    await vault.createIdentity(displayName: 'Account 2');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock('123456');
    pubkey = controller.state.activeIdentity!.publicKey;

    relays = FakeProfileRelayClient();
    container = ProviderContainer(
      overrides: [
        vaultServiceProvider.overrideWithValue(vault),
        vaultControllerProvider.overrideWith((ref) => controller),
        relayProfileServiceProvider.overrideWithValue(
          RelayProfileService(client: relays),
        ),
        profileNetworkStoreProvider.overrideWithValue(
          FakeProfileNetworkStore(ProfileNetworkSettings.defaults()),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  NostrEvent relayList(String author, List<List<String>> tags, int createdAt) =>
      NostrEvent(
        id: 'kind10002-$author-$createdAt',
        kind: 10002,
        content: '',
        sig: 'sig',
        pubkey: author,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
        tags: tags,
      );

  void hold(List<List<String>> tags, [int createdAt = 10]) {
    relays.held[indexer] = [relayList(pubkey, tags, createdAt)];
  }

  RelayListEditorNotifier editor([String? key]) {
    final id = key ?? pubkey;
    container.listen(relayListEditorProvider(id), (_, _) {});
    return container.read(relayListEditorProvider(id).notifier);
  }

  RelayListEditorState state([String? key]) =>
      container.read(relayListEditorProvider(key ?? pubkey));

  test('loading shows the relays and their markers', () async {
    hold([
      ['r', a],
      ['r', b, 'read'],
      ['r', c, 'write'],
    ]);

    await editor().load();

    expect(state().phase, RelayListEditorPhase.editing);
    expect(state().relays, const [
      RelayListEntry(a),
      RelayListEntry(b, write: false),
      RelayListEntry(c, read: false),
    ]);
    expect(state().dirty, isFalse);
  });

  test('no list is told apart from no answer', () async {
    await editor().load();
    expect(state().phase, RelayListEditorPhase.noList);

    relays.unreachable.addAll([
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);
    await editor().load();
    expect(state().phase, RelayListEditorPhase.loadFailed);
  });

  test('adding, editing and removing then saving publishes a list signed by '
      'the account', () async {
    hold([
      ['r', a],
      ['r', b],
      ['alt', 'kept'],
    ]);
    await editor().load();

    expect(editor().add('c.example.com'), isTrue);
    editor().setMarkers(a, write: false);
    editor().remove(b);
    final results = await editor().save();

    final published = relays.published.single;
    final event = published.event;
    expect(event.kind, 10002);
    expect(event.pubkey, pubkey);
    expect(NostrKeyPairs.verify(event.pubkey, event.id, event.sig), isTrue);
    expect(event.content, '');
    expect(event.tags, [
      ['r', a, 'read'],
      ['r', c],
      ['alt', 'kept'],
    ]);
    expect(event.createdAt, greaterThan(10));
    // Published to the old and new write relays, and the indexers.
    expect(published.relays, containsAll([a, b, c, indexer]));
    expect(results.values.every((result) => result.accepted), isTrue);
    expect(state().publishResults, results);
    expect(state().dirty, isFalse);
  });

  test('an invalid or duplicate relay is not added', () async {
    hold([
      ['r', a],
    ]);
    await editor().load();

    expect(editor().add('https://a.example.com'), isFalse);
    expect(state().inputError, "That isn't a relay address (wss://…).");
    expect(editor().add('A.example.com/'), isFalse);
    expect(state().inputError, 'That relay is already listed.');
    expect(state().relays, const [RelayListEntry(a)]);

    expect(editor().add(b), isTrue);
    expect(state().inputError, isNull);
  });

  test('a relay can\'t be marked neither read nor write', () async {
    hold([
      ['r', a, 'read'],
    ]);
    await editor().load();

    editor().setMarkers(a, read: false);

    expect(state().relays, const [RelayListEntry(a, write: false)]);
  });

  test(
    'saving with no relay answering is refused and publishes nothing',
    () async {
      hold([
        ['r', a],
      ]);
      await editor().load();
      editor().add(b);
      relays.unreachable.addAll([
        ...defaultProfileRelays,
        ...defaultIndexerRelays,
      ]);

      await expectLater(
        editor().save(),
        throwsA(
          isA<RelayListSaveException>().having(
            (e) => e.message,
            'message',
            contains('No relay answered'),
          ),
        ),
      );
      expect(relays.published, isEmpty);
      expect(state().saveError, contains('No relay answered'));
      // The edits are kept to try again.
      expect(state().relays, hasLength(2));
    },
  );

  test('a list another app removed since loading is not overwritten', () async {
    hold([
      ['r', a],
    ]);
    await editor().load();
    editor().add(b);
    relays.held[indexer] = [];

    await expectLater(editor().save(), throwsA(isA<RelayListSaveException>()));
    expect(relays.published, isEmpty);
  });

  test('no relay accepting is a failure', () async {
    hold([
      ['r', a],
    ]);
    await editor().load();
    editor().add(b);
    final targets = await container
        .read(relayProfileServiceProvider)
        .relayListPublishRelays(
          const [RelayListEntry(a)],
          const [RelayListEntry(a), RelayListEntry(b)],
        );
    for (final relay in targets) {
      relays.publishAnswers[relay] = const RelayPublishResult(
        RelayPublishStatus.rejected,
        'blocked',
      );
    }

    await expectLater(
      editor().save(),
      throwsA(
        isA<RelayListSaveException>().having(
          (e) => e.message,
          'message',
          contains('No relay accepted'),
        ),
      ),
    );
    expect(state().dirty, isTrue);
  });

  test('an empty list is refused', () async {
    hold([
      ['r', a],
    ]);
    await editor().load();
    editor().remove(a);

    await expectLater(editor().save(), throwsA(isA<RelayListSaveException>()));
    expect(relays.published, isEmpty);
    expect(relays.queries, hasLength(1));
  });

  test('creating a list needs confirming first', () async {
    await editor().load();
    expect(state().phase, RelayListEditorPhase.noList);

    editor().confirmCreate();
    editor().add(a);
    await editor().save();

    expect(relays.published.single.event.tags, [
      ['r', a],
    ]);
  });

  test(
    'changes are applied to a list another app changed since loading',
    () async {
      hold([
        ['r', a],
        ['r', b],
      ]);
      await editor().load();
      editor().remove(b);
      hold([
        ['r', a, 'write'],
        ['r', b],
        ['r', c],
      ], 20);

      await editor().save();

      expect(relays.published.single.event.tags, [
        ['r', a, 'write'],
        ['r', c],
      ]);
      expect(relays.published.single.event.createdAt, greaterThan(20));
    },
  );

  test('a list dated a second ahead is replaced by a later one', () async {
    final ahead = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
    hold([
      ['r', a],
    ], ahead);
    await editor().load();
    editor().add(b);

    await editor().save();

    expect(relays.published.single.event.createdAt, ahead + 1);
  });

  test('an identity that is not active can\'t save', () async {
    final other = controller.state.identities
        .firstWhere((identity) => !identity.isActive)
        .publicKey;
    relays.held[indexer] = [
      relayList(other, [
        ['r', a],
      ], 10),
    ];
    await editor(other).load();
    editor(other).add(b);

    await expectLater(
      editor(other).save(),
      throwsA(
        isA<RelayListSaveException>().having(
          (e) => e.message,
          'message',
          contains('no longer the active one'),
        ),
      ),
    );
    expect(relays.published, isEmpty);
  });

  test('each account has its own list', () async {
    final other = controller.state.identities
        .firstWhere((identity) => !identity.isActive)
        .publicKey;
    relays.held[indexer] = [
      relayList(pubkey, [
        ['r', a],
      ], 10),
      relayList(other, [
        ['r', b],
      ], 10),
    ];

    await editor().load();
    await editor(other).load();

    expect(state().relays, const [RelayListEntry(a)]);
    expect(state(other).relays, const [RelayListEntry(b)]);
  });
}
