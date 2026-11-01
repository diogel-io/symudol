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
/// not `name@domain`. A bare word is not a domain, and a port, path or user
/// would change where the request goes, so those are refused too.
Nip05Identifier? parseNip05Identifier(String identifier) {
  final match = RegExp(
    r'^([^@\s]+)@([^@\s]+)$',
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
  if (!uri.host.contains('.') || uri.host != domain.toLowerCase()) return null;
  return (name: name, domain: domain);
}

/// Checks a NIP-05 identifier against its domain's `/.well-known/nostr.json`.
/// It is only ever called when the user asks: the request tells the domain
/// this device's address and the name looked up.
class Nip05Client {
  Nip05Client({http.Client? client, this.timeout = const Duration(seconds: 8)})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// How long the domain gets to answer, and then to send its answer.
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
    // NIP-05: fetchers must ignore redirects, and following one would ask
    // another host.
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';

    final List<int> body;
    try {
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode == 404) return result(Nip05Status.notFound);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return result(Nip05Status.networkError);
      }
      final read = await _readCapped(response.stream).timeout(timeout);
      if (read == null) return result(Nip05Status.invalidResponse);
      body = read;
    } catch (_) {
      return result(Nip05Status.networkError);
    }

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

  /// The bytes of [stream], or null when it is longer than [maxResponseBytes].
  static Future<List<int>?> _readCapped(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length > maxResponseBytes) return null;
    }
    return bytes;
  }
}
