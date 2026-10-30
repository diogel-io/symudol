import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';

/// Where a profile is read from and published to (diogel-io/symudol#42).
void main() {
  group('normaliseRelayUrl', () {
    test('lowercases the host and drops a bare trailing slash', () {
      expect(
        normaliseRelayUrl(' wss://Relay.Example.com/ '),
        'wss://relay.example.com',
      );
      expect(
        normaliseRelayUrl('ws://localhost:7777/inbox'),
        'ws://localhost:7777/inbox',
      );
    });

    test('keeps a trailing slash on a path, which can select the endpoint', () {
      expect(
        normaliseRelayUrl('wss://example.com/relay/'),
        'wss://example.com/relay/',
      );
    });

    test('keeps the brackets on an IPv6 host', () {
      expect(normaliseRelayUrl('ws://[::1]:7777'), 'ws://[::1]:7777');
      expect(normaliseRelayUrl('wss://[2001:DB8::1]/'), 'wss://[2001:db8::1]');
    });

    test('rejects anything that is not a websocket URL', () {
      expect(normaliseRelayUrl('https://relay.example.com'), isNull);
      expect(normaliseRelayUrl('relay.example.com'), isNull);
      expect(normaliseRelayUrl('wss://'), isNull);
      expect(normaliseRelayUrl(null), isNull);
    });
  });

  group('writeRelays', () {
    test('keeps write and unmarked relays, not read-only ones', () {
      final relays = writeRelays([
        ['r', 'wss://write.example.com', 'write'],
        ['r', 'wss://both.example.com'],
        ['r', 'wss://read.example.com', 'read'],
        ['p', 'wss://not-a-relay-tag.example.com'],
        ['r'],
        ['r', 'https://not-a-relay.example.com'],
      ]);

      expect(relays, ['wss://write.example.com', 'wss://both.example.com']);
    });

    test('drops duplicates and stops at $maxOwnRelays', () {
      final relays = writeRelays([
        ['r', 'wss://one.example.com/'],
        ['r', 'wss://ONE.example.com'],
        for (var i = 0; i < 12; i++) ['r', 'wss://r$i.example.com'],
      ]);

      expect(relays, hasLength(maxOwnRelays));
      expect(relays.first, 'wss://one.example.com');
      expect(relays.toSet(), hasLength(maxOwnRelays));
    });

    test('a missing list has no write relays', () {
      expect(writeRelays(null), isEmpty);
    });
  });

  test('profileRelays puts own relays first, without duplicates', () {
    final relays = profileRelays(
      ['wss://own.example.com', 'wss://nos.lol/'],
      defaultProfileRelays,
      defaultIndexerRelays,
    );

    expect(relays, [
      'wss://own.example.com',
      'wss://nos.lol',
      'wss://relay.damus.io',
      'wss://relay.primal.net',
      ...defaultIndexerRelays,
    ]);
  });

  test('relayHost drops the scheme', () {
    expect(relayHost('wss://purplepag.es'), 'purplepag.es');
    expect(relayHost('ws://localhost:7777'), 'localhost:7777');
  });
}
