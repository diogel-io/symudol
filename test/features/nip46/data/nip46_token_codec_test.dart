import 'dart:typed_data';

import 'package:symudol/features/nip46/data/nip46_token_codec.dart';
import 'package:symudol/features/nip46/domain/nip46_connection_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validPubkey =
      'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1';

  group('generateBunkerToken', () {
    test('includes pubkey, relays, and hex secret', () {
      final token = Nip46TokenCodec.generateBunkerToken(
        remoteSignerPubkey: validPubkey,
        relays: ['wss://relay.example.com'],
        randomBytes: (n) => Uint8List(n)..fillRange(0, n, 0xab),
      );
      expect(token.remoteSignerPubkey, validPubkey);
      expect(token.relays, ['wss://relay.example.com']);
      expect(token.secret.length, 64); // 32 bytes → 64 hex chars
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token.secret), isTrue);
    });

    test('toUri includes all relay params', () {
      final token = Nip46TokenCodec.generateBunkerToken(
        remoteSignerPubkey: validPubkey,
        relays: ['wss://r1.example.com', 'wss://r2.example.com'],
        randomBytes: (n) => Uint8List(n)..fillRange(0, n, 0x01),
      );
      final uri = token.toUri();
      expect(uri, startsWith('bunker://$validPubkey?'));
      expect(uri, contains('relay='));
      expect(uri, contains(Uri.encodeComponent('wss://r1.example.com')));
      expect(uri, contains(Uri.encodeComponent('wss://r2.example.com')));
      expect(uri, contains('secret='));
    });

    test('throws when no relays supplied', () {
      expect(
        () => Nip46TokenCodec.generateBunkerToken(
          remoteSignerPubkey: validPubkey,
          relays: [],
        ),
        throwsA(isA<Nip46TokenParseException>()),
      );
    });
  });

  group('parseNostrconnect', () {
    String buildNostrconnect({
      String? pubkey,
      List<String> relays = const ['wss://relay.example.com'],
      String secret = 'mysecret',
      String? perms,
      String? name,
    }) {
      final p = pubkey ?? validPubkey;
      var uri = 'nostrconnect://$p?secret=$secret';
      for (final r in relays) {
        uri += '&relay=${Uri.encodeComponent(r)}';
      }
      if (perms != null) uri += '&perms=${Uri.encodeComponent(perms)}';
      if (name != null) uri += '&name=${Uri.encodeComponent(name)}';
      return uri;
    }

    test('parses valid nostrconnect URI', () {
      final token = Nip46TokenCodec.parseNostrconnect(buildNostrconnect());
      expect(token.clientPubkey, validPubkey);
      expect(token.relays, ['wss://relay.example.com']);
      expect(token.secret, 'mysecret');
    });

    test('handles multiple relay params', () {
      final token = Nip46TokenCodec.parseNostrconnect(
        buildNostrconnect(
          relays: ['wss://r1.example.com', 'wss://r2.example.com'],
        ),
      );
      expect(token.relays, hasLength(2));
      expect(token.relays, contains('wss://r1.example.com'));
      expect(token.relays, contains('wss://r2.example.com'));
    });

    test('parses optional metadata', () {
      final token = Nip46TokenCodec.parseNostrconnect(
        buildNostrconnect(perms: 'sign_event', name: 'Test App'),
      );
      expect(token.perms, 'sign_event');
      expect(token.name, 'Test App');
    });

    test('throws on missing secret', () {
      expect(
        () => Nip46TokenCodec.parseNostrconnect(
          'nostrconnect://$validPubkey?relay=${Uri.encodeComponent("wss://r.example.com")}',
        ),
        throwsA(isA<Nip46TokenParseException>()),
      );
    });

    test('throws on missing relay', () {
      expect(
        () => Nip46TokenCodec.parseNostrconnect(
          'nostrconnect://$validPubkey?secret=abc',
        ),
        throwsA(isA<Nip46TokenParseException>()),
      );
    });

    test('throws on invalid client pubkey', () {
      expect(
        () => Nip46TokenCodec.parseNostrconnect(
          'nostrconnect://notahex?secret=abc&relay=${Uri.encodeComponent("wss://r.example.com")}',
        ),
        throwsA(isA<Nip46TokenParseException>()),
      );
    });

    group('relays (#31)', () {
      test('accepts wss://, and ws:// outside release builds', () {
        final token = Nip46TokenCodec.parseNostrconnect(
          buildNostrconnect(relays: ['wss://a.example.com', 'ws://10.0.2.2:10547']),
        );
        expect(token.relays, ['wss://a.example.com', 'ws://10.0.2.2:10547']);
      });

      test('refuses ws:// when insecure relays are not allowed', () {
        expect(
          () => Nip46TokenCodec.parseNostrconnect(
            buildNostrconnect(relays: ['ws://relay.example.com']),
            allowInsecureRelays: false,
          ),
          throwsA(isA<Nip46TokenParseException>()),
        );
      });

      test('refuses relays that are not WebSocket URLs', () {
        for (final relay in [
          'https://relay.example.com',
          'javascript:alert(1)',
          'relay.example.com',
          'wss://',
        ]) {
          expect(
            () => Nip46TokenCodec.parseNostrconnect(
              buildNostrconnect(relays: [relay]),
            ),
            throwsA(isA<Nip46TokenParseException>()),
            reason: relay,
          );
        }
      });

      test('refuses more than the maximum, after dropping repeats', () {
        final many = [
          for (var i = 0; i <= Nip46TokenCodec.maxNostrconnectRelays; i++)
            'wss://r$i.example.com',
        ];
        expect(
          () => Nip46TokenCodec.parseNostrconnect(
            buildNostrconnect(relays: many),
          ),
          throwsA(isA<Nip46TokenParseException>()),
        );

        final repeated = Nip46TokenCodec.parseNostrconnect(
          buildNostrconnect(
            relays: List.filled(20, 'wss://same.example.com'),
          ),
        );
        expect(repeated.relays, ['wss://same.example.com']);
      });
    });

    test('throws on wrong scheme', () {
      expect(
        () => Nip46TokenCodec.parseNostrconnect(
          'bunker://$validPubkey?secret=abc',
        ),
        throwsA(isA<Nip46TokenParseException>()),
      );
    });
  });

  group('parseBunker', () {
    test('parses valid bunker URI', () {
      final uri =
          'bunker://$validPubkey?relay=${Uri.encodeComponent("wss://relay.example.com")}&secret=mysecret';
      final token = Nip46TokenCodec.parseBunker(uri);
      expect(token.remoteSignerPubkey, validPubkey);
      expect(token.relays, ['wss://relay.example.com']);
      expect(token.secret, 'mysecret');
    });

    test('throws on invalid remote signer pubkey', () {
      expect(
        () => Nip46TokenCodec.parseBunker(
          'bunker://notvalid?relay=${Uri.encodeComponent("wss://r.example.com")}&secret=x',
        ),
        throwsA(isA<Nip46TokenParseException>()),
      );
    });
  });
}
