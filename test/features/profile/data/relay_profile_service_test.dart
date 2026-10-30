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

  test('the relay list is read from the defaults and indexers', () async {
    await service.fetchProfile(alice);

    final listQuery = client.queries.first;
    expect(listQuery.kind, 10002);
    expect(listQuery.author, alice);
    expect(listQuery.relays, [
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);
  });

  test(
    'the profile is searched for on the identity\'s write relays first',
    () async {
      client.held[indexer] = [
        _relayList(alice, [own, 'wss://old.example.com'], 1),
        _relayList(alice, [own], 5),
      ];
      client.held[own] = [_profile(alice, 'own', 10)];

      final lookup = await service.fetchProfile(alice);

      final profileQuery = client.queries.last;
      expect(profileQuery.kind, 0);
      expect(profileQuery.relays, [
        own,
        ...defaultProfileRelays,
        ...defaultIndexerRelays,
      ]);
      expect(lookup.profile?.name, 'own');
      expect(lookup.searchedRelays, profileQuery.relays);
      expect(lookup.publishRelays, [own, ...defaultProfileRelays]);
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
    expect(lookup.searchedRelays, isNot(contains('wss://mallory.example.com')));
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

  test('no profile anywhere reports every relay searched', () async {
    final lookup = await service.fetchProfile(alice);

    expect(lookup.profile, isNull);
    expect(lookup.searchedRelays, [
      ...defaultProfileRelays,
      ...defaultIndexerRelays,
    ]);
    expect(lookup.publishRelays, defaultProfileRelays);
  });

  test(
    'a failed relay list still searches the defaults and indexers',
    () async {
      client.failKinds.add(10002);
      client.held[indexer] = [_profile(alice, 'alice', 10)];

      final lookup = await service.fetchProfile(alice);

      expect(lookup.profile?.name, 'alice');
      expect(client.queries.last.relays, [
        ...defaultProfileRelays,
        ...defaultIndexerRelays,
      ]);
    },
  );

  test('a failed profile query is a fetch failure', () async {
    client.failKinds.add(0);

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

typedef _Query = ({int kind, String author, List<String> relays});

/// Answers each query with the matching events held on the relays asked.
class _FakeRelayClient implements ProfileRelayClient {
  /// The events each relay holds.
  final Map<String, List<NostrEvent>> held = {};

  /// Kinds whose queries throw.
  final Set<int> failKinds = {};

  /// When true, answer with every held event whatever the kind asked for,
  /// as a misbehaving relay might.
  bool answerAnyKind = false;

  final List<_Query> queries = [];

  @override
  Future<List<NostrEvent>> query({
    required int kind,
    required String author,
    required List<String> relays,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    queries.add((kind: kind, author: author, relays: relays));
    if (failKinds.contains(kind)) throw StateError('relays unreachable');
    return [
      for (final relay in relays)
        ...?held[relay]?.where((event) => answerAnyKind || event.kind == kind),
    ];
  }
}
