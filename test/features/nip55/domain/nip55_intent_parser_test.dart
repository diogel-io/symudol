import 'package:android_diogel/features/nip55/domain/nip55_failure.dart';
import 'package:android_diogel/features/nip55/domain/nip55_intent_parser.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/nip55/domain/nip55_payload.dart';
import 'package:android_diogel/features/nip55/domain/nip55_web_return_options.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/amethyst_sign_event.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 5, 1);
  late Nip55IntentParser parser;

  setUp(() {
    parser = Nip55IntentParser(now: () => fixedNow);
  });

  group('Nip55IntentParser', () {
    test('parses get_public_key', () {
      final request = parser.parse({
        'requestToken': 'token-1',
        'type': 'get_public_key',
        'permissions': '["sign_event"]',
        'sourceHint': 'com.example.app',
      });

      expect(request.method, Nip55Method.getPublicKey);
      expect(request.payload, isA<GetPublicKeyPayload>());
      expect(request.requestToken, 'token-1');
      expect(request.permissions, '["sign_event"]');
      expect(request.sourceHint, 'com.example.app');
    });

    test('parses sign_event', () {
      final request = parser.parse({
        'requestToken': 'token-2',
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'id': 'caller-id',
        'currentUser': 'a' * 64,
      });

      expect(request.method, Nip55Method.signEvent);
      expect(request.payload, isA<SignEventPayload>());
      expect(request.externalId, 'caller-id');
      expect(request.eventJson?['kind'], 1);
      expect(request.eventJson?['content'], 'hello');
    });

    test('parses sign_message', () {
      final request = parser.parse({
        'requestToken': 'token-sign-message',
        'type': 'sign_message',
        'content': 'hello message',
        'currentUser': 'a' * 64,
      });

      expect(request.method, Nip55Method.signMessage);
      expect(request.payload, isA<SignMessagePayload>());
      expect((request.payload as SignMessagePayload).message, 'hello message');
    });

    test('parses all NIP-55 method wire names', () {
      final peerPubkey = 'b' * 64;
      final cases = <String, Map<String, Object?>>{
        'sign_message': {'content': 'hello'},
        'nip04_encrypt': {'content': 'hello', 'pubkey': peerPubkey},
        'nip04_decrypt': {'content': 'ciphertext', 'pubkey': peerPubkey},
        'nip44_encrypt': {'content': 'hello', 'pubkey': peerPubkey},
        'nip44_decrypt': {'content': 'ciphertext', 'pubkey': peerPubkey},
        'decrypt_zap_event': {
          'content': '{"kind":9735,"content":"encrypted","tags":[]}',
        },
      };

      for (final entry in cases.entries) {
        final request = parser.parse({
          'requestToken': 'token-${entry.key}',
          'type': entry.key,
          ...entry.value,
        });
        expect(request.method.wireName, entry.key);
        expect(request.payload, isNot(isA<GetPublicKeyPayload>()));
      }
    });

    test('accepts Quartz/Amethyst foreground pubKey alias', () {
      final peerPubkey = 'c' * 64;
      final request = parser.parse({
        'requestToken': 'token-quartz-pubKey',
        'type': 'nip04_decrypt',
        'content': 'ciphertext',
        'pubKey': peerPubkey,
      });

      expect(request.pubkey, peerPubkey);
      expect(request.payload, isA<Nip04DecryptPayload>());
    });

    test('parses browser return options', () {
      final request = parser.parse({
        'requestToken': 'token-web',
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'callbackUrl': 'https://example.com/callback',
        'returnType': 'event',
        'compressionType': 'gzip',
      });

      expect(
        request.webReturnOptions.callbackUrl.toString(),
        'https://example.com/callback',
      );
      expect(request.webReturnOptions.returnType, Nip55WebReturnType.event);
      expect(
        request.webReturnOptions.compressionType,
        Nip55WebCompressionType.gzip,
      );
    });

    test('parses explicit browser flow without callback metadata', () {
      final request = parser.parse({
        'requestToken': 'token-browser-no-callback',
        'type': 'get_public_key',
        'isBrowserFlow': true,
      });

      expect(request.webReturnOptions.isBrowserFlow, isTrue);
      expect(request.webReturnOptions.hasCallback, isFalse);
    });

    test('rejects unknown unsupported method', () {
      expect(
        () => parser.parse({'requestToken': 'token-3', 'type': 'unknown'}),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects malformed event JSON', () {
      expect(
        () => parser.parse({
          'requestToken': 'token-4',
          'type': 'sign_event',
          'content': '{bad',
        }),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects missing sign_event content', () {
      expect(
        () => parser.parse({'requestToken': 'token-5', 'type': 'sign_event'}),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects missing sign_message content', () {
      expect(
        () => parser.parse({
          'requestToken': 'token-missing-sign-message',
          'type': 'sign_message',
        }),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects invalid current_user', () {
      expect(
        () => parser.parse({
          'requestToken': 'token-6',
          'type': 'sign_event',
          'content': '{"kind":1,"content":"hello","tags":[]}',
          'currentUser': 'not-a-pubkey',
        }),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects missing peer pubkey for NIP-04/NIP-44 operations', () {
      for (final method in const [
        'nip04_encrypt',
        'nip04_decrypt',
        'nip44_encrypt',
        'nip44_decrypt',
      ]) {
        expect(
          () => parser.parse({
            'requestToken': 'token-$method',
            'type': method,
            'content': 'payload',
          }),
          throwsA(isA<Nip55ParseException>()),
        );
      }
    });

    test('rejects empty encrypt/decrypt content', () {
      expect(
        () => parser.parse({
          'requestToken': 'token-empty',
          'type': 'nip44_encrypt',
          'content': ' ',
          'pubkey': 'b' * 64,
        }),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects missing request token', () {
      expect(
        () => parser.parse({'type': 'get_public_key'}),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('parses Amethyst-style sign_event extras', () {
      final request = parser.parse(amethystSignEventExtras());

      expect(request.method, Nip55Method.signEvent);
      expect(request.externalId, 'amethyst-req-1');
      expect(request.currentUser, amethystSignerPubkey);
      expect(request.eventJson?['kind'], 1);
      expect(request.eventJson?['content'], 'hello from amethyst');
      expect(request.payload, isA<SignEventPayload>());
    });
  });
}
