import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symudol/features/profile/data/nip05_client.dart';

const _pubkey =
    'b0635d6a9851d3aed0cd6c495b282167acf761729078d975fc341b22650b07b9';
const _other =
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

/// NIP-05 verification on request (diogel-io/symudol#44).
void main() {
  group('parseNip05Identifier', () {
    test('splits name and domain, trimmed', () {
      final parsed = parseNip05Identifier('  bob@example.com ');
      expect(parsed?.name, 'bob');
      expect(parsed?.domain, 'example.com');
    });

    test('accepts every character NIP-05 allows in a name', () {
      expect(parseNip05Identifier('a.b-c_9@example.com')?.name, 'a.b-c_9');
    });

    test('accepts a punycode top-level domain', () {
      expect(
        parseNip05Identifier('bob@example.xn--p1ai')?.domain,
        'example.xn--p1ai',
      );
    });

    test('accepts the root name', () {
      expect(parseNip05Identifier('_@example.com')?.name, '_');
    });

    for (final bad in [
      '',
      'bob',
      'bob@',
      '@example.com',
      'bob@alice@example.com',
      'bob smith@example.com',
      'bob@localhost',
      'bob@example.com:8443',
      'bob@example.com/path',
      'bob@user:pw@example.com',
      'bob@foo..example.com',
      'bob+tag@example.com',
      'bøb@example.com',
      'bob@.example.com',
      'bob@192.168.1.1',
      'bob@10.255.255.1',
      'bob@127.1',
      'bob@0x7f.0x1',
      'bob@[::1]',
      'bob@[fe80::1]',
    ]) {
      test('refuses "$bad"', () {
        expect(parseNip05Identifier(bad), isNull);
      });
    }
  });

  group('verify', () {
    late List<http.BaseRequest> requests;

    Nip05Client client(Future<http.Response> Function(http.Request) answer) {
      requests = [];
      return Nip05Client(
        client: MockClient((request) {
          requests.add(request);
          return answer(request);
        }),
      );
    }

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    test('asks the domain for the name, without following redirects', () async {
      final nip05 = client(
        (_) async => json({
          'names': {'bob': _pubkey},
        }),
      );

      await nip05.verify('bob@example.com', _pubkey);

      expect(requests, hasLength(1));
      final request = requests.single as http.Request;
      expect(
        request.url.toString(),
        'https://example.com/.well-known/nostr.json?name=bob',
      );
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(request.headers['Accept'], 'application/json');
    });

    test('verified when the domain lists this key', () async {
      final result = await client(
        (_) async => json({
          'names': {'bob': _pubkey},
        }),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.verified);
      expect(result.domain, 'example.com');
      expect(result.identifier, 'bob@example.com');
    });

    test('compares keys whatever their case', () async {
      final result = await client(
        (_) async => json({
          'names': {'bob': _pubkey.toUpperCase()},
        }),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.verified);
    });

    test('falls back to the lowercase name', () async {
      final result = await client(
        (_) async => json({
          'names': {'bob': _pubkey},
        }),
      ).verify('Bob@example.com', _pubkey);

      expect(result.status, Nip05Status.verified);
    });

    test('mismatch when the domain lists another key', () async {
      final result = await client(
        (_) async => json({
          'names': {'bob': _other},
        }),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.mismatch);
    });

    test('not found when the name is missing', () async {
      final result = await client(
        (_) async => json({
          'names': {'alice': _pubkey},
        }),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.notFound);
    });

    test('not found on a 404', () async {
      final result = await client(
        (_) async => http.Response('', 404),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.notFound);
    });

    for (final status in [301, 302, 500, 503]) {
      test('network error on HTTP $status', () async {
        final result = await client(
          (_) async => http.Response('', status),
        ).verify('bob@example.com', _pubkey);

        expect(result.status, Nip05Status.networkError);
      });
    }

    test('network error when the domain cannot be reached', () async {
      final result = await client(
        (_) async => throw const SocketException('no route'),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.networkError);
    });

    test('network error when the domain does not answer in time', () async {
      final result = await Nip05Client(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.networkError);
    });

    test(
      'one deadline covers a body that never finishes, then aborts',
      () async {
        final body = StreamController<List<int>>();
        addTearDown(body.close);
        http.AbortableRequest? sent;
        final watch = Stopwatch()..start();
        final result = await Nip05Client(
          client: MockClient.streaming((request, _) async {
            sent = request as http.AbortableRequest;
            body.add(utf8.encode('{"names":'));
            return http.StreamedResponse(body.stream, 200);
          }),
          timeout: const Duration(milliseconds: 200),
        ).verify('bob@example.com', _pubkey);

        expect(result.status, Nip05Status.networkError);
        expect(watch.elapsed, lessThan(const Duration(milliseconds: 400)));
        // A real client closes the connection when this completes.
        await expectLater(sent!.abortTrigger, completes);
      },
    );

    test('the same deadline covers slow headers and the body', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final watch = Stopwatch()..start();
      final result = await Nip05Client(
        client: MockClient.streaming((request, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.StreamedResponse(body.stream, 200);
        }),
        timeout: const Duration(milliseconds: 400),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.networkError);
      // Separate deadlines for the headers and the body would take 700 ms.
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 650)));
    });

    test('an error status releases the unread body', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);
      final result = await Nip05Client(
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(body.stream, 404),
        ),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.notFound);
      expect(cancelled, isTrue);
    });

    final invalid = <String, String>{
      'a body that is not JSON': '<html>',
      'no names': '{}',
      'names that are not a map': '{"names": ["bob"]}',
      'a name that is not a string': '{"names": {"bob": 1}}',
      'a key that is not hex': '{"names": {"bob": "npub1abc"}}',
      'a key of the wrong length': '{"names": {"bob": "abcd"}}',
      'JSON that is not an object': '[]',
    };
    for (final MapEntry(key: what, value: body) in invalid.entries) {
      test('invalid response for $what', () async {
        final result = await client(
          (_) async => http.Response(body, 200),
        ).verify('bob@example.com', _pubkey);

        expect(result.status, Nip05Status.invalidResponse);
      });
    }

    test('invalid response for an answer over the size cap', () async {
      final padding = 'x' * Nip05Client.maxResponseBytes;
      final result = await client(
        (_) async => json({
          'names': {'bob': _pubkey},
          'padding': padding,
        }),
      ).verify('bob@example.com', _pubkey);

      expect(result.status, Nip05Status.invalidResponse);
    });

    test('malformed identifiers ask nothing', () async {
      final nip05 = client((_) async => json({'names': {}}));

      final result = await nip05.verify('bob', _pubkey);

      expect(result.status, Nip05Status.malformed);
      expect(result.domain, isNull);
      expect(requests, isEmpty);
    });
  });
}
