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

  /// When set, [read] waits for it before answering.
  Future<void>? hold;

  /// How many times the settings were read.
  int reads = 0;

  @override
  Future<ProfileNetworkSettings> read() async {
    reads++;
    await hold;
    return settings;
  }

  @override
  Future<void> write(ProfileNetworkSettings settings) async {
    if (failWrites) throw StateError('storage unavailable');
    this.settings = settings;
  }
}
