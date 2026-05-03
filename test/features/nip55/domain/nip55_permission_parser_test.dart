import 'package:android_diogel/features/nip55/domain/nip55_permission_parser.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nip55PermissionParser', () {
    const parser = Nip55PermissionParser();

    test('parses kind-scoped sign_event', () {
      final parsed = parser.parse('sign_event:1');

      expect(parsed.warnings, isEmpty);
      expect(parsed.scopes, hasLength(1));
      expect(parsed.scopes.single, isA<SignEventScope>());
      expect((parsed.scopes.single as SignEventScope).kind, 1);
    });

    test('parses broad sign_event as high-risk warning', () {
      final parsed = parser.parse('sign_event');

      expect(parsed.scopes.single, isA<SignEventScope>());
      expect((parsed.scopes.single as SignEventScope).kind, isNull);
      expect(
        parsed.warnings,
        contains('Broad sign_event permission requested.'),
      );
    });

    test('surfaces malformed kind without throwing', () {
      final parsed = parser.parse('sign_event:not-a-kind');

      expect(parsed.scopes.single, isA<UnsupportedScope>());
      expect(parsed.warnings.single, contains('Unsupported permission'));
    });

    test('parses encryption/decryption permissions', () {
      final parsed = parser.parse(
        'nip44_encrypt nip44_decrypt,nip04_encrypt nip04_decrypt decrypt_zap_event',
      );

      expect(parsed.scopes, hasLength(5));
      expect(parsed.scopes[0], isA<Nip44EncryptScope>());
      expect(parsed.scopes[1], isA<Nip44DecryptScope>());
      expect(parsed.scopes[2], isA<Nip04EncryptScope>());
      expect(parsed.scopes[3], isA<Nip04DecryptScope>());
      expect(parsed.scopes[4], isA<DecryptZapEventScope>());
    });
  });
}
