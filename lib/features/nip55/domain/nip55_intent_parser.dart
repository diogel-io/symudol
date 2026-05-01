import 'dart:convert';

import 'nip55_failure.dart';
import 'nip55_incoming_request.dart';
import 'nip55_method.dart';

class Nip55IntentParser {
  const Nip55IntentParser({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  Nip55IncomingRequest parse(Map<String, Object?> raw) {
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
      localId: 'nip55-${(_now ?? DateTime.now)().microsecondsSinceEpoch}',
      method: method,
      content: content,
      externalId: raw['id'] as String?,
      currentUser: currentUser,
      pubkey: raw['pubkey'] as String?,
      permissions: raw['permissions'] as String?,
      callerPackage: raw['callerPackage'] as String?,
      dataUri: raw['dataUri'] as String?,
      eventJson: eventJson,
      receivedAt: (_now ?? DateTime.now)(),
    );
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
