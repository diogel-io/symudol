import 'package:android_diogel/features/nip46/domain/nip46_method.dart';
import 'package:android_diogel/features/nip46/domain/nip46_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nip46Request.fromDecryptedJson', () {
    test('parses a valid request', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-1',
        'method': 'get_public_key',
        'params': <Object?>[],
      });
      expect(req.id, 'req-1');
      expect(req.method, Nip46Method.getPublicKey);
      expect(req.params, isEmpty);
    });

    test('parses params as strings', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-2',
        'method': 'sign_event',
        'params': ['{"kind":1}'],
      });
      expect(req.param(0), '{"kind":1}');
    });

    test('normalises non-string params to empty string', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-3',
        'method': 'nip04_encrypt',
        'params': [null, 42],
      });
      expect(req.param(0), '');
      expect(req.param(1), ''); // non-string values normalize to empty string
    });

    test('missing id throws Nip46ParseException', () {
      expect(
        () => Nip46Request.fromDecryptedJson({
          'method': 'ping',
          'params': <Object?>[],
        }),
        throwsA(isA<Nip46ParseException>()),
      );
    });

    test('empty id throws Nip46ParseException', () {
      expect(
        () => Nip46Request.fromDecryptedJson({
          'id': '',
          'method': 'ping',
          'params': <Object?>[],
        }),
        throwsA(isA<Nip46ParseException>()),
      );
    });

    test('unknown method becomes unsupported', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-4',
        'method': 'nonexistent_method',
        'params': <Object?>[],
      });
      expect(req.method, Nip46Method.unsupported);
    });

    test('null method becomes unsupported', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-5',
        'method': null,
        'params': <Object?>[],
      });
      expect(req.method, Nip46Method.unsupported);
    });

    test('missing params defaults to empty list', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-6',
        'method': 'ping',
      });
      expect(req.params, isEmpty);
    });

    test('param() returns empty string for out-of-range index', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-7',
        'method': 'ping',
        'params': <Object?>[],
      });
      expect(req.param(5), '');
    });

    test('optionalParam() returns null for empty or missing param', () {
      final req = Nip46Request.fromDecryptedJson({
        'id': 'req-8',
        'method': 'sign_event',
        'params': ['', 'hello'],
      });
      expect(req.optionalParam(0), isNull);
      expect(req.optionalParam(1), 'hello');
      expect(req.optionalParam(2), isNull);
    });
  });
}
