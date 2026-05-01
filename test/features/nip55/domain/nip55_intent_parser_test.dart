import 'package:android_diogel/features/nip55/domain/nip55_failure.dart';
import 'package:android_diogel/features/nip55/domain/nip55_intent_parser.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
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
        'type': 'get_public_key',
        'permissions': '["sign_event"]',
        'callerPackage': 'com.example.app',
      });

      expect(request.method, Nip55Method.getPublicKey);
      expect(request.permissions, '["sign_event"]');
      expect(request.callerPackage, 'com.example.app');
    });

    test('parses sign_event', () {
      final request = parser.parse({
        'type': 'sign_event',
        'content': '{"kind":1,"content":"hello","tags":[]}',
        'id': 'caller-id',
        'currentUser': 'a' * 64,
      });

      expect(request.method, Nip55Method.signEvent);
      expect(request.externalId, 'caller-id');
      expect(request.eventJson?['kind'], 1);
      expect(request.eventJson?['content'], 'hello');
    });

    test('rejects unsupported method', () {
      expect(
        () => parser.parse({'type': 'nip04_encrypt'}),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects malformed event JSON', () {
      expect(
        () => parser.parse({'type': 'sign_event', 'content': '{bad'}),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects missing sign_event content', () {
      expect(
        () => parser.parse({'type': 'sign_event'}),
        throwsA(isA<Nip55ParseException>()),
      );
    });

    test('rejects invalid current_user', () {
      expect(
        () => parser.parse({
          'type': 'sign_event',
          'content': '{"kind":1,"content":"hello","tags":[]}',
          'currentUser': 'not-a-pubkey',
        }),
        throwsA(isA<Nip55ParseException>()),
      );
    });
  });
}
