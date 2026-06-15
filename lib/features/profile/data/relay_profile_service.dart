import 'dart:async';
import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../domain/nostr_profile.dart';

/// Fetches Nostr profile metadata (NIP-01 kind 0 events) from a set of relays.
class RelayProfileService {
  static const List<String> defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
  ];

  bool _relaysInitialized = false;

  Future<void> _ensureRelaysInitialized() async {
    if (_relaysInitialized) return;

    await Nostr.instance.services.relays.init(
      relaysUrl: defaultRelays,
      retryOnError: true,
      ignoreConnectionException: true,
    );

    _relaysInitialized = true;
  }

  /// Returns the most recent profile metadata for [pubkeyHex], or null if
  /// no relay responded with a kind 0 event in time.
  Future<NostrProfile?> fetchProfile(String pubkeyHex) async {
    try {
      await _ensureRelaysInitialized();

      final request = NostrRequest(
        filters: [
          NostrFilter(kinds: const [0], authors: [pubkeyHex], limit: 1),
        ],
      );

      final subscription =
          Nostr.instance.services.relays.startEventsSubscription(request: request);

      final events = <NostrEvent>[];
      final completer = Completer<void>();
      Timer? graceTimer;
      late final StreamSubscription<NostrEvent> streamSubscription;

      streamSubscription = subscription.stream.listen((event) {
        events.add(event);
        // Give other relays a brief moment to respond too, so we can pick
        // the most recent profile, then stop waiting.
        graceTimer ??= Timer(const Duration(milliseconds: 800), () {
          if (!completer.isCompleted) completer.complete();
        });
      });

      final timeoutTimer = Timer(const Duration(seconds: 8), () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
      graceTimer?.cancel();
      timeoutTimer.cancel();
      await streamSubscription.cancel();
      subscription.close();

      if (events.isEmpty) return null;

      events.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );

      final content = events.first.content;
      if (content == null || content.isEmpty) return null;

      return NostrProfile.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
