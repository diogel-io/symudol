// Which relays a profile is read from and published to (diogel-io/symudol#42).
// These follow Bancwr's rules (`frontend/app/utils/profile-relays.ts`): the
// identity's own NIP-65 write relays, then the defaults, then indexer relays.
// Indexers collect profiles and relay lists from across the network, so an
// identity whose profile is on none of its own or the default relays is
// found there.

/// The relays every profile lookup asks, and every profile is published to.
const List<String> defaultProfileRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
];

/// Relays that index profiles and relay lists. Each held kind 0 and kind
/// 10002 for the keys Bancwr probed on 2026-10-02; any one answering is
/// enough.
const List<String> defaultIndexerRelays = [
  'wss://purplepag.es',
  'wss://profiles.nostr1.com',
  'wss://relay.nos.social',
];

/// A bound on how many of an identity's own relays are used, so a huge list
/// cannot fan out.
const int maxOwnRelays = 8;

/// [value] as a relay URL with a lowercase scheme and host and no bare `/`
/// path, or null when it is not a `wss://` or `ws://` URL. Any other path is
/// kept as it is, trailing slash included, because a relay's path can select
/// its endpoint.
String? normaliseRelayUrl(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !(uri.scheme == 'wss' || uri.scheme == 'ws') ||
      uri.host.isEmpty) {
    return null;
  }
  final lower = uri.host.toLowerCase();
  // Uri.host drops an IPv6 literal's brackets; put them back.
  final host = lower.contains(':') ? '[$lower]' : lower;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path == '/' ? '' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '${uri.scheme}://$host$port$path$query';
}

/// The write relays of a NIP-65 list (kind 10002): `r` tags marked `write` or
/// not marked at all, without duplicates and at most [maxOwnRelays].
List<String> writeRelays(List<List<String>>? tags) {
  if (tags == null) return const [];
  final urls = tags
      .where(
        (tag) =>
            tag.length >= 2 &&
            tag[0] == 'r' &&
            (tag.length == 2 || tag[2] == 'write'),
      )
      .map((tag) => normaliseRelayUrl(tag[1]));
  return _unique(urls).take(maxOwnRelays).toList();
}

/// [own] first, then [defaults], then [others], normalised and without
/// duplicates.
List<String> profileRelays(
  List<String> own,
  List<String> defaults, [
  List<String> others = const [],
]) {
  return _unique([...own, ...defaults, ...others].map(normaliseRelayUrl));
}

/// [url] without its `wss://` scheme, for showing to the user.
String relayHost(String url) => url.replaceFirst(RegExp(r'^wss?://'), '');

List<String> _unique(Iterable<String?> urls) =>
    {...urls.whereType<String>()}.toList();
