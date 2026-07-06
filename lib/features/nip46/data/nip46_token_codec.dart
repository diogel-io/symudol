import 'dart:math';
import 'dart:typed_data';

import '../domain/nip46_connection_token.dart';

class Nip46TokenCodec {
  const Nip46TokenCodec._();

  static Nip46BunkerToken generateBunkerToken({
    required String remoteSignerPubkey,
    required List<String> relays,
    Uint8List Function(int)? randomBytes,
  }) {
    if (relays.isEmpty) {
      throw const Nip46TokenParseException(
        'At least one relay is required for a bunker token',
      );
    }
    final secret = _hexSecret(randomBytes ?? _secureRandomBytes, 32);
    return Nip46BunkerToken(
      remoteSignerPubkey: remoteSignerPubkey,
      relays: List.unmodifiable(relays),
      secret: secret,
    );
  }

  static Nip46NostrconnectToken parseNostrconnect(String uri) {
    final parsed = _parseUri(uri, 'nostrconnect');
    final clientPubkey = parsed.host;
    _validateHex64(clientPubkey, 'nostrconnect client pubkey');

    final queryParams = parsed.queryParametersAll;
    final relays = _extractRelays(queryParams);
    if (relays.isEmpty) {
      throw const Nip46TokenParseException(
        'nostrconnect:// token must include at least one relay',
      );
    }

    final secret = _requireParam(queryParams, 'secret', 'nostrconnect');
    final perms = _optionalParam(queryParams, 'perms');
    final name = _optionalParam(queryParams, 'name');
    final url = _optionalParam(queryParams, 'url');
    final image = _optionalParam(queryParams, 'image');

    return Nip46NostrconnectToken(
      clientPubkey: clientPubkey,
      relays: relays,
      secret: secret,
      perms: perms,
      name: name,
      url: url,
      image: image,
    );
  }

  static Nip46BunkerToken parseBunker(String uri) {
    final parsed = _parseUri(uri, 'bunker');
    final remoteSignerPubkey = parsed.host;
    _validateHex64(remoteSignerPubkey, 'bunker remote signer pubkey');

    final queryParams = parsed.queryParametersAll;
    final relays = _extractRelays(queryParams);
    if (relays.isEmpty) {
      throw const Nip46TokenParseException(
        'bunker:// token must include at least one relay',
      );
    }

    final secret = _requireParam(queryParams, 'secret', 'bunker');

    return Nip46BunkerToken(
      remoteSignerPubkey: remoteSignerPubkey,
      relays: relays,
      secret: secret,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static Uri _parseUri(String uri, String expectedScheme) {
    Uri parsed;
    try {
      parsed = Uri.parse(uri);
    } catch (_) {
      throw Nip46TokenParseException('Invalid URI: $uri');
    }
    if (parsed.scheme != expectedScheme) {
      throw Nip46TokenParseException(
        'Expected $expectedScheme:// URI, got ${parsed.scheme}://',
      );
    }
    return parsed;
  }

  static List<String> _extractRelays(Map<String, List<String>> params) {
    final raw = params['relay'] ?? [];
    return raw
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
        .toList();
  }

  static String _requireParam(
    Map<String, List<String>> params,
    String key,
    String context,
  ) {
    final values = params[key] ?? [];
    final v = values.firstOrNull?.trim() ?? '';
    if (v.isEmpty) {
      throw Nip46TokenParseException(
        '$context token is missing required parameter: $key',
      );
    }
    return v;
  }

  static String? _optionalParam(Map<String, List<String>> params, String key) {
    final v = (params[key] ?? []).firstOrNull?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  static void _validateHex64(String value, String label) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw Nip46TokenParseException('Invalid $label: $value');
    }
  }

  static String _hexSecret(Uint8List Function(int) randomBytes, int length) {
    final bytes = randomBytes(length);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
