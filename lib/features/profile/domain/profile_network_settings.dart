import 'profile_relays.dart';

/// The Blossom server images are uploaded to when the identity lists none of
/// its own: Porwr's and Bancwr's default (diogel-io/symudol#45).
const String defaultBlossomServer = 'https://blossom.primal.net';

/// The app-wide relays a profile is read from and published to, and the
/// Blossom server images are uploaded to, as the user chose them in Settings
/// (diogel-io/symudol#45). An identity's own NIP-65 relays are added to these
/// at lookup time; they are not part of these settings.
class ProfileNetworkSettings {
  const ProfileNetworkSettings({
    required this.profileRelays,
    required this.indexerRelays,
    required this.blossomServer,
  });

  /// Symudol's built-in choices.
  factory ProfileNetworkSettings.defaults() => const ProfileNetworkSettings(
    profileRelays: defaultProfileRelays,
    indexerRelays: defaultIndexerRelays,
    blossomServer: defaultBlossomServer,
  );

  /// Settings read back from storage. A missing or unreadable field falls
  /// back to its default, and so does an empty profile relay list, because
  /// publishing needs at least one. An empty indexer list is kept: the user
  /// chose to have none.
  factory ProfileNetworkSettings.fromJson(Map<String, Object?> json) {
    final defaults = ProfileNetworkSettings.defaults();
    final profile = _relays(json['profileRelays']);
    final indexers = _relays(json['indexerRelays']);
    final blossom = json['blossomServer'];
    return ProfileNetworkSettings(
      profileRelays: profile == null || profile.isEmpty
          ? defaults.profileRelays
          : profile,
      indexerRelays: indexers ?? defaults.indexerRelays,
      blossomServer:
          (blossom is String ? normaliseBlossomUrl(blossom) : null) ??
          defaults.blossomServer,
    );
  }

  /// The relays every profile lookup asks, and every profile is published to.
  final List<String> profileRelays;

  /// The relays that index profiles and relay lists; asked on lookup only.
  final List<String> indexerRelays;

  /// Where images are uploaded when the identity lists no Blossom server of
  /// its own.
  final String blossomServer;

  Map<String, Object?> toJson() => {
    'profileRelays': profileRelays,
    'indexerRelays': indexerRelays,
    'blossomServer': blossomServer,
  };

  ProfileNetworkSettings copyWith({
    List<String>? profileRelays,
    List<String>? indexerRelays,
    String? blossomServer,
  }) => ProfileNetworkSettings(
    profileRelays: profileRelays ?? this.profileRelays,
    indexerRelays: indexerRelays ?? this.indexerRelays,
    blossomServer: blossomServer ?? this.blossomServer,
  );

  @override
  bool operator ==(Object other) =>
      other is ProfileNetworkSettings &&
      _sameList(other.profileRelays, profileRelays) &&
      _sameList(other.indexerRelays, indexerRelays) &&
      other.blossomServer == blossomServer;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(profileRelays),
    Object.hashAll(indexerRelays),
    blossomServer,
  );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [value]'s relay URLs, normalised, without duplicates and at most
  /// [maxOwnRelays], or null when [value] is not a list.
  static List<String>? _relays(Object? value) {
    if (value is! List) return null;
    return {
      ...value.whereType<String>().map(normaliseRelayUrl).whereType<String>(),
    }.take(maxOwnRelays).toList();
  }
}

/// [value] as a Blossom server URL with a lowercase host and no trailing
/// `/`, or null when it is not an `https://` URL without a query or fragment.
String? normaliseBlossomUrl(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final lower = uri.host.toLowerCase();
  final host = lower.contains(':') ? '[$lower]' : lower;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return 'https://$host$port$path';
}
