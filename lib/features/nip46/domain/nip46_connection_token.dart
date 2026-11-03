class Nip46BunkerToken {
  final String remoteSignerPubkey;
  final List<String> relays;
  final String secret;

  const Nip46BunkerToken({
    required this.remoteSignerPubkey,
    required this.relays,
    required this.secret,
  });

  String toUri() {
    final params = StringBuffer();
    for (final relay in relays) {
      if (params.isNotEmpty) params.write('&');
      params.write('relay=${Uri.encodeComponent(relay)}');
    }
    if (params.isNotEmpty) params.write('&');
    params.write('secret=${Uri.encodeComponent(secret)}');
    return 'bunker://$remoteSignerPubkey?$params';
  }
}

class Nip46NostrconnectToken {
  final String clientPubkey;
  final List<String> relays;
  final String secret;
  final String? perms;
  final String? name;
  final String? url;
  final String? image;

  const Nip46NostrconnectToken({
    required this.clientPubkey,
    required this.relays,
    required this.secret,
    this.perms,
    this.name,
    this.url,
    this.image,
  });
}

/// A nostrconnect:// URI from a client that already has an active session
/// (#31). Pairing it again would answer that client twice.
class Nip46AlreadyConnectedException implements Exception {
  const Nip46AlreadyConnectedException();

  @override
  String toString() => 'This client is already connected.';
}

/// The vault was wiped while a connection was being made: it belonged to the
/// old vault, so it was dropped (#31).
class Nip46VaultWipedException implements Exception {
  const Nip46VaultWipedException();

  @override
  String toString() => 'The Symudol vault was erased.';
}

class Nip46TokenParseException implements Exception {
  final String message;
  const Nip46TokenParseException(this.message);

  @override
  String toString() => 'Nip46TokenParseException: $message';
}
