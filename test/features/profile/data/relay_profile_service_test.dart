import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/data/profile_relay_client.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';

/// A profile is found on the identity's own relays, the defaults or an
/// indexer (diogel-io/symudol#42).
void main() {
  final alice = 'a' * 64;
  final mallory = 'f' * 64;
  const indexer = 'wss://purplepag.es';
  const own = 'wss://own.example.com';

  late _FakeRelayClient client;
  late RelayProfileService service;

  setUp(() {
    client = _FakeRelayClient();
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
      expect(first.kinds, [0, 10002]);
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
      expect(second.kinds, [0]);
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

typedef _Query = ({List<int> kinds, String author, List<String> relays});

/// Answers each query with the matching events held on the relays asked.
class _FakeRelayClient implements ProfileRelayClient {
  /// The events each relay holds.
  final Map<String, List<NostrEvent>> held = {};

  /// Relays that never answer.
  final Set<String> unreachable = {};

  /// A query that includes any of these relays throws.
  final Set<String> failRelays = {};

  /// When true, answer with every held event whatever the kind asked for,
  /// as a misbehaving relay might.
  bool answerAnyKind = false;

  final List<_Query> queries = [];

  @override
  Future<RelayQueryResult> query({
    required List<int> kinds,
    required String author,
    required List<String> relays,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    queries.add((kinds: kinds, author: author, relays: relays));
    if (relays.any(failRelays.contains)) {
      throw StateError('relays unreachable');
    }
    final answering = relays.where((relay) => !unreachable.contains(relay));
    return RelayQueryResult(
      events: [
        for (final relay in answering)
          ...?held[relay]?.where(
            (event) => answerAnyKind || kinds.contains(event.kind),
          ),
      ],
      answered: answering.toSet(),
    );
  }
}
