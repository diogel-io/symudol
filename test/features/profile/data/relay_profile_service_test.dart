import 'dart:async';
import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';

import '../../../fakes/fake_profile_relay_client.dart';

/// A profile is found on the identity's own relays, the defaults or an
/// indexer (diogel-io/symudol#42).
void main() {
  final alice = 'a' * 64;
  final mallory = 'f' * 64;
  const indexer = 'wss://purplepag.es';
  const own = 'wss://own.example.com';

  late FakeProfileRelayClient client;
  late RelayProfileService service;

  setUp(() {
    client = FakeProfileRelayClient();
    service = RelayProfileService(client: client);
  });

  test('a profile held only on an indexer is found', () async {
    client.held[indexer] = [_profile(alice, 'alice', 10)];

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile?.name, 'alice');
  });

  test(
    'the defaults and indexers are asked for the profile and list at once',
    () async {
      await service.fetchProfile(alice);

      expect(client.queries, hasLength(1));
      final first = client.queries.single;
      expect(first.kinds, [0, 10002, 10063]);
      expect(first.author, alice);
      expect(first.relays, [...defaultProfileRelays, ...defaultIndexerRelays]);
    },
  );

  test(
    'the identity\'s own write relays are then asked for the profile',
    () async {
      client.held[indexer] = [
        _relayList(alice, [own, 'wss://old.example.com'], 1),
        _relayList(alice, [own, 'wss://nos.lol'], 5),
      ];
      client.held[own] = [_profile(alice, 'own', 10)];

      final lookup = await service.fetchProfile(alice);

      final second = client.queries.last;
      expect(second.kinds, [0, 10063]);
      expect(second.relays, [own]);
      expect(lookup.profile?.name, 'own');
      expect(lookup.searchedRelays, [
        own,
        'wss://nos.lol',
        'wss://relay.damus.io',
        'wss://relay.primal.net',
        ...defaultIndexerRelays,
      ]);
      expect(lookup.publishRelays, [
        own,
        'wss://nos.lol',
        'wss://relay.damus.io',
        'wss://relay.primal.net',
      ]);
    },
  );

  test(
    'a list naming only relays already asked needs no second query',
    () async {
      client.held[indexer] = [
        _relayList(alice, ['wss://nos.lol'], 5),
      ];

      await service.fetchProfile(alice);

      expect(client.queries, hasLength(1));
    },
  );

  test('the newest profile wins across relays', () async {
    client.held['wss://nos.lol'] = [_profile(alice, 'older', 10)];
    client.held[indexer] = [_profile(alice, 'newer', 20)];
    client.held['wss://relay.damus.io'] = [_profile(alice, 'oldest', 5)];

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile?.name, 'newer');
  });

  test('events signed by another key are ignored', () async {
    client.held[indexer] = [
      _relayList(mallory, ['wss://mallory.example.com'], 30),
      _profile(mallory, 'mallory', 30),
      _profile(alice, 'alice', 10),
    ];

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile?.name, 'alice');
    expect(client.queries, hasLength(1));
  });

  test('an event of another kind is not taken for the profile', () async {
    client.held[indexer] = [
      _profile(alice, 'alice', 10),
      _event(alice, 1, 30, content: 'a newer note'),
    ];
    client.answerAnyKind = true;

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile?.name, 'alice');
  });

  test('no profile anywhere lists every relay that answered', () async {
    client.unreachable.add('wss://relay.nos.social');

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile, isNull);
    expect(lookup.searchedRelays, [
      ...defaultProfileRelays,
      'wss://purplepag.es',
      'wss://profiles.nostr1.com',
    ]);
    expect(lookup.publishRelays, defaultProfileRelays);
  });

  group('relays chosen in Settings (#45)', () {
    const chosen = 'wss://chosen.example.com';
    const chosenIndexer = 'wss://index.example.com';

    RelayProfileService withSettings(ProfileNetworkSettings settings) =>
        RelayProfileService(client: client, settings: () async => settings);

    test(
      'are asked, searched and published to instead of the defaults',
      () async {
        client.held[chosenIndexer] = [
          _relayList(alice, [own], 5),
        ];
        final service = withSettings(
          ProfileNetworkSettings.defaults().copyWith(
            profileRelays: [chosen],
            indexerRelays: [chosenIndexer],
          ),
        );

        final lookup = await service.fetchProfile(alice);

        expect(client.queries.first.relays, [chosen, chosenIndexer]);
        expect(client.queries.last.relays, [own]);
        expect(lookup.searchedRelays, [own, chosen, chosenIndexer]);
        expect(lookup.publishRelays, [own, chosen]);
      },
    );

    test('an empty indexer list asks the profile relays alone', () async {
      final service = withSettings(
        ProfileNetworkSettings.defaults().copyWith(
          profileRelays: [chosen],
          indexerRelays: [],
        ),
      );

      final lookup = await service.fetchProfile(alice);

      expect(client.queries.single.relays, [chosen]);
      expect(lookup.searchedRelays, [chosen]);
      expect(lookup.publishRelays, [chosen]);
    });

    test('a lookup waits for the settings before asking any relay', () async {
      final settings = Completer<ProfileNetworkSettings>();
      final service = RelayProfileService(
        client: client,
        settings: () => settings.future,
      );

      final lookup = service.fetchProfile(alice);
      await Future<void>.delayed(Duration.zero);
      expect(client.queries, isEmpty);

      settings.complete(
        ProfileNetworkSettings.defaults().copyWith(
          profileRelays: [chosen],
          indexerRelays: [],
        ),
      );
      await lookup;
      expect(client.queries.single.relays, [chosen]);
    });
  });

  group('the identity\'s Blossom servers (#43)', () {
    test('are read from its kind 10063 list, in order', () async {
      client.held[indexer] = [
        _serverList(alice, ['https://old.example'], 1),
        _serverList(alice, [
          'https://Media.Example/',
          'https://second.example',
        ], 5),
      ];

      final lookup = await service.fetchProfile(alice);

      expect(lookup.blossomServers, [
        'https://media.example',
        'https://second.example',
      ]);
    });

    test('drop entries that are not https', () async {
      client.held[indexer] = [
        _serverList(alice, ['http://plain.example', 'https://ok.example'], 1),
      ];

      final lookup = await service.fetchProfile(alice);

      expect(lookup.blossomServers, ['https://ok.example']);
    });

    test('are found on the identity\'s own relays', () async {
      client.held[indexer] = [
        _relayList(alice, [own], 1),
      ];
      client.held[own] = [
        _serverList(alice, ['https://own-media.example'], 2),
      ];

      final lookup = await service.fetchProfile(alice);

      expect(lookup.blossomServers, ['https://own-media.example']);
    });

    test('ignore a list signed by another key', () async {
      client.held[indexer] = [
        _serverList(mallory, ['https://evil.example'], 9),
      ];

      final lookup = await service.fetchProfile(alice);

      expect(lookup.blossomServers, isEmpty);
    });
  });

  test('no relay answering is a fetch failure, not no profile', () async {
    client.unreachable.addAll([
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);

    expect(service.fetchProfile(alice), throwsA(isA<ProfileFetchException>()));
  });

  test('unreachable own relays keep the profile from the others', () async {
    client.held[indexer] = [
      _relayList(alice, [own], 5),
      _profile(alice, 'alice', 10),
    ];
    client.unreachable.add(own);

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile?.name, 'alice');
    expect(lookup.searchedRelays, isNot(contains(own)));
    expect(lookup.publishRelays.first, own);
  });

  test(
    'a failed query on the own relays keeps the profile from the others',
    () async {
      client.held[indexer] = [
        _relayList(alice, [own], 5),
        _profile(alice, 'alice', 10),
      ];
      client.failRelays.add(own);

      final lookup = await service.fetchProfile(alice);

      expect(lookup.profile?.name, 'alice');
    },
  );

  test('a failed query on the defaults is a fetch failure', () async {
    client.failRelays.add('wss://relay.damus.io');

    expect(service.fetchProfile(alice), throwsA(isA<ProfileFetchException>()));
  });

  test(
    'the newest profile\'s raw content and time are returned (#41)',
    () async {
      client.held[indexer] = [
        _event(alice, 0, 10, content: jsonEncode({'name': 'old'})),
        _event(
          alice,
          0,
          20,
          content: jsonEncode({'name': 'alice', 'lud06': 'lnurl1', 'x': 1}),
        ),
      ];

      final lookup = await service.fetchProfile(alice);

      expect(lookup.content, {'name': 'alice', 'lud06': 'lnurl1', 'x': 1});
      expect(lookup.createdAt, DateTime.fromMillisecondsSinceEpoch(20000));
    },
  );

  test('no kind 0 anywhere has no content or time', () async {
    final lookup = await service.fetchProfile(alice);

    expect(lookup.content, isNull);
    expect(lookup.createdAt, isNull);
  });

  test('a field of the wrong type does not fail the lookup (#41)', () async {
    client.held[indexer] = [
      _event(alice, 0, 10, content: jsonEncode({'name': 42, 'about': 'hi'})),
    ];

    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile?.name, isNull);
    expect(lookup.profile?.about, 'hi');
    expect(lookup.content, {'name': 42, 'about': 'hi'});
  });

  test('content that is not a JSON object is a fetch failure', () async {
    client.held[indexer] = [_event(alice, 0, 10, content: '["a"]')];

    expect(service.fetchProfile(alice), throwsA(isA<ProfileFetchException>()));
  });

  test('an unreadable profile is a fetch failure', () async {
    client.held[indexer] = [_event(alice, 0, 10, content: 'not json')];

    expect(service.fetchProfile(alice), throwsA(isA<ProfileFetchException>()));
  });
}

NostrEvent _profile(String pubkey, String name, int createdAt) =>
    _event(pubkey, 0, createdAt, content: jsonEncode({'name': name}));

NostrEvent _relayList(String pubkey, List<String> relays, int createdAt) =>
    _event(
      pubkey,
      10002,
      createdAt,
      tags: [
        for (final relay in relays) ['r', relay],
      ],
    );

NostrEvent _serverList(String pubkey, List<String> servers, int createdAt) =>
    _event(
      pubkey,
      10063,
      createdAt,
      tags: [
        for (final server in servers) ['server', server],
      ],
    );

NostrEvent _event(
  String pubkey,
  int kind,
  int createdAt, {
  String content = '',
  List<List<String>> tags = const [],
}) {
  return NostrEvent(
    id: '$kind-$createdAt',
    kind: kind,
    content: content,
    sig: 'sig',
    pubkey: pubkey,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
    tags: tags,
  );
}
