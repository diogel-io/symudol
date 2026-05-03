import 'dart:convert';

import 'nip55_client.dart';
import 'nip55_failure.dart';
import 'nip55_incoming_request.dart';
import 'nip55_method.dart';
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

    final content = raw['content'] as String?;
    Map<String, Object?>? eventJson;
    if (method == Nip55Method.signEvent) {
      if (content == null || content.trim().isEmpty) {
        throw const Nip55ParseException('Missing sign_event content');
      }
      eventJson = _decodeEventJson(content);
    }

    return Nip55IncomingRequest(
      localId: 'nip55-${parsedAt.microsecondsSinceEpoch}',
      requestToken: requestToken,
      method: method,
      content: content,
      externalId: raw['id'] as String?,
      currentUser: currentUser,
      pubkey: raw['pubkey'] as String?,
      permissions: raw['permissions'] as String?,
      sourceHint: raw['sourceHint'] as String?,
      clientIdentity: _parseClientIdentity(raw),
      dataUri: raw['dataUri'] as String?,
      eventJson: eventJson,
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

  Map<String, Object?> _decodeEventJson(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const Nip55ParseException(
          'sign_event content must be a JSON object',
        );
      }
      return decoded.cast<String, Object?>();
    } on Nip55ParseException {
      rethrow;
    } catch (error) {
      throw Nip55ParseException('Malformed sign_event JSON: $error');
    }
  }

  bool _isHex64(String value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}
