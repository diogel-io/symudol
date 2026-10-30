import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/profile/domain/profile_network_store.dart';

/// Keeps the profile network settings in memory (diogel-io/symudol#45).
class FakeProfileNetworkStore implements ProfileNetworkStore {
  FakeProfileNetworkStore([ProfileNetworkSettings? settings])
    : settings = settings ?? ProfileNetworkSettings.defaults();

  /// What [read] returns; [write] replaces it.
  ProfileNetworkSettings settings;

  /// When true, [write] throws.
  bool failWrites = false;

  /// How many times the settings were read.
  int reads = 0;

  @override
  Future<ProfileNetworkSettings> read() async {
    reads++;
    return settings;
  }

  @override
  Future<void> write(ProfileNetworkSettings settings) async {
    if (failWrites) throw StateError('storage unavailable');
    this.settings = settings;
  }
}
