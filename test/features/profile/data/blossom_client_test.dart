import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symudol/features/profile/data/blossom_client.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';

final _bytes = Uint8List.fromList([1, 2, 3, 4]);
final _sha = blobSha256(_bytes);

SignedNostrEvent _auth() => SignedNostrEvent(
  id: 'a' * 64,
  pubkey: 'b' * 64,
  createdAt: 1700000000,
  kind: blossomAuthKind,
  tags: [
    ['t', 'upload'],
    ['x', _sha],
    ['expiration', '1700000300'],
  ],
  content: 'Upload profile image',
  sig: 'c' * 128,
);

void main() {
  group('blossomUploadAuth (#43)', () {
    test('authorises an upload of one blob for five minutes', () {
      final draft = blossomUploadAuth(
        _sha,
        now: DateTime.fromMillisecondsSinceEpoch(1700000000123),
      );

      expect(draft.kind, 24242);
      expect(draft.createdAt.millisecondsSinceEpoch, 1700000000000);
      expect(draft.tags, [
        ['t', 'upload'],
        ['x', _sha],
        ['expiration', '1700000300'],
      ]);
    });

    test('the header is the event as base64 JSON after "Nostr "', () {
      final header = blossomAuthorizationHeader(_auth());

      expect(header, startsWith('Nostr '));
      final event = jsonDecode(
        utf8.decode(base64.decode(header.substring('Nostr '.length))),
      );
      expect(event['kind'], 24242);
      expect(event['sig'], 'c' * 128);
    });
  });

  group('BlossomClient.upload (#43)', () {
    test('PUTs the JPEG to /upload and returns the URL', () async {
      late http.BaseRequest sent;
      late Uint8List body;
      final client = BlossomClient(
        client: MockClient((request) async {
          sent = request;
          body = request.bodyBytes;
          return http.Response(
            jsonEncode({
              'url': 'https://cdn.example/$_sha.jpg',
              'sha256': _sha,
            }),
            200,
          );
        }),
      );

      final url = await client.upload(
        server: 'https://blossom.example',
        bytes: _bytes,
        auth: _auth(),
      );

      expect(url, 'https://cdn.example/$_sha.jpg');
      expect(sent.method, 'PUT');
      expect(sent.url.toString(), 'https://blossom.example/upload');
      expect(sent.headers['Content-Type'], 'image/jpeg');
      expect(
        sent.headers['Authorization'],
        blossomAuthorizationHeader(_auth()),
      );
      expect(sent.followRedirects, isFalse);
      expect(body, _bytes);
    });

    Future<Object?> uploadAnswering(http.Response response) async {
      final client = BlossomClient(client: MockClient((_) async => response));
      try {
        await client.upload(
          server: 'https://blossom.example',
          bytes: _bytes,
          auth: _auth(),
        );
        return null;
      } catch (error) {
        return error;
      }
    }

    test('rejects an answer for a different blob', () async {
      final error = await uploadAnswering(
        http.Response(
          jsonEncode({'url': 'https://cdn.example/x.jpg', 'sha256': 'f' * 64}),
          200,
        ),
      );

      expect(error, isA<BlossomException>());
    });

    test('rejects a URL that is not https', () async {
      final error = await uploadAnswering(
        http.Response(
          jsonEncode({'url': 'http://cdn.example/x.jpg', 'sha256': _sha}),
          200,
        ),
      );

      expect(
        (error as BlossomException).message,
        'The server returned an address that is not https.',
      );
    });

    test('quotes the X-Reason of a refusal', () async {
      final error = await uploadAnswering(
        http.Response('', 401, headers: {'x-reason': 'Auth expired'}),
      );

      expect(
        (error as BlossomException).message,
        'blossom.example refused the upload: Auth expired',
      );
    });

    test('names the status of a refusal without a reason', () async {
      final error = await uploadAnswering(http.Response('', 413));

      expect(
        (error as BlossomException).message,
        'blossom.example refused the upload (HTTP 413).',
      );
    });

    test('does not follow a redirect with the signed header', () async {
      final error = await uploadAnswering(
        http.Response('', 307, headers: {'location': 'https://other.example'}),
      );

      expect(error, isA<BlossomException>());
    });

    test('rejects an answer that is not a descriptor', () async {
      final error = await uploadAnswering(http.Response('<html>', 200));

      expect(error, isA<BlossomException>());
    });

    test('reports a server it could not reach', () async {
      final client = BlossomClient(
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(
        client.upload(
          server: 'https://blossom.example',
          bytes: _bytes,
          auth: _auth(),
        ),
        throwsA(
          isA<BlossomException>().having(
            (error) => error.message,
            'message',
            contains("Couldn't reach blossom.example"),
          ),
        ),
      );
    });
  });
}
