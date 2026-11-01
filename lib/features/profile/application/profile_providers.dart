import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_state.dart';
import '../data/blossom_client.dart';
import '../data/profile_image_picker.dart';
import '../data/profile_relay_client.dart';
import '../data/relay_profile_service.dart';
import '../data/secure_storage_profile_network_store.dart';
import '../domain/profile_load_state.dart';
import '../domain/profile_network_settings.dart';
import '../domain/profile_network_store.dart';

/// Provider for the [RelayProfileService]. Every lookup waits for the saved
/// network settings, so a lookup right after launch can't ask a relay the
/// user removed (diogel-io/symudol#45).
final relayProfileServiceProvider = Provider<RelayProfileService>((ref) {
  return RelayProfileService(
    client: ref.watch(profileRelayClientProvider),
    settings: () => ref.read(profileNetworkSettingsProvider.future),
  );
});

/// The connection to the relays a profile is read from and published to.
final profileRelayClientProvider = Provider<ProfileRelayClient>((ref) {
  return DartNostrProfileRelayClient();
});

/// The Blossom server connection images are uploaded through
/// (diogel-io/symudol#43).
final blossomClientProvider = Provider<BlossomClient>((ref) {
  return BlossomClient();
});

/// The photo picker and camera profile images come from.
final profileImagePickerProvider = Provider<ProfileImagePicker>((ref) {
  return SystemProfileImagePicker();
});

/// Where the profile network settings are kept.
final profileNetworkStoreProvider = Provider<ProfileNetworkStore>((ref) {
  return SecureStorageProfileNetworkStore();
});

/// The relays and Blossom server the user chose in Settings
/// (diogel-io/symudol#45).
final profileNetworkSettingsProvider =
    AsyncNotifierProvider<
      ProfileNetworkSettingsNotifier,
      ProfileNetworkSettings
    >(ProfileNetworkSettingsNotifier.new);

class ProfileNetworkSettingsNotifier
    extends AsyncNotifier<ProfileNetworkSettings> {
  @override
  Future<ProfileNetworkSettings> build() {
    // A wipe deletes the saved settings with the vault; read them again so
    // the defaults apply at once.
    ref.listen(vaultStateProvider, (previous, next) {
      if (next is NoVault && previous is! NoVault) ref.invalidateSelf();
    });
    return ref.read(profileNetworkStoreProvider).read();
  }

  /// Saves [settings] and uses them for every lookup and publish from now on.
  Future<void> save(ProfileNetworkSettings settings) async {
    await ref.read(profileNetworkStoreProvider).write(settings);
    state = AsyncData(settings);
  }
}

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

  Future<ProfileLoadState>? _loading;

  /// Fetches the profile for [pubkeyHex] alone. Call only after the user has
  /// asked and confirmed. Returns the resulting state; a call while a fetch
  /// is running waits for that fetch rather than starting another.
  Future<ProfileLoadState> load() =>
      _loading ??= _fetch().whenComplete(() => _loading = null);

  Future<ProfileLoadState> _fetch() async {
    state = const ProfileLoading();
    final service = ref.read(relayProfileServiceProvider);
    ProfileLoadState next;
    try {
      final lookup = await service.fetchProfile(pubkeyHex);
      next = ProfileLoaded(
        lookup.profile,
        content: lookup.content,
        createdAt: lookup.createdAt,
        searchedRelays: lookup.searchedRelays,
        publishRelays: lookup.publishRelays,
        blossomServers: lookup.blossomServers,
      );
    } catch (_) {
      next = const ProfileLoadFailed();
    }
    if (ref.mounted) state = next;
    return next;
  }

  /// Records a profile this device has just published, so the avatar and
  /// name follow a save without fetching again (diogel-io/symudol#41).
  void published(ProfileLoaded profile) => state = profile;
}
