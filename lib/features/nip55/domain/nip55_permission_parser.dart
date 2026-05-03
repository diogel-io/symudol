import 'nip55_permission_scope.dart';

class Nip55ParsedPermissions {
  final List<Nip55PermissionScope> scopes;
  final List<String> warnings;

  const Nip55ParsedPermissions({
    required this.scopes,
    this.warnings = const [],
  });

  bool get hasWarnings => warnings.isNotEmpty;
}

class Nip55PermissionParser {
  const Nip55PermissionParser();

  Nip55ParsedPermissions parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const Nip55ParsedPermissions(scopes: []);
    }

    final scopes = <Nip55PermissionScope>[];
    final warnings = <String>[];
    for (final token
        in raw
            .split(RegExp(r'[\s,]+'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)) {
      final scope = _parseToken(token);
      if (scope == null) {
        warnings.add('Unsupported permission: $token');
        scopes.add(UnsupportedScope(token));
        continue;
      }
      scopes.add(scope);
      if (scope is SignEventScope && scope.kind == null) {
        warnings.add('Broad sign_event permission requested.');
      }
    }

    return Nip55ParsedPermissions(scopes: scopes, warnings: warnings);
  }

  Nip55PermissionScope? _parseToken(String token) {
    if (token == 'sign_event') return const SignEventScope();
    if (token.startsWith('sign_event:')) {
      final kindPart = token.substring('sign_event:'.length);
      if (kindPart.isEmpty) return null;
      final kind = int.tryParse(kindPart);
      if (kind == null || kind < 0) return null;
      return SignEventScope(kind);
    }

    return switch (token) {
      'get_public_key' => const GetPublicKeyScope(),
      'nip44_encrypt' => const Nip44EncryptScope(),
      'nip44_decrypt' => const Nip44DecryptScope(),
      'nip04_encrypt' => const Nip04EncryptScope(),
      'nip04_decrypt' => const Nip04DecryptScope(),
      'decrypt_zap_event' => const DecryptZapEventScope(),
      _ => null,
    };
  }
}
