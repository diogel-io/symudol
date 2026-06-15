import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/relay_profile_service.dart';
import '../domain/nostr_profile.dart';

/// Provider for the [RelayProfileService].
final relayProfileServiceProvider = Provider<RelayProfileService>((ref) {
  return RelayProfileService();
});

/// Fetches and caches the Nostr profile metadata for the given hex public key.
final nostrProfileProvider =
    FutureProvider.family<NostrProfile?, String>((ref, pubkeyHex) async {
  // Keep the result cached for the lifetime of the app so we don't re-fetch
  // from relays every time the avatar is rebuilt.
  ref.keepAlive();

  final service = ref.watch(relayProfileServiceProvider);
  return service.fetchProfile(pubkeyHex);
});
