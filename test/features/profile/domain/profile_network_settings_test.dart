import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/domain/profile_network_settings.dart';
import 'package:symudol/features/profile/domain/profile_relays.dart';

/// The relays and Blossom server chosen in Settings (diogel-io/symudol#45).
void main() {
  group('ProfileNetworkSettings', () {
    test('the defaults are the built-in relays and server', () {
      final defaults = ProfileNetworkSettings.defaults();

      expect(defaults.profileRelays, defaultProfileRelays);
      expect(defaults.indexerRelays, defaultIndexerRelays);
      expect(defaults.blossomServer, 'https://blossom.primal.net');
    });

    test('a JSON round trip keeps every field', () {
      const settings = ProfileNetworkSettings(
        profileRelays: ['wss://one.example.com'],
        indexerRelays: [],
        blossomServer: 'https://media.example.com',
      );

      expect(ProfileNetworkSettings.fromJson(settings.toJson()), settings);
    });

    test('missing or wrongly typed fields fall back to their defaults', () {
      final defaults = ProfileNetworkSettings.defaults();

      expect(ProfileNetworkSettings.fromJson(const {}), defaults);
      expect(
        ProfileNetworkSettings.fromJson(const {
          'profileRelays': 'wss://one.example.com',
          'indexerRelays': 3,
          'blossomServer': ['https://media.example.com'],
        }),
        defaults,
      );
    });

    test('an empty profile list falls back, an empty indexer list is kept', () {
      final read = ProfileNetworkSettings.fromJson(const {
        'profileRelays': <String>[],
        'indexerRelays': <String>[],
      });

      expect(read.profileRelays, defaultProfileRelays);
      expect(read.indexerRelays, isEmpty);
    });

    test('stored relays are normalised, deduplicated and capped', () {
      final read = ProfileNetworkSettings.fromJson({
        'profileRelays': [
          'WSS://One.Example.com/',
          'wss://one.example.com',
          'https://not-a-relay.example.com',
          42,
          for (var i = 0; i < 10; i++) 'wss://r$i.example.com',
        ],
      });

      expect(read.profileRelays.first, 'wss://one.example.com');
      expect(read.profileRelays, hasLength(maxOwnRelays));
      expect(read.profileRelays, isNot(contains(startsWith('https'))));
    });

    test('an invalid stored Blossom server falls back to the default', () {
      final read = ProfileNetworkSettings.fromJson(const {
        'blossomServer': 'http://media.example.com',
      });

      expect(read.blossomServer, defaultBlossomServer);
    });
  });

  group('normaliseBlossomUrl', () {
    test('keeps an https server without its trailing slashes', () {
      expect(
        normaliseBlossomUrl(' https://Media.Example.com// '),
        'https://media.example.com',
      );
      expect(
        normaliseBlossomUrl('https://media.example.com:8443/blossom/'),
        'https://media.example.com:8443/blossom',
      );
    });

    test('refuses anything that is not a plain https address', () {
      for (final value in [
        null,
        '',
        'media.example.com',
        'http://media.example.com',
        'wss://media.example.com',
        'https://',
        'https://user@media.example.com',
        'https://media.example.com/?x=1',
        'https://media.example.com/#top',
      ]) {
        expect(normaliseBlossomUrl(value), isNull, reason: '$value');
      }
    });
  });
}
