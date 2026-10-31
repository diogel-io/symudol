import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:symudol/features/profile/application/profile_editor.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/blossom_client.dart';
import 'package:symudol/features/profile/data/profile_relay_client.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/domain/profile_image.dart';
import 'package:symudol/features/profile/domain/profile_load_state.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
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

  /// What the Blossom server received, and how it answers.
  late List<http.Request> uploads;
  late Future<http.Response> Function(http.Request request) blossom;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock('123456');
    pubkey = controller.state.activeIdentity!.publicKey;

    relays = FakeProfileRelayClient();
    uploads = [];
    blossom = (request) async => http.Response(
      jsonEncode({
        'url': 'https://cdn.example/${blobSha256(request.bodyBytes)}.jpg',
        'sha256': blobSha256(request.bodyBytes),
      }),
      200,
    );
    container = ProviderContainer(
      overrides: [
        vaultServiceProvider.overrideWithValue(vault),
        vaultControllerProvider.overrideWith((ref) => controller),
        relayProfileServiceProvider.overrideWithValue(
          RelayProfileService(client: relays),
        ),
        profileNetworkStoreProvider.overrideWithValue(
          FakeProfileNetworkStore(
            ProfileNetworkSettings.defaults().copyWith(
              blossomServer: 'https://settings.example',
            ),
          ),
        ),
        blossomClientProvider.overrideWithValue(
          BlossomClient(
            client: MockClient((request) {
              uploads.add(request);
              return blossom(request);
            }),
          ),
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

  test(
    'saving does not revert a field another app changed after loading',
    () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice', 'picture': 'https://a/old.png'}, 10),
      ];
      await editor().load();
      editor().updateForm(state().form.withText('about', 'new'));
      relays.held[indexer] = [
        profileEvent({'name': 'alice', 'picture': 'https://a/new.png'}, 20),
      ];

      await editor().save();

      expect(jsonDecode(relays.published.single.event.content), {
        'name': 'alice',
        'picture': 'https://a/new.png',
        'about': 'new',
      });
    },
  );

  test('the event is kind 0, signed by the active identity, and newer than '
      'the one it replaces', () async {
    final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
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

  test(
    'preparing shows what will be signed, keeping the user\'s edits',
    () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice', 'picture': 'https://a/old.png'}, 10),
      ];
      await editor().load();
      editor().updateForm(state().form.withText('about', 'new'));
      relays.held[indexer] = [
        profileEvent({'name': 'alice', 'picture': 'https://a/new.png'}, 20),
      ];

      final prepared = await editor().prepareSave();

      expect(state().form['picture'], 'https://a/new.png');
      expect(state().form['about'], 'new');
      expect(state().dirty, isTrue);

      await editor().save(prepared: prepared);

      expect(jsonDecode(relays.published.single.event.content), {
        'name': 'alice',
        'picture': 'https://a/new.png',
        'about': 'new',
      });
      expect(state().form['picture'], 'https://a/new.png');
      expect(state().dirty, isFalse);
    },
  );

  test('after a save the form holds what was published', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'website': 'https://a'}, 10),
    ];
    await editor().load();
    editor().updateForm(state().form.withText('name', 'Alice'));
    relays.held[indexer] = [
      profileEvent({'name': 'alice', 'website': 'https://b'}, 20),
    ];

    await editor().save();

    expect(state().form['name'], 'Alice');
    expect(state().form['website'], 'https://b');
  });

  test('loading while the profile is already loading waits for it', () async {
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, 10),
    ];
    relays.queryDelay = const Duration(milliseconds: 50);

    final first = container.read(nostrProfileProvider(pubkey).notifier).load();
    await editor().load();
    await first;

    expect(state().phase, ProfileEditorPhase.editing);
    expect(state().form['name'], 'alice');
    expect(relays.queries, hasLength(1));
  });

  test('a newest profile dated far ahead is refused, not outdated', () async {
    final ahead = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    relays.held[indexer] = [
      profileEvent({'name': 'alice'}, ahead),
    ];
    await editor().load();

    await expectLater(editor().save(), throwsA(isA<ProfileSaveException>()));

    expect(state().saveError, contains('ahead of this phone'));
    expect(relays.published, isEmpty);
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

  group('uploading an image (#43)', () {
    final photo = img.encodeJpg(
      img.Image(width: 64, height: 32)..clear(img.ColorRgb8(10, 20, 30)),
    );

    NostrEvent serverList(List<String> servers) => NostrEvent(
      id: 'kind10063',
      kind: 10063,
      content: '',
      sig: 'sig',
      pubkey: pubkey,
      createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
      tags: [
        for (final server in servers) ['server', server],
      ],
    );

    test('goes to the identity\'s own server when it lists one', () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice'}, 10),
        serverList(['https://own-media.example']),
      ];
      await editor().load();

      expect(await editor().uploadServer(), 'https://own-media.example');
    });

    test('goes to the Settings server otherwise', () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice'}, 10),
      ];
      await editor().load();

      expect(await editor().uploadServer(), 'https://settings.example');
    });

    test('uploads the re-encoded JPEG signed by the identity', () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice'}, 10),
      ];
      await editor().load();

      final url = await editor().uploadImage(
        ProfileImageKind.picture,
        photo,
        server: 'https://settings.example',
      );

      final request = uploads.single;
      final sha = blobSha256(request.bodyBytes);
      expect(url, 'https://cdn.example/$sha.jpg');
      expect(request.url.toString(), 'https://settings.example/upload');
      final auth = jsonDecode(
        utf8.decode(
          base64.decode(
            request.headers['Authorization']!.substring('Nostr '.length),
          ),
        ),
      );
      expect(auth['kind'], 24242);
      expect(auth['pubkey'], pubkey);
      expect(auth['tags'], contains(equals(['x', sha])));
      expect(state().uploading, isNull);
      // The screen fills the field; nothing is published.
      expect(relays.published, isEmpty);
    });

    test(
      'a server refusal is a message, and nothing is left running',
      () async {
        relays.held[indexer] = [
          profileEvent({'name': 'alice'}, 10),
        ];
        await editor().load();
        blossom = (_) async =>
            http.Response('', 401, headers: {'x-reason': 'Not allowed'});

        await expectLater(
          editor().uploadImage(
            ProfileImageKind.banner,
            photo,
            server: 'https://settings.example',
          ),
          throwsA(
            isA<ProfileUploadException>().having(
              (error) => error.message,
              'message',
              'settings.example refused the upload: Not allowed',
            ),
          ),
        );
        expect(state().uploading, isNull);
      },
    );

    test('an image it cannot read is a message, and nothing is sent', () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice'}, 10),
      ];
      await editor().load();

      await expectLater(
        editor().uploadImage(
          ProfileImageKind.picture,
          Uint8List.fromList([1, 2, 3]),
          server: 'https://settings.example',
        ),
        throwsA(isA<ProfileUploadException>()),
      );
      expect(uploads, isEmpty);
    });

    test('a locked vault signs nothing and sends nothing', () async {
      relays.held[indexer] = [
        profileEvent({'name': 'alice'}, 10),
      ];
      await editor().load();
      await vault.lock();

      await expectLater(
        editor().uploadImage(
          ProfileImageKind.picture,
          photo,
          server: 'https://settings.example',
        ),
        throwsA(
          isA<ProfileUploadException>().having(
            (error) => error.message,
            'message',
            contains('locked'),
          ),
        ),
      );
      expect(uploads, isEmpty);
    });
  });
}
