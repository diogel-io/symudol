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

class Nip46TokenParseException implements Exception {
  final String message;
  const Nip46TokenParseException(this.message);

  @override
  String toString() => 'Nip46TokenParseException: $message';
}
