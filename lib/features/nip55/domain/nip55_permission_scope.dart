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
      'sign_event' => SignEventScope(json['kind'] as int?),
      'nip44_encrypt' => Nip44EncryptScope(peerPubkey),
      'nip44_decrypt' => Nip44DecryptScope(peerPubkey),
      'nip04_encrypt' => Nip04EncryptScope(peerPubkey),
      'nip04_decrypt' => Nip04DecryptScope(peerPubkey),
      'decrypt_zap_event' => const DecryptZapEventScope(),
      _ => UnsupportedScope(json['wire'] as String? ?? type ?? 'unknown'),
    };
  }
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

  const SignEventScope([this.kind]);

  @override
  String get wire => kind == null ? 'sign_event' : 'sign_event:$kind';

  @override
  String get label => kind == null ? 'Sign any event kind' : 'Sign kind $kind';

  @override
  bool get isBroad => kind == null;

  @override
  Map<String, Object?> toJson() => {'type': 'sign_event', 'kind': kind};
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
      return grant.kind == null || grant.kind == requested.kind;
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
    return runtimeType == requested.runtimeType;
  }
}

String _short(String hex) {
  if (hex.length <= 8) return hex;
  return '${hex.substring(0, 4)}...${hex.substring(hex.length - 4)}';
}
