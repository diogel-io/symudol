sealed class Nip55PermissionScope {
  const Nip55PermissionScope();

  String get wire;
  String get label;
  bool get isBroad => false;
  bool get isSensitive => false;

  Map<String, Object?> toJson();

  static Nip55PermissionScope fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    final peerPubkey = json['peerPubkey'] as String?;
    return switch (type) {
      'get_public_key' => const GetPublicKeyScope(),
      'sign_event' => SignEventScope(
          json['kind'] as int?,
          json['relayUrl'] as String?,
        ),
      'nip44_encrypt' => Nip44EncryptScope(peerPubkey),
      'nip44_decrypt' => Nip44DecryptScope(peerPubkey),
      'nip04_encrypt' => Nip04EncryptScope(peerPubkey),
      'nip04_decrypt' => Nip04DecryptScope(peerPubkey),
      'decrypt_zap_event' => const DecryptZapEventScope(),
      'connect' => const ConnectScope(),
      'sign_message' => const SignMessageScope(),
      _ => UnsupportedScope(json['wire'] as String? ?? type ?? 'unknown'),
    };
  }
}

final class ConnectScope extends Nip55PermissionScope {
  const ConnectScope();

  @override
  String get wire => 'connect';

  @override
  String get label => 'Connect to signer';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class SignMessageScope extends Nip55PermissionScope {
  const SignMessageScope();

  @override
  String get wire => 'sign_message';

  @override
  String get label => 'Sign message';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class GetPublicKeyScope extends Nip55PermissionScope {
  const GetPublicKeyScope();

  @override
  String get wire => 'get_public_key';

  @override
  String get label => 'Share public key';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class SignEventScope extends Nip55PermissionScope {
  final int? kind;
  // Relay URL for kind 22242 (NIP-42 relay auth). A relay-specific grant only
  // matches auth requests for that relay. A null relay is a wildcard.
  final String? relayUrl;

  const SignEventScope([this.kind, this.relayUrl]);

  @override
  String get wire {
    if (kind == null) return 'sign_event';
    if (relayUrl == null) return 'sign_event:$kind';
    return 'sign_event:$kind:$relayUrl';
  }

  @override
  String get label {
    if (kind == null) return 'Sign any event kind';
    if (relayUrl == null) return 'Sign kind $kind';
    return 'Sign kind $kind for $relayUrl';
  }

  @override
  bool get isBroad => kind == null;

  @override
  Map<String, Object?> toJson() => {
    'type': 'sign_event',
    'kind': kind,
    'relayUrl': relayUrl,
  };
}

final class Nip44EncryptScope extends Nip55PermissionScope {
  final String? peerPubkey;
  const Nip44EncryptScope([this.peerPubkey]);

  @override
  String get wire => peerPubkey == null ? 'nip44_encrypt' : 'nip44_encrypt:$peerPubkey';

  @override
  String get label => peerPubkey == null ? 'NIP-44 encrypt' : 'NIP-44 encrypt with ${_short(peerPubkey!)}';

  @override
  Map<String, Object?> toJson() => {'type': 'nip44_encrypt', 'peerPubkey': peerPubkey};
}

final class Nip44DecryptScope extends Nip55PermissionScope {
  final String? peerPubkey;
  const Nip44DecryptScope([this.peerPubkey]);

  @override
  String get wire => peerPubkey == null ? 'nip44_decrypt' : 'nip44_decrypt:$peerPubkey';

  @override
  String get label => peerPubkey == null ? 'NIP-44 decrypt' : 'NIP-44 decrypt from ${_short(peerPubkey!)}';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': 'nip44_decrypt', 'peerPubkey': peerPubkey};
}

final class Nip04EncryptScope extends Nip55PermissionScope {
  final String? peerPubkey;
  const Nip04EncryptScope([this.peerPubkey]);

  @override
  String get wire => peerPubkey == null ? 'nip04_encrypt' : 'nip04_encrypt:$peerPubkey';

  @override
  String get label => peerPubkey == null ? 'NIP-04 encrypt' : 'NIP-04 encrypt with ${_short(peerPubkey!)}';

  @override
  Map<String, Object?> toJson() => {'type': 'nip04_encrypt', 'peerPubkey': peerPubkey};
}

final class Nip04DecryptScope extends Nip55PermissionScope {
  final String? peerPubkey;
  const Nip04DecryptScope([this.peerPubkey]);

  @override
  String get wire => peerPubkey == null ? 'nip04_decrypt' : 'nip04_decrypt:$peerPubkey';

  @override
  String get label => peerPubkey == null ? 'NIP-04 decrypt' : 'NIP-04 decrypt from ${_short(peerPubkey!)}';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': 'nip04_decrypt', 'peerPubkey': peerPubkey};
}

final class DecryptZapEventScope extends Nip55PermissionScope {
  const DecryptZapEventScope();

  @override
  String get wire => 'decrypt_zap_event';

  @override
  String get label => 'Decrypt zap event';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class UnsupportedScope extends Nip55PermissionScope {
  final String value;

  const UnsupportedScope(this.value);

  @override
  String get wire => value;

  @override
  String get label => 'Unsupported permission: $value';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': 'unsupported', 'wire': value};
}

extension Nip55PermissionScopeMatching on Nip55PermissionScope {
  bool matches(Nip55PermissionScope requested) {
    final grant = this;
    if (grant is SignEventScope && requested is SignEventScope) {
      if (grant.kind != null && grant.kind != requested.kind) return false;
      // Relay URL matching for kind 22242 (NIP-42 relay auth):
      // A relay-specific grant only covers that relay; a null relay is a wildcard.
      if (grant.relayUrl != null && grant.relayUrl != requested.relayUrl) {
        return false;
      }
      return true;
    }
    if (grant is Nip44EncryptScope && requested is Nip44EncryptScope) {
      return grant.peerPubkey == null || grant.peerPubkey == requested.peerPubkey;
    }
    if (grant is Nip44DecryptScope && requested is Nip44DecryptScope) {
      return grant.peerPubkey == null || grant.peerPubkey == requested.peerPubkey;
    }
    if (grant is Nip04EncryptScope && requested is Nip04EncryptScope) {
      return grant.peerPubkey == null || grant.peerPubkey == requested.peerPubkey;
    }
    if (grant is Nip04DecryptScope && requested is Nip04DecryptScope) {
      return grant.peerPubkey == null || grant.peerPubkey == requested.peerPubkey;
    }
    // Cross-scope: nip04_decrypt/nip44_decrypt grants satisfy decrypt_zap_event.
    // NIP-57 zap receipts are NIP-04 encrypted to the recipient, so if the
    // user trusts an app to decrypt DMs, they trust it to decrypt zaps too.
    // This mirrors Nip55PermissionMirror.scopeMatches on the Kotlin side.
    if (grant is Nip04DecryptScope && requested is DecryptZapEventScope) {
      return true;
    }
    if (grant is Nip44DecryptScope && requested is DecryptZapEventScope) {
      return true;
    }
    return runtimeType == requested.runtimeType;
  }
}

String _short(String hex) {
  if (hex.length <= 8) return hex;
  return '${hex.substring(0, 4)}...${hex.substring(hex.length - 4)}';
}
