// An identity's own relay list, NIP-65 kind 10002 (diogel-io/symudol#88):
// where its events are read from and written to.

import 'package:flutter/foundation.dart';

import 'profile_relays.dart';

/// One relay of a NIP-65 list and how the identity uses it. A relay is
/// always marked read, write or both.
@immutable
class RelayListEntry {
  const RelayListEntry(this.url, {this.read = true, this.write = true})
    : assert(read || write);

  final String url;

  /// Where the identity reads mentions of itself.
  final bool read;

  /// Where the identity publishes its own events.
  final bool write;

  RelayListEntry copyWith({bool? read, bool? write}) =>
      RelayListEntry(url, read: read ?? this.read, write: write ?? this.write);

  @override
  bool operator ==(Object other) =>
      other is RelayListEntry &&
      other.url == url &&
      other.read == read &&
      other.write == write;

  @override
  int get hashCode => Object.hash(url, read, write);
}

/// The relays of a kind 10002's [tags], in their order: an `r` tag with no
/// marker is both read and write. URLs are normalised, and a relay listed
/// twice is kept once with both entries' markers. Every relay is kept, past
/// [maxOwnRelays] too, so a save never drops one the user can't see.
List<RelayListEntry> relayListFromTags(List<List<String>>? tags) {
  final entries = <String, RelayListEntry>{};
  for (final tag in tags ?? const <List<String>>[]) {
    if (tag.length < 2 || tag[0] != 'r') continue;
    final url = normaliseRelayUrl(tag[1]);
    if (url == null) continue;
    final marker = tag.length > 2 ? tag[2] : '';
    final read = marker != 'write';
    final write = marker != 'read';
    final existing = entries[url];
    entries[url] = existing == null
        ? RelayListEntry(url, read: read, write: write)
        : existing.copyWith(
            read: existing.read || read,
            write: existing.write || write,
          );
  }
  return entries.values.toList();
}

/// The tags of a kind 10002 listing [entries], followed by [otherTags]: the
/// tags other than `r` of the list it replaces, which are kept.
List<List<String>> relayListTags(
  List<RelayListEntry> entries, {
  List<List<String>> otherTags = const [],
}) => [
  for (final entry in entries)
    ['r', entry.url, if (!entry.write) 'read' else if (!entry.read) 'write'],
  ...otherTags,
];

/// The tags of [tags] that are not `r` tags.
List<List<String>> nonRelayTags(List<List<String>>? tags) => [
  for (final tag in tags ?? const <List<String>>[])
    if (tag.isEmpty || tag[0] != 'r') tag,
];

/// What the user typed as a relay address, normalised, or null when it is
/// not one. With no scheme, `wss://` is assumed. `ws://` sends everything in
/// the clear, so it is accepted only when [allowInsecure], as for
/// `nostrconnect://` relays (diogel-io/symudol#31).
String? parseRelayInput(String text, {bool allowInsecure = !kReleaseMode}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final withScheme = trimmed.contains('://') ? trimmed : 'wss://$trimmed';
  final url = normaliseRelayUrl(withScheme);
  if (url == null) return null;
  if (url.startsWith('ws://') && !allowInsecure) return null;
  return url;
}

/// [latest] with only the changes the user made from [loaded] to [edited]:
/// relays added, removed or marked differently. A relay the user left alone
/// keeps what [latest] says, so a save does not revert a change another app
/// made after the list was loaded.
List<RelayListEntry> applyRelayEdits(
  List<RelayListEntry> latest,
  List<RelayListEntry> loaded,
  List<RelayListEntry> edited,
) {
  final before = {for (final entry in loaded) entry.url: entry};
  final after = {for (final entry in edited) entry.url: entry};
  final result = <RelayListEntry>[];
  for (final entry in latest) {
    final was = before[entry.url];
    final now = after[entry.url];
    if (was != null && now == null) continue; // removed
    result.add(now != null && now != was ? now : entry);
  }
  final kept = {for (final entry in result) entry.url};
  for (final entry in edited) {
    // Added, or edited where another app had removed it.
    final changed = before[entry.url] != entry;
    if (!kept.contains(entry.url) && changed) result.add(entry);
  }
  return result;
}
