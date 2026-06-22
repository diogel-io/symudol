import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/relay_profile_service.dart';
import '../domain/nostr_profile.dart';

/// Provider for the [RelayProfileService].
final relayProfileServiceProvider = Provider<RelayProfileService>((ref) {
  return RelayProfileService();
});

/// Fetches and caches the Nostr profile metadata for the given hex public
/// key. Cached for the provider container's lifetime — callers that need
/// fresher data (e.g. the Accounts/Requests screens, on each visit) must
/// explicitly `ref.invalidate(nostrProfileProvider(pubkeyHex))`.
final nostrProfileProvider =
    FutureProvider.family<NostrProfile?, String>((ref, pubkeyHex) async {
  final service = ref.watch(relayProfileServiceProvider);
  return service.fetchProfile(pubkeyHex);
});
