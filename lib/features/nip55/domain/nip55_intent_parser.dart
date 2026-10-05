import 'package:bech32/bech32.dart';

import 'nip55_client.dart';
import 'nip55_failure.dart';
import 'nip55_incoming_request.dart';
import 'nip55_method.dart';
import 'nip55_payload.dart';
import 'nip55_web_return_options.dart';

class Nip55IntentParser {
  const Nip55IntentParser({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  Nip55IncomingRequest parse(Map<String, Object?> raw) {
    final parsedAt = (_now ?? DateTime.now)();
    final requestToken = raw['requestToken'] as String?;
    if (requestToken == null || requestToken.trim().isEmpty) {
      throw const Nip55ParseException('Missing NIP-55 request token');
    }

    final method = Nip55Method.fromWire(raw['type'] as String?);
    if (method == Nip55Method.unsupported) {
      throw const Nip55ParseException('Unsupported NIP-55 request type');
    }

    final rawCurrentUser = raw['currentUser'] as String?;
    final currentUser = _normalizeHexOrNpub(rawCurrentUser);
    if (rawCurrentUser != null && rawCurrentUser.trim().isNotEmpty && currentUser == null) {
      throw const Nip55ParseException('Invalid current_user pubkey');
    }

    final rawPubkey = (raw['pubkey'] ?? raw['pubKey']) as String?;
    final pubkey = _normalizeHexOrNpub(rawPubkey);
    if (method.requiresPeerPubkey && !_isHex64(pubkey)) {
      throw Nip55ParseException(
        'Missing or invalid ${method.wireName} peer pubkey',
      );
    }

    final content = raw['content'] as String?;
    // NOTE: This can be a heavy operation for large events.
    // If UI jank persists, consider moving this whole method to a Future and using Isolate.run.
    final payload = _parsePayload(
      method: method,
      content: content,
      pubkey: pubkey,
    );
    final eventJson = switch (payload) {
      SignEventPayload(:final unsignedEvent) => unsignedEvent,
      DecryptZapEventPayload(:final eventJson) => eventJson,
      _ => null,
    };

    return Nip55IncomingRequest(
      localId: 'nip55-${parsedAt.microsecondsSinceEpoch}',
      requestToken: requestToken,
      method: method,
      content: content,
      externalId: raw['id'] as String?,
      currentUser: currentUser,
      pubkey: pubkey,
      permissions: raw['permissions'] as String?,
      sourceHint: raw['sourceHint'] as String?,
      clientIdentity: _parseClientIdentity(raw),
      dataUri: raw['dataUri'] as String?,
      eventJson: eventJson,
      payload: payload,
      webReturnOptions: Nip55WebReturnOptions.fromRaw(raw),
      receivedAt: parsedAt,
    );
  }

  Nip55ClientIdentity _parseClientIdentity(Map<String, Object?> raw) {
    final packageName =
        _trimToNull(raw['callingPackage'] as String?) ??
        _trimToNull(raw['intentPackage'] as String?);
    final appLabel = _trimToNull(raw['callerAppLabel'] as String?);
    final certificateSha256 = _trimToNull(
      raw['callerCertificateSha256'] as String?,
    );
    final referrer = _trimToNull(raw['referrer'] as String?);
    return Nip55ClientIdentity(
      packageName: packageName,
      appLabel: appLabel,
      certificateSha256: certificateSha256,
      referrer: referrer,
      // These come only from Nip55BridgeActivity, which reads the package from
      // Android's callingPackage and the certificate from the package manager.
      // MainActivity no longer takes them from intent extras, which any app
      // could set (diogel-io/symudol#7), so "verified" means attested by Android.
      provenanceVerified: packageName != null && certificateSha256 != null,
    );
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Nip55Payload _parsePayload({
    required Nip55Method method,
    required String? content,
    required String? pubkey,
  }) {
    return switch (method) {
      Nip55Method.getPublicKey => const GetPublicKeyPayload(),
      Nip55Method.signMessage => SignMessagePayload(
        _requiredContent(content, 'Missing sign_message content'),
      ),
      Nip55Method.signEvent => SignEventPayload(
        decodeNip55JsonObject(
          methodLabel: 'sign_event',
          content: _requiredContent(content, 'Missing sign_event content'),
        ),
      ),
      Nip55Method.nip04Encrypt => Nip04EncryptPayload(
        content: _requiredContent(content, 'Missing nip04_encrypt content'),
        peerPubkey: pubkey!,
      ),
      Nip55Method.nip04Decrypt => Nip04DecryptPayload(
        content: _requiredContent(content, 'Missing nip04_decrypt content'),
        peerPubkey: pubkey!,
      ),
      Nip55Method.nip44Encrypt => Nip44EncryptPayload(
        content: _requiredContent(content, 'Missing nip44_encrypt content'),
        peerPubkey: pubkey!,
      ),
      Nip55Method.nip44Decrypt => Nip44DecryptPayload(
        content: _requiredContent(content, 'Missing nip44_decrypt content'),
        peerPubkey: pubkey!,
      ),
      Nip55Method.decryptZapEvent => DecryptZapEventPayload(
        decodeNip55JsonObject(
          methodLabel: 'decrypt_zap_event',
          content: _requiredContent(
            content,
            'Missing decrypt_zap_event content',
          ),
        ),
      ),
      Nip55Method.unsupported => throw const Nip55ParseException(
        'Unsupported NIP-55 request type',
      ),
    };
  }

  String _requiredContent(String? content, String message) {
    final trimmed = content?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      throw Nip55ParseException(message);
    }
    return content!;
  }

  bool _isHex64(String? value) =>
      value != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  /// Normalize a pubkey that is either 64-char hex or an NIP-19 npub1...
  /// bech32 string. Returns lowercase hex on success, null for blank/invalid.
  /// Only npub is accepted; other NIP-19 entity types are rejected.
  String? _normalizeHexOrNpub(String? value) {
    if (value == null) return null;
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    if (_isHex64(trimmed)) return trimmed;
    if (!trimmed.startsWith('npub1')) return null;
    try {
      final decoded = bech32.decode(trimmed, 90);
      if (decoded.hrp != 'npub') return null;
      final bytes = _convertBits(decoded.data, 5, 8);
      if (bytes == null || bytes.length != 32) return null;
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (_) {
      return null;
    }
  }

  static List<int>? _convertBits(List<int> data, int fromBits, int toBits) {
    final out = <int>[];
    int acc = 0, bits = 0;
    final maxv = (1 << toBits) - 1;
    for (final v in data) {
      if (v < 0 || v >> fromBits != 0) return null;
      acc = (acc << fromBits) | v;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        out.add((acc >> bits) & maxv);
      }
    }
    if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) return null;
    return out;
  }
}
