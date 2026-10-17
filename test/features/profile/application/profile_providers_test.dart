import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/domain/nostr_profile.dart';
import 'package:symudol/features/profile/domain/profile_load_state.dart';

import '../../../fakes/fake_relay_profile_service.dart';

void main() {
  final alice = 'a' * 64;
  final bob = 'b' * 64;

  late FakeRelayProfileService service;
  late ProviderContainer container;

  setUp(() {
    service = FakeRelayProfileService();
    container = ProviderContainer(
      overrides: [relayProfileServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
  });

  test('reading a profile does not fetch it', () {
    expect(container.read(nostrProfileProvider(alice)), isA<ProfileNotLoaded>());
    container.listen(nostrProfileProvider(bob), (_, _) {});

    expect(service.requested, isEmpty);
  });

  test('load fetches only the requested pubkey', () async {
    service.profile = const NostrProfile(name: 'alice', picture: 'https://x/a.png');
    container.read(nostrProfileProvider(bob));

    final result = await container.read(nostrProfileProvider(alice).notifier).load();

    expect(service.requested, [alice]);
    expect(result, isA<ProfileLoaded>());
    expect(container.read(nostrProfileProvider(alice)).profile?.name, 'alice');
    expect(container.read(nostrProfileProvider(bob)), isA<ProfileNotLoaded>());
  });

  test('a loaded profile is kept without fetching again', () async {
    service.profile = const NostrProfile(name: 'alice');
    await container.read(nostrProfileProvider(alice).notifier).load();
    container.read(nostrProfileProvider(alice));

    expect(service.requested, [alice]);
  });

  test('no profile on the relays is loaded, not failed', () async {
    final result = await container.read(nostrProfileProvider(alice).notifier).load();

    expect(result, isA<ProfileLoaded>());
    expect(result.profile, isNull);
  });

  test('a fetch failure is reported as failed', () async {
    service.fail = true;

    final result = await container.read(nostrProfileProvider(alice).notifier).load();

    expect(result, isA<ProfileLoadFailed>());
    expect(container.read(nostrProfileProvider(alice)), isA<ProfileLoadFailed>());
  });
}
