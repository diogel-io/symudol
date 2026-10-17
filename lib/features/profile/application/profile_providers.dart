import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/relay_profile_service.dart';
import '../domain/profile_load_state.dart';

/// Provider for the [RelayProfileService].
final relayProfileServiceProvider = Provider<RelayProfileService>((ref) {
  return RelayProfileService();
});

/// Profile metadata for the given hex public key, fetched only when the user
/// asks (diogel-io/symudol#83). Watching this provider never makes a network
/// request: each relay queried learns the pubkey and the device's IP address,
/// so a fetch happens only through [NostrProfileNotifier.load]. A loaded
/// profile is kept in memory for the provider container's lifetime and never
/// persisted, so a cold start makes no request.
final nostrProfileProvider =
    NotifierProvider.family<NostrProfileNotifier, ProfileLoadState, String>(
  NostrProfileNotifier.new,
);

class NostrProfileNotifier extends Notifier<ProfileLoadState> {
  NostrProfileNotifier(this.pubkeyHex);

  final String pubkeyHex;

  @override
  ProfileLoadState build() => const ProfileNotLoaded();

  /// Fetches the profile for [pubkeyHex] alone. Call only after the user has
  /// asked and confirmed. Returns the resulting state.
  Future<ProfileLoadState> load() async {
    if (state is ProfileLoading) return state;
    state = const ProfileLoading();
    final service = ref.read(relayProfileServiceProvider);
    ProfileLoadState next;
    try {
      next = ProfileLoaded(await service.fetchProfile(pubkeyHex));
    } catch (_) {
      next = const ProfileLoadFailed();
    }
    if (ref.mounted) state = next;
    return next;
  }
}
