import 'profile_network_settings.dart';

/// Keeps the user's [ProfileNetworkSettings] (diogel-io/symudol#45).
abstract class ProfileNetworkStore {
  /// The saved settings, or the defaults when none are saved or they cannot
  /// be read.
  Future<ProfileNetworkSettings> read();

  Future<void> write(ProfileNetworkSettings settings);
}
