import 'dart:async';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/foundation.dart';

import '../domain/profile_relays.dart';

/// Asks relays for one author's events of one kind. A seam so the profile
/// lookup can be tested without a network (diogel-io/symudol#42).
abstract class ProfileRelayClient {
  /// The events of [kind] by [author] that [relays] return within [timeout].
  /// Each relay learns [author] and the device's IP address.
  Future<List<NostrEvent>> query({
    required int kind,
    required String author,
    required List<String> relays,
    Duration timeout,
  });
}

/// Queries relays through the shared [Nostr.instance].
class DartNostrProfileRelayClient implements ProfileRelayClient {
  bool _relaysInitialized = false;

  Future<void> _ensureRelaysInitialized() async {
    if (_relaysInitialized) return;

    await Nostr.instance.services.relays.init(
      relaysUrl: defaultProfileRelays,
      retryOnError: true,
      ignoreConnectionException: true,
    );

    _relaysInitialized = true;
  }

  @override
  Future<List<NostrEvent>> query({
    required int kind,
    required String author,
    required List<String> relays,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _ensureRelaysInitialized();

    final request = NostrRequest(
      filters: [
        NostrFilter(kinds: [kind], authors: [author], limit: 1),
      ],
    );

    // dart_nostr connects to any relay in [relays] it has not seen yet, and
    // sends the request only to those relays.
    final subscription = Nostr.instance.services.relays.startEventsSubscription(
      request: request,
      relays: relays,
    );

    final events = <NostrEvent>[];
    final completer = Completer<void>();
    Timer? graceTimer;

    final streamSubscription = subscription.stream.listen((event) {
      // dart_nostr does not check what relays send, so drop any event whose
      // id or signature is wrong.
      if (!isAuthentic(event)) return;
      events.add(event);
      // Give other relays a brief moment to respond too, so we can pick
      // the most recent event, then stop waiting.
      graceTimer ??= Timer(const Duration(milliseconds: 800), () {
        if (!completer.isCompleted) completer.complete();
      });
    });

    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    graceTimer?.cancel();
    timeoutTimer.cancel();
    await streamSubscription.cancel();
    subscription.close();

    return events;
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
