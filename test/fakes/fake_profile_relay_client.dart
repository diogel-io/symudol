import 'package:dart_nostr/dart_nostr.dart';
import 'package:symudol/features/profile/data/profile_relay_client.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';

typedef ProfileRelayQuery = ({
  List<int> kinds,
  String author,
  List<String> relays,
});

/// Answers each query with the matching events held on the relays asked,
/// and records what is published (diogel-io/symudol#42, #41).
class FakeProfileRelayClient implements ProfileRelayClient {
  /// The events each relay holds.
  final Map<String, List<NostrEvent>> held = {};

  /// Relays that never answer.
  final Set<String> unreachable = {};

  /// A query that includes any of these relays throws.
  final Set<String> failRelays = {};

  /// When true, answer with every held event whatever the kind asked for,
  /// as a misbehaving relay might.
  bool answerAnyKind = false;

  final List<ProfileRelayQuery> queries = [];

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

  /// Every event published, in order.
  final List<({SignedNostrEvent event, List<String> relays})> published = [];

  /// How each relay answers a publish; a relay not listed accepts.
  final Map<String, RelayPublishResult> publishAnswers = {};

  @override
  Future<Map<String, RelayPublishResult>> publish({
    required SignedNostrEvent event,
    required List<String> relays,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    published.add((event: event, relays: relays));
    return {
      for (final relay in relays)
        relay: unreachable.contains(relay)
            ? const RelayPublishResult(RelayPublishStatus.noAnswer)
            : publishAnswers[relay] ??
                  const RelayPublishResult(RelayPublishStatus.accepted),
    };
  }
}
