import 'nostr_profile.dart';

/// Where a pubkey's profile metadata stands. Nothing is fetched until the
/// user asks, so every pubkey starts as [ProfileNotLoaded].
sealed class ProfileLoadState {
  const ProfileLoadState();

  /// The loaded profile, or null when none has been loaded or none exists.
  NostrProfile? get profile => null;
}

class ProfileNotLoaded extends ProfileLoadState {
  const ProfileNotLoaded();
}

class ProfileLoading extends ProfileLoadState {
  const ProfileLoading();
}

/// The relays answered. [profile] is null when they hold no kind 0 event
/// for the pubkey.
class ProfileLoaded extends ProfileLoadState {
  const ProfileLoaded(
    this._profile, {
    this.content,
    this.createdAt,
    this.searchedRelays = const [],
    this.publishRelays = const [],
    this.blossomServers = const [],
  });

  final NostrProfile? _profile;

  /// Every key of the newest kind 0's content; null when there was none
  /// (diogel-io/symudol#41).
  final Map<String, Object?>? content;

  /// When the newest kind 0 was created; null when there was none.
  final DateTime? createdAt;

  /// Every relay that answered the profile query (diogel-io/symudol#42).
  final List<String> searchedRelays;

  /// Where a new or edited profile should be published: the identity's own
  /// write relays plus the defaults.
  final List<String> publishRelays;

  /// The https Blossom servers the identity lists (kind 10063), in its order
  /// of preference (diogel-io/symudol#43).
  final List<String> blossomServers;

  @override
  NostrProfile? get profile => _profile;
}

class ProfileLoadFailed extends ProfileLoadState {
  const ProfileLoadFailed();
}
