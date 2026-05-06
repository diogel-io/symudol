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

    // URL decode if needed
    var normalized = raw;
    if (normalized.contains('%')) {
      try {
        normalized = Uri.decodeComponent(normalized);
      } catch (_) {
        // Fallback to raw if decoding fails
      }
    }

    final scopes = <Nip55PermissionScope>[];
    final warnings = <String>[];
    final tokens = normalized
        .split(RegExp(r'[\s,\[\]]+'))
        .map((value) => value.trim())
        .map((value) => value.replaceAll(RegExp(r"^['" + '"' + r']+|[' + '"' + r']+$'), ''))
        .map((value) => value.replaceAll(RegExp(r"^'|'$"), ''))
        .where((value) => value.isNotEmpty);

    for (final token in tokens) {
      final scope = _parseToken(token);
      if (scope == null) {
        warnings.add('Unsupported permission: $token');
        continue;
      }
      scopes.add(scope);
      if (scope is SignEventScope && scope.kind == null) {
        warnings.add('Broad sign_event permission requested.');
      }
    }

    return Nip55ParsedPermissions(scopes: scopes, warnings: warnings);
  }

  Nip55PermissionScope? _parseToken(String rawToken) {
    final token = rawToken.toLowerCase();

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
      'connect' => const ConnectScope(),
      'sign_message' => const SignMessageScope(),
      _ => null,
    };
  }
}
