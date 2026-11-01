import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What a NIP-05 check found (diogel-io/symudol#44).
enum Nip05Status {
  /// The domain lists the name for this identity's public key.
  verified,

  /// The identifier is not `name@domain`.
  malformed,

  /// The domain does not list the name.
  notFound,

  /// The domain lists the name for a different public key.
  mismatch,

  /// The domain answered with something that is not a NIP-05 response.
  invalidResponse,

  /// The domain could not be reached, or did not answer in time.
  networkError,
}

/// The outcome of checking [identifier], whose domain is [domain].
class Nip05Result {
  const Nip05Result(this.status, {required this.identifier, this.domain});

  final Nip05Status status;

  /// The identifier checked, trimmed.
  final String identifier;

  /// The identifier's domain, or null when it is malformed.
  final String? domain;
}

/// The name and domain of a NIP-05 identifier.
typedef Nip05Identifier = ({String name, String domain});

/// Splits [identifier] into its name and domain, or returns null when it is
/// not `name@domain`. NIP-05 names use only `a-z0-9-_.`, read here without
/// regard to case. A bare word is not a domain, and a port, path or user
/// would change where the request goes, so those are refused too.
Nip05Identifier? parseNip05Identifier(String identifier) {
  final match = RegExp(
    r'^([A-Za-z0-9._-]+)@([^@\s]+)$',
  ).firstMatch(identifier.trim());
  if (match == null) return null;
  final name = match.group(1)!;
  final domain = match.group(2)!;
  final Uri uri;
  try {
    uri = Uri.parse('https://$domain');
  } on FormatException {
    return null;
  }
  if (!uri.host.contains('.') ||
      uri.host != domain.toLowerCase() ||
      uri.host.split('.').any((label) => label.isEmpty)) {
    return null;
  }
  return (name: name, domain: domain);
}

/// Checks a NIP-05 identifier against its domain's `/.well-known/nostr.json`.
/// It is only ever called when the user asks: the request tells the domain
/// this device's address and the name looked up.
class Nip05Client {
  Nip05Client({http.Client? client, this.timeout = const Duration(seconds: 8)})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// How long the domain gets to answer, body and all.
  final Duration timeout;

  /// The largest answer read, so a hostile domain can't send megabytes.
  static const int maxResponseBytes = 64 * 1024;

  /// Asks [identifier]'s domain which key it lists for the name, and compares
  /// it with [pubkeyHex]. Never throws: every failure is a [Nip05Status].
  Future<Nip05Result> verify(String identifier, String pubkeyHex) async {
    final trimmed = identifier.trim();
    final parsed = parseNip05Identifier(trimmed);
    if (parsed == null) {
      return Nip05Result(Nip05Status.malformed, identifier: trimmed);
    }
    Nip05Result result(Nip05Status status) =>
        Nip05Result(status, identifier: trimmed, domain: parsed.domain);

    final uri = Uri.https(parsed.domain, '/.well-known/nostr.json', {
      'name': parsed.name,
    });
    // One deadline covers the answer and its body. Aborting closes the
    // connection, so a domain that trickles bytes can't hold it open.
    final abort = Completer<void>();
    // NIP-05: fetchers must ignore redirects, and following one would ask
    // another host.
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';

    final ({Nip05Status? status, List<int>? body}) fetched;
    try {
      fetched = await _fetch(request).timeout(timeout);
    } catch (_) {
      return result(Nip05Status.networkError);
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
    if (fetched.status case final Nip05Status status) return result(status);
    final body = fetched.body!;

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } catch (_) {
      return result(Nip05Status.invalidResponse);
    }
    final names = json is Map ? json['names'] : null;
    if (names is! Map || names.values.any((value) => value is! String)) {
      return result(Nip05Status.invalidResponse);
    }
    final found = names[parsed.name] ?? names[parsed.name.toLowerCase()];
    if (found == null) return result(Nip05Status.notFound);
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(found as String)) {
      return result(Nip05Status.invalidResponse);
    }
    return result(
      found.toLowerCase() == pubkeyHex.toLowerCase()
          ? Nip05Status.verified
          : Nip05Status.mismatch,
    );
  }

  /// Sends [request] and reads its answer: a status when the answer settles
  /// the check, or the body to parse.
  Future<({Nip05Status? status, List<int>? body})> _fetch(
    http.BaseRequest request,
  ) async {
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Release the unread body, so the connection isn't left open.
      unawaited(response.stream.listen(null).cancel());
      return (
        status: response.statusCode == 404
            ? Nip05Status.notFound
            : Nip05Status.networkError,
        body: null,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      // Too long for a NIP-05 answer, so stop reading.
      if (bytes.length > maxResponseBytes) {
        return (status: Nip05Status.invalidResponse, body: null);
      }
    }
    return (status: null, body: bytes);
  }
}
