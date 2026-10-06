import 'package:symudol/features/nip55/domain/nip55_permission_parser.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_scope.dart';
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
        contains(Nip55PermissionParser.broadSignEventWarning),
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

    test(
      'parses Amethyst style JSON object array permissions',
      () {
        final parsed = const Nip55PermissionParser().parse(
          '[{"type":"sign_event","kind":22242},{"type":"sign_event","kind":31234},'
          '{"type":"nip04_encrypt"},{"type":"nip04_decrypt"},'
          '{"type":"nip44_decrypt"},{"type":"nip44_decrypt"},'
          '{"type":"decrypt_zap_event"}]',
        );

        expect(parsed.warnings, isEmpty);

        final signEventKinds = parsed.scopes
            .whereType<SignEventScope>()
            .map((scope) => scope.kind)
            .toList();
        expect(signEventKinds, containsAll(<int?>[22242, 31234]));

        expect(parsed.scopes.whereType<Nip04EncryptScope>(), hasLength(1));
        expect(parsed.scopes.whereType<Nip04DecryptScope>(), hasLength(1));
        expect(parsed.scopes.whereType<Nip44DecryptScope>(), hasLength(2));
        expect(
          parsed.scopes.whereType<DecryptZapEventScope>(),
          hasLength(1),
        );
      },
    );

    // ── Dark-Wisp and Primal permission JSON fixtures ───────────────────

    test('parses Dark-Wisp style JSON object array with sign_event kinds', () {
      // Dark-Wisp sends a JSON object array with kind-scoped sign_event entries
      final parsed = const Nip55PermissionParser().parse(
        '[{"type":"sign_event","kind":1},{"type":"sign_event","kind":4},'
        '{"type":"sign_event","kind":22242},'
        '{"type":"nip04_encrypt"},{"type":"nip04_decrypt"}]',
      );

      expect(parsed.warnings, isEmpty);
      final signEventScopes = parsed.scopes.whereType<SignEventScope>().toList();
      expect(signEventScopes.map((s) => s.kind), containsAll(<int>[1, 4, 22242]));
      expect(parsed.scopes.whereType<Nip04EncryptScope>(), hasLength(1));
      expect(parsed.scopes.whereType<Nip04DecryptScope>(), hasLength(1));
    });

    test('parses Primal style JSON object array with nip44 and decrypt_zap_event', () {
      // Primal sends a similar JSON object array, typically nip44 and decrypt_zap_event
      final parsed = const Nip55PermissionParser().parse(
        '[{"type":"get_public_key"},{"type":"sign_event","kind":1},'
        '{"type":"nip44_encrypt"},{"type":"nip44_decrypt"},'
        '{"type":"decrypt_zap_event"}]',
      );

      expect(parsed.warnings, isEmpty);
      expect(parsed.scopes.whereType<GetPublicKeyScope>(), hasLength(1));
      expect(parsed.scopes.whereType<SignEventScope>().first.kind, 1);
      expect(parsed.scopes.whereType<Nip44EncryptScope>(), hasLength(1));
      expect(parsed.scopes.whereType<Nip44DecryptScope>(), hasLength(1));
      expect(parsed.scopes.whereType<DecryptZapEventScope>(), hasLength(1));
    });

    test('ping in permissions is silently ignored without warning', () {
      final parsed = const Nip55PermissionParser().parse(
        'ping get_public_key sign_event:1',
      );

      // ping is stateless — no scope created, no warning
      expect(parsed.warnings.any((w) => w.contains('ping')), isFalse);
      expect(parsed.scopes.whereType<GetPublicKeyScope>(), hasLength(1));
      expect(parsed.scopes.whereType<SignEventScope>(), hasLength(1));
    });

    test('ping in JSON array is silently ignored', () {
      final parsed = const Nip55PermissionParser().parse(
        '[{"type":"ping"},{"type":"get_public_key"}]',
      );

      // ping maps to UnsupportedScope via fromJson — kept as warning
      // OR explicitly ignored — either way, no ping scope is stored
      expect(parsed.scopes.whereType<GetPublicKeyScope>(), hasLength(1));
    });

    test('kind-scoped sign_event permissions are not widened to broad sign_event', () {
      final parsed = const Nip55PermissionParser().parse(
        'sign_event:1 sign_event:4 sign_event:22242',
      );

      final signEventScopes = parsed.scopes.whereType<SignEventScope>().toList();
      expect(signEventScopes, hasLength(3));
      expect(signEventScopes.every((s) => s.kind != null), isTrue);
      // No broad (null kind) scope should be present
      expect(signEventScopes.any((s) => s.kind == null), isFalse);
      expect(parsed.warnings, isEmpty);
    });

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
