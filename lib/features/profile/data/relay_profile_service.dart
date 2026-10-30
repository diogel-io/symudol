import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../domain/nostr_profile.dart';
import '../domain/profile_relays.dart';
import 'profile_relay_client.dart';

/// Finds an identity's profile metadata (NIP-01 kind 0) where it lives: on
/// the identity's own NIP-65 write relays, the default relays or the indexer
/// relays (diogel-io/symudol#42).
class RelayProfileService {
  RelayProfileService({ProfileRelayClient? client})
    : _client = client ?? DartNostrProfileRelayClient();

  final ProfileRelayClient _client;

  static const int _relayListKind = 10002;
  static const int _profileKind = 0;

  /// Looks up the most recent profile metadata for [pubkeyHex]. The default
  /// and indexer relays are asked for both the identity's relay list (kind
  /// 10002) and its profile (kind 0) at once; the list's write relays not
  /// already asked are then asked for the profile too.
  ///
  /// Throws [ProfileFetchException] when no relay answered or the profile
  /// cannot be read, so callers can tell a failure from no profile: a
  /// profile null result means every relay in
  /// [ProfileLookup.searchedRelays] answered without one.
  ///
  /// Each relay learns [pubkeyHex] and the device's IP address, so call this
  /// only when the user has asked (diogel-io/symudol#83).
  Future<ProfileLookup> fetchProfile(String pubkeyHex) async {
    try {
      final base = profileRelays(
        const [],
        defaultProfileRelays,
        defaultIndexerRelays,
      );
      final first = await _client.query(
        kinds: const [_profileKind, _relayListKind],
        author: pubkeyHex,
        relays: base,
      );
      final own = writeRelays(
        _newest(first.events, _relayListKind, pubkeyHex)?.tags,
      );
      final events = [...first.events];
      final answered = {...first.answered};

      final unasked = own.where((relay) => !base.contains(relay)).toList();
      if (unasked.isNotEmpty) {
        try {
          final second = await _client.query(
            kinds: const [_profileKind],
            author: pubkeyHex,
            relays: unasked,
          );
          events.addAll(second.events);
          answered.addAll(second.answered);
        } catch (_) {
          // The identity's own relays could not be asked; what the defaults
          // and indexers returned still stands.
        }
      }

      if (answered.isEmpty) {
        throw StateError('No relay answered');
      }

      final content = _newest(events, _profileKind, pubkeyHex)?.content;
      final profile = content == null || content.isEmpty
          ? null
          : NostrProfile.fromJson(jsonDecode(content) as Map<String, dynamic>);
      return ProfileLookup(
        profile: profile,
        searchedRelays: profileRelays(
          own,
          defaultProfileRelays,
          defaultIndexerRelays,
        ).where(answered.contains).toList(),
        publishRelays: profileRelays(own, defaultProfileRelays),
      );
    } catch (error) {
      throw ProfileFetchException(error);
    }
  }

  /// The most recent of [events] of [kind] signed by [pubkeyHex], or null. A
  /// relay can answer with any event, so the others are ignored.
  static NostrEvent? _newest(
    List<NostrEvent> events,
    int kind,
    String pubkeyHex,
  ) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    NostrEvent? newest;
    for (final event in events) {
      if (event.kind != kind || event.pubkey != pubkeyHex) continue;
      if (newest == null ||
          (event.createdAt ?? epoch).isAfter(newest.createdAt ?? epoch)) {
        newest = event;
      }
    }
    return newest;
  }
}

/// What a profile lookup found, and where.
class ProfileLookup {
  const ProfileLookup({
    this.profile,
    this.searchedRelays = const [],
    this.publishRelays = const [],
  });

  /// The newest profile found, or null when no relay held one.
  final NostrProfile? profile;

  /// Every relay that answered the profile query, the identity's own write
  /// relays first.
  final List<String> searchedRelays;

  /// Where a new or edited profile should be published: the identity's own
  /// write relays plus the defaults.
  final List<String> publishRelays;
}

/// The profile could not be fetched or read.
class ProfileFetchException implements Exception {
  const ProfileFetchException(this.cause);

  final Object cause;

  @override
  String toString() => 'ProfileFetchException: $cause';
}
