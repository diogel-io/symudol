import 'dart:async';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/foundation.dart';

/// Asks relays for one author's events of some kinds. A seam so the profile
/// lookup can be tested without a network (diogel-io/symudol#42).
abstract class ProfileRelayClient {
  /// The newest event of each of [kinds] by [author] that [relays] return,
  /// and which relays answered, waiting at most [timeout] once connected.
  /// Each relay learns [author] and the device's IP address.
  Future<RelayQueryResult> query({
    required List<int> kinds,
    required String author,
    required List<String> relays,
    Duration timeout,
  });
}

/// What a relay query returned.
class RelayQueryResult {
  const RelayQueryResult({this.events = const [], this.answered = const {}});

  /// The events returned, each of a requested kind by the requested author.
  final List<NostrEvent> events;

  /// The relays that sent everything they store (EOSE). A relay that could
  /// not be reached or never finished is not here.
  final Set<String> answered;
}

/// Queries relays through the shared [Nostr.instance].
class DartNostrProfileRelayClient implements ProfileRelayClient {
  @override
  Future<RelayQueryResult> query({
    required List<int> kinds,
    required String author,
    required List<String> relays,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final service = Nostr.instance.services.relays;
    bool connected(String relay) =>
        service.nostrRegistry.isRelayRegisteredAndConnectedSuccesfully(relay);

    // Connect first, so [timeout] counts from when the request is sent, not
    // from the start of a connection wait of up to 5 s per relay. dart_nostr
    // would otherwise hold the request until every listed relay has
    // connected or given up, then try the unreachable ones again.
    if (relays.any((relay) => !connected(relay))) {
      await service.init(relaysUrl: relays, ignoreConnectionException: true);
    }
    final reachable = relays.where(connected).toList();
    if (reachable.isEmpty) return const RelayQueryResult();

    final request = NostrRequest(
      filters: [
        for (final kind in kinds)
          NostrFilter(kinds: [kind], authors: [author], limit: 1),
      ],
    );

    final events = <NostrEvent>[];
    final completer = Completer<void>();
    final requested = reachable.toSet();
    final finished = <String>{};

    // Wait until every relay has sent everything it stores (EOSE), so a
    // slower relay holding a newer event is not cut off; [timeout] covers
    // relays that never finish.
    final subscription = service.startEventsSubscription(
      request: request,
      relays: reachable,
      onEose: (relay, _) {
        finished.add(relay);
        if (finished.containsAll(requested) && !completer.isCompleted) {
          completer.complete();
        }
      },
    );

    final streamSubscription = subscription.stream.listen((event) {
      // dart_nostr does not check what relays send, so drop any event that
      // does not match the request, or whose id or signature is wrong.
      if (!kinds.contains(event.kind) || event.pubkey != author) return;
      if (!isAuthentic(event)) return;
      events.add(event);
    });

    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    timeoutTimer.cancel();
    await streamSubscription.cancel();
    subscription.close();

    return RelayQueryResult(events: events, answered: {...finished});
  }

  /// Whether [event]'s id matches its content and its signature is valid.
  @visibleForTesting
  static bool isAuthentic(NostrEvent event) {
    final kind = event.kind;
    final createdAt = event.createdAt;
    if (kind == null || createdAt == null || event.id == null) return false;
    try {
      final expectedId = NostrEvent.getEventId(
        kind: kind,
        content: event.content ?? '',
        createdAt: createdAt,
        tags: event.tags ?? const [],
        pubkey: event.pubkey,
      );
      return expectedId == event.id && event.isVerified();
    } catch (_) {
      // A malformed key or signature.
      return false;
    }
  }
}
