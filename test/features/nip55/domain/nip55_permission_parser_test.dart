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

      expect(parsed.scopes, isEmpty);
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

    test('drops empty permissions without unsupported warning', () {
      const parser = Nip55PermissionParser();

      for (final raw in ['', ' ', '[]', '[""]', '[,]', ',,,', '["",""]']) {
        final parsed = parser.parse(raw);
        expect(parsed.scopes, isEmpty, reason: 'Failed for input: "$raw"');
        expect(parsed.warnings, isEmpty, reason: 'Failed for input: "$raw"');
      }
    });

    test('does not put unsupported tokens into scopes', () {
      final parsed = const Nip55PermissionParser().parse(
        'unknown_token get_public_key',
      );

      // 'unknown_token' should be in warnings or dropped, but NOT in scopes
      expect(parsed.scopes, hasLength(1));
      expect(parsed.scopes.single, isA<GetPublicKeyScope>());
      expect(
        parsed.warnings.single,
        contains('Unsupported permission: unknown_token'),
      );
    });

    test(
      'parses Amethyst style mixed permissions without blank unsupported warning',
      () {
        final parsed = const Nip55PermissionParser().parse(
          '["connect","get_public_key","nip04_decrypt",""]',
        );

        expect(parsed.scopes.whereType<GetPublicKeyScope>(), hasLength(1));
        expect(parsed.scopes.whereType<Nip04DecryptScope>(), hasLength(1));
        expect(
          parsed.warnings.any(
            (warning) => warning.trim() == 'Unsupported permission:',
          ),
          isFalse,
        );
      },
    );

    test('recognizes Amber connect permission without unsupported warning', () {
      final parsed = const Nip55PermissionParser().parse(
        'connect get_public_key',
      );

      expect(parsed.warnings.where((w) => w.contains('connect')), isEmpty);
      expect(
        parsed.warnings.any((w) => w.contains('Unsupported permission:')),
        isFalse,
      );
    });

    test(
      'recognizes sign_message permission token without unsupported warning',
      () {
        final parsed = const Nip55PermissionParser().parse(
          'sign_message get_public_key',
        );
        expect(
          parsed.warnings.any((warning) => warning.contains('sign_message')),
          isFalse,
        );
        expect(
          parsed.scopes.map((scope) => scope.label).join(', '),
          isNot(contains('Unsupported permission')),
        );
      },
    );

    test('Amber extra permission tokens are warnings only, not scopes', () {
      final parsed = const Nip55PermissionParser().parse(
        'encrypt_clear_text decrypt_clear_text encrypt_event decrypt_event encrypt_tag_array decrypt_tag_array get_public_key',
      );

      expect(parsed.scopes, hasLength(1));
      expect(parsed.scopes.single, isA<GetPublicKeyScope>());
      expect(
        parsed.scopes.map((scope) => scope.label).join(', '),
        isNot(contains('Unsupported permission')),
      );
      for (final token in [
        'encrypt_clear_text',
        'decrypt_clear_text',
        'encrypt_event',
        'decrypt_event',
        'encrypt_tag_array',
        'decrypt_tag_array',
      ]) {
        expect(parsed.warnings, contains('Unsupported permission: $token'));
      }
    });
  });
}
