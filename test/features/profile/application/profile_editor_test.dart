import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/application/profile_editor.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/profile_relay_client.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/domain/profile_load_state.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_relay_client.dart';
import '../../../fakes/fake_vault_store.dart';

/// Saving merges into the newest profile, signs with the active identity and
/// publishes; it refuses when that could drop fields (diogel-io/symudol#41).
void main() {
  const indexer = 'wss://purplepag.es';
  const own = 'wss://own.example.com';

  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeProfileRelayClient relays;
  late ProviderContainer container;
  late String pubkey;
  late ProviderSubscription<ProfileEditorState> screen;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
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
      ],
    );
    addTearDown(container.dispose);
    screen = container.listen(profileEditorProvider(pubkey), (_, _) {});
  });

  NostrEvent profileEvent(Map<String, Object?> content, int createdAt) =>
      NostrEvent(
        id: 'kind0-$createdAt',
        kind: 0,
        content: jsonEncode(content),
        sig: 'sig',
        pubkey: pubkey,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
        tags: const [],
      );

  ProfileEditorNotifier editor() =>
      container.read(profileEditorProvider(pubkey).notifier);
  ProfileEditorState state() => container.read(profileEditorProvider(pubkey));

  test('loading fills the form from the newest profile', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'about': 'hi'}, 10),
    ];

    await editor().load();

    expect(state().phase, ProfileEditorPhase.editing);
    expect(state().form['name'], 'alice');
    expect(state().form['about'], 'hi');
    expect(state().dirty, isFalse);
  });

  test('saving keeps fields another app set since loading', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'about': 'old'}, 10),
    ];
    await editor().load();
    editor().updateForm(state().form.withText('about', 'new'));
    // Another app adds a field after the form was loaded.
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'about': 'old', 'lud06': 'lnurl1'}, 20),
    ];

    await editor().save();

    final event = relays.published.single.event;
    expect(jsonDecode(event.content), {
      'name': 'alice',
      'about': 'new',
      'lud06': 'lnurl1',
    });
  });

  test('the event is kind 0, signed by the active identity, and newer than '
      'the one it replaces', () async {
    final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, future),
    ];
    await editor().load();

    await editor().save();

    final event = relays.published.single.event;
    expect(event.kind, 0);
    expect(event.pubkey, pubkey);
    expect(event.tags, isEmpty);
    expect(event.createdAt, future + 1);
    expect(DartNostrCryptoService().verifySignedEvent(event), isTrue);
  });

  test(
    'it publishes to the identity\'s write relays plus the defaults',
    () async {
      relays.held[indexer] = [
        NostrEvent(
          id: 'list',
          kind: 10002,
          content: '',
          sig: 'sig',
          pubkey: pubkey,
          createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
          tags: const [
            ['r', own],
          ],
        ),
        profileEvent({'name': 'alice'}, 10),
      ];
      await editor().load();

      final results = await editor().save();

      expect(relays.published.single.relays, [own, ...defaultProfileRelays]);
      expect(results.keys, [own, ...defaultProfileRelays]);
      expect(results.values.every((result) => result.accepted), isTrue);
    },
  );

  test('each relay\'s answer is reported', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    relays.publishAnswers['wss://nos.lol'] = const RelayPublishResult(
      RelayPublishStatus.rejected,
      'blocked: rate limited',
    );
    await editor().load();

    final results = await editor().save();

    expect(results['wss://nos.lol']!.status, RelayPublishStatus.rejected);
    expect(results['wss://nos.lol']!.message, 'blocked: rate limited');
    expect(results['wss://relay.damus.io']!.accepted, isTrue);
    expect(state().publishResults, results);
    expect(state().dirty, isFalse);
  });

  test('no relay answering refuses the save and signs nothing', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    await editor().load();
    relays.unreachable.addAll([
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(relays.published, isEmpty);
    expect(state().saveError, contains('No relay answered'));
  });

  test('no relay accepting is an error', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    for (final relay in defaultProfileRelays) {
      relays.publishAnswers[relay] = const RelayPublishResult(
        RelayPublishStatus.rejected,
      );
    }
    await editor().load();

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(state().saveError, contains('No relay accepted'));
    expect(state().dirty, isFalse);
  });

  test('a new profile needs confirmation before it is created', () async {
    await editor().load();
    expect(state().phase, ProfileEditorPhase.noProfile);
    expect(state().searchedRelays, [
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);

    editor().confirmCreate();
    editor().updateForm(state().form.withText('name', 'new'));
    await editor().save();

    expect(jsonDecode(relays.published.single.event.content), {'name': 'new'});
  });

  test('a save without confirmation never creates a profile', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    await editor().load();
    relays.held.clear();

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(relays.published, isEmpty);
  });

  test('a saved profile updates the identity\'s loaded profile', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'picture': 'https://a/1.png'}, 10),
    ];
    await editor().load();
    editor().updateForm(state().form.withText('picture', 'https://a/2.png'));

    await editor().save();

    final loaded = container.read(nostrProfileProvider(pubkey));
    expect(loaded, isA<ProfileLoaded>());
    expect(loaded.profile?.picture, 'https://a/2.png');
  });

  test('invalid fields stop the save', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    await editor().load();
    editor().updateForm(state().form.withText('website', 'example.com'));

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(state().fieldErrors.keys, ['website']);
    expect(relays.published, isEmpty);
  });

  test('a prepared save publishes to the relays the user confirmed', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    await editor().load();

    final prepared = await editor().prepareSave();
    final queriesBefore = relays.queries.length;
    await editor().save(prepared: prepared);

    expect(relays.queries.length, queriesBefore);
    expect(relays.published.single.relays, prepared.publishRelays);
  });

  test('preparing refuses when no relay answers', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    await editor().load();
    relays.unreachable.addAll([
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);

    await expectLater(
      editor().prepareSave(),
      throwsA(isA<ProfileSaveException>()),
    );
    expect(state().saving, isFalse);
  });

  test('an unexpected failure ends the save with a message', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    relays.publishError = StateError('socket closed');
    await editor().load();

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(state().saving, isFalse);
    expect(state().saveError, "Couldn't save the profile. Try again.");
  });

  test('a save finishes even if the editor screen closes', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'picture': 'https://a/1.png'}, 10),
    ];
    await editor().load();
    editor().updateForm(state().form.withText('picture', 'https://a/2.png'));
    final notifier = editor();
    relays.queryDelay = const Duration(milliseconds: 50);

    final saving = notifier.save();
    // The screen was the editor's only listener.
    screen.close();
    await saving;

    expect(relays.published, hasLength(1));
    expect(
      container.read(nostrProfileProvider(pubkey)).profile?.picture,
      'https://a/2.png',
    );
  });

  test('a locked vault fails cleanly', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    await editor().load();
    await vault.lock();

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(state().saveError, contains('locked'));
    expect(state().saving, isFalse);
    expect(relays.published, isEmpty);
  });
}
