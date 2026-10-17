import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/domain/nostr_profile.dart';

/// Records every profile fetch instead of opening relay connections, so tests
/// can prove a fetch happens only when the user asks (diogel-io/symudol#83).
class FakeRelayProfileService extends RelayProfileService {
  FakeRelayProfileService({this.profile, this.fail = false});

  /// What every fetch returns.
  NostrProfile? profile;

  /// When true, every fetch throws [ProfileFetchException].
  bool fail;

  /// The pubkeys fetched, in order.
  final List<String> requested = [];

  @override
  Future<NostrProfile?> fetchProfile(String pubkeyHex) async {
    requested.add(pubkeyHex);
    if (fail) throw ProfileFetchException(StateError('relays unreachable'));
    return profile;
  }
}
