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

  /// How long to wait for the relay list before looking for the profile.
  static const Duration _relayListTimeout = Duration(seconds: 5);

  /// Looks up the most recent profile metadata for [pubkeyHex] in two passes:
  /// the identity's relay list (kind 10002) from the default and indexer
  /// relays, then its kind 0 from the list's write relays, the defaults and
  /// the indexers. Throws [ProfileFetchException] when the profile relays
  /// cannot be queried or the profile cannot be read, so callers can tell a
  /// failure from no profile. A relay list that cannot be fetched only means
  /// the identity's own relays are not searched.
  ///
  /// Each relay learns [pubkeyHex] and the device's IP address, so call this
  /// only when the user has asked (diogel-io/symudol#83).
  Future<ProfileLookup> fetchProfile(String pubkeyHex) async {
    List<String> own = const [];
    try {
      final lists = await _client.query(
        kind: _relayListKind,
        author: pubkeyHex,
        relays: profileRelays(
          const [],
          defaultProfileRelays,
          defaultIndexerRelays,
        ),
        timeout: _relayListTimeout,
      );
      own = writeRelays(_newest(lists, _relayListKind, pubkeyHex)?.tags);
    } catch (_) {
      // Search the defaults and indexers without the identity's own relays.
    }

    final searched = profileRelays(
      own,
      defaultProfileRelays,
      defaultIndexerRelays,
    );

    try {
      final events = await _client.query(
        kind: _profileKind,
        author: pubkeyHex,
        relays: searched,
      );
      final content = _newest(events, _profileKind, pubkeyHex)?.content;
      final profile = content == null || content.isEmpty
          ? null
          : NostrProfile.fromJson(jsonDecode(content) as Map<String, dynamic>);
      return ProfileLookup(
        profile: profile,
        searchedRelays: searched,
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

  /// Every relay asked for the profile.
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
