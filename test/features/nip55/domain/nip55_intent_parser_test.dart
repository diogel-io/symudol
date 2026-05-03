import 'package:android_diogel/features/nip55/domain/nip55_failure.dart';
import 'package:android_diogel/features/nip55/domain/nip55_intent_parser.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/nip55/domain/nip55_payload.dart';
import 'package:android_diogel/features/nip55/domain/nip55_web_return_options.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('parses all NIP-55 method wire names', () {
      final peerPubkey = 'b' * 64;
      final cases = <String, Map<String, Object?>>{
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
  });
}
