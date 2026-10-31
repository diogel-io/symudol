import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../requests/domain/nostr_event_draft.dart';
import '../../requests/domain/signed_nostr_event.dart';

/// The BUD-02 upload authorisation kind.
const int blossomAuthKind = 24242;

/// How long an upload authorisation is valid for.
const Duration blossomAuthLifetime = Duration(minutes: 5);

/// An upload that failed, with a message for the user.
class BlossomException implements Exception {
  const BlossomException(this.message);

  final String message;

  @override
  String toString() => 'BlossomException: $message';
}

/// The lowercase hex SHA-256 of [bytes], which names a blob on Blossom.
String blobSha256(Uint8List bytes) => sha256.convert(bytes).toString();

/// The BUD-02 authorisation to upload the blob [sha256Hex], to be signed by
/// the identity uploading it.
NostrEventDraft blossomUploadAuth(String sha256Hex, {DateTime? now}) {
  final created = DateTime.fromMillisecondsSinceEpoch(
    (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 * 1000,
  );
  final expiration =
      created.add(blossomAuthLifetime).millisecondsSinceEpoch ~/ 1000;
  return NostrEventDraft(
    kind: blossomAuthKind,
    content: 'Upload profile image',
    tags: [
      ['t', 'upload'],
      ['x', sha256Hex],
      ['expiration', '$expiration'],
    ],
    createdAt: created,
  );
}

/// The `Authorization` header carrying [auth] (BUD-01).
String blossomAuthorizationHeader(SignedNostrEvent auth) =>
    'Nostr ${base64.encode(utf8.encode(jsonEncode(auth.toJson())))}';

/// Uploads images to a Blossom server (BUD-01/02, diogel-io/symudol#43).
class BlossomClient {
  BlossomClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 60);

  /// Uploads the JPEG [bytes] to [server], authorised by [auth], and returns
  /// the blob's URL. The server's answer must name the hash that was signed
  /// for and an https URL. Redirects are not followed, so the signed header
  /// never reaches another host. Throws [BlossomException].
  Future<String> upload({
    required String server,
    required Uint8List bytes,
    required SignedNostrEvent auth,
  }) async {
    final sha256Hex = blobSha256(bytes);
    final uri = Uri.parse('$server/upload');
    final request = http.Request('PUT', uri)
      ..followRedirects = false
      ..headers['Authorization'] = blossomAuthorizationHeader(auth)
      ..headers['Content-Type'] = 'image/jpeg'
      ..bodyBytes = bytes;

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } catch (_) {
      throw BlossomException(
        "Couldn't reach ${uri.host}. Check the connection and try again.",
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // BUD-01: the reason, if any, is in X-Reason.
      final reason = response.headers['x-reason']?.trim();
      throw BlossomException(
        reason == null || reason.isEmpty
            ? '${uri.host} refused the upload (HTTP ${response.statusCode}).'
            : '${uri.host} refused the upload: $reason',
      );
    }

    final Object? descriptor;
    try {
      descriptor = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const BlossomException(
        "The server's answer did not match the uploaded image.",
      );
    }
    if (descriptor is! Map ||
        descriptor['url'] is! String ||
        descriptor['sha256'] is! String ||
        (descriptor['sha256'] as String).toLowerCase() != sha256Hex) {
      throw const BlossomException(
        "The server's answer did not match the uploaded image.",
      );
    }
    final url = descriptor['url'] as String;
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw const BlossomException(
        'The server returned an address that is not https.',
      );
    }
    return url;
  }
}
