import 'dart:convert';

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
  /// Shown on the approval screen when an app asks to sign any event kind.
  /// That permission is never remembered (#5), so the user is told each such
  /// signature will be asked for, rather than led to think it was granted.
  static const broadSignEventWarning =
      'This app asked to sign any kind of event. That is not remembered: '
      'you will be asked for each one.';

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

    final jsonObjectList = _tryDecodeJsonObjectList(normalized);
    if (jsonObjectList != null) {
      return _parseJsonObjectList(jsonObjectList);
    }

    final scopes = <Nip55PermissionScope>[];
    final warnings = <String>[];
    final tokens = normalized
        .split(RegExp(r'[\s,\[\]]+'))
        .map((value) => value.trim())
        .map((value) => value.replaceAll(RegExp(r'''^['"]+|['"]+$'''), ''))
        .map((value) => value.replaceAll(RegExp(r"^'|'$"), ''))
        .where((value) => value.isNotEmpty);

    for (final token in tokens) {
      if (_isStatelessToken(token)) continue; // e.g. ping — provider handles these without a stored grant
      final scope = _parseToken(token);
      if (scope == null) {
        warnings.add('Unsupported permission: $token');
        continue;
      }
      scopes.add(scope);
      if (scope is SignEventScope && scope.kind == null) {
        warnings.add(broadSignEventWarning);
      }
    }

    return Nip55ParsedPermissions(scopes: scopes, warnings: warnings);
  }

  /// Attempts to decode [normalized] as a JSON array containing permission
  /// objects (e.g. `[{"type":"sign_event","kind":1}, ...]`), the format sent
  /// by apps like Amethyst. Returns null if it isn't a JSON array of objects,
  /// so the caller can fall back to the legacy token-based formats.
  List<Map<String, Object?>>? _tryDecodeJsonObjectList(String normalized) {
    Object? decoded;
    try {
      decoded = jsonDecode(normalized);
    } catch (_) {
      return null;
    }
    if (decoded is! List || decoded.isEmpty) return null;
    if (decoded.every((item) => item is Map)) {
      return decoded.cast<Map<String, Object?>>();
    }
    return null;
  }

  Nip55ParsedPermissions _parseJsonObjectList(
    List<Map<String, Object?>> items,
  ) {
    final scopes = <Nip55PermissionScope>[];
    final warnings = <String>[];

    for (final item in items) {
      final scope = Nip55PermissionScope.fromJson(item);
      if (scope is UnsupportedScope) {
        warnings.add('Unsupported permission: ${scope.value}');
        continue;
      }
      scopes.add(scope);
      if (scope is SignEventScope && scope.kind == null) {
        warnings.add(broadSignEventWarning);
      }
    }

    return Nip55ParsedPermissions(scopes: scopes, warnings: warnings);
  }

  /// Tokens that the provider handles statelessly — no persistent grant needed.
  bool _isStatelessToken(String token) => token == 'ping';

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
