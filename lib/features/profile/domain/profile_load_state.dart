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
  const ProfileLoaded(this._profile);

  final NostrProfile? _profile;

  @override
  NostrProfile? get profile => _profile;
}

class ProfileLoadFailed extends ProfileLoadState {
  const ProfileLoadFailed();
}
