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

    final currentUser = raw['currentUser'] as String?;
    if (currentUser != null && !_isHex64(currentUser)) {
      throw const Nip55ParseException('Invalid current_user pubkey');
    }

    final pubkey = raw['pubkey'] as String?;
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
}
