sealed class Nip46PermissionScope {
  const Nip46PermissionScope();

  String get wire;
  String get label;
  bool get isBroad => false;
  bool get isSensitive => false;

  Map<String, Object?> toJson();

  static Nip46PermissionScope fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'get_public_key' => const Nip46GetPublicKeyScope(),
      'ping' => const Nip46PingScope(),
      'sign_event' => Nip46SignEventScope(json['kind'] as int?),
      'nip04_encrypt' => const Nip46Nip04EncryptScope(),
      'nip04_decrypt' => const Nip46Nip04DecryptScope(),
      'nip44_encrypt' => const Nip46Nip44EncryptScope(),
      'nip44_decrypt' => const Nip46Nip44DecryptScope(),
      'decrypt_zap_event' => const Nip46DecryptZapEventScope(),
      'switch_relays' => const Nip46SwitchRelaysScope(),
      'get_relays' => const Nip46GetRelaysScope(),
      _ => Nip46UnsupportedScope(json['wire'] as String? ?? type ?? 'unknown'),
    };
  }
}

final class Nip46GetPublicKeyScope extends Nip46PermissionScope {
  const Nip46GetPublicKeyScope();

  @override
  String get wire => 'get_public_key';

  @override
  String get label => 'Share public key';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46PingScope extends Nip46PermissionScope {
  const Nip46PingScope();

  @override
  String get wire => 'ping';

  @override
  String get label => 'Ping signer';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46SignEventScope extends Nip46PermissionScope {
  final int? kind;

  const Nip46SignEventScope([this.kind]);

  @override
  String get wire => kind == null ? 'sign_event' : 'sign_event:$kind';

  @override
  String get label => kind == null ? 'Sign any event kind' : 'Sign kind $kind';

  @override
  bool get isBroad => kind == null;

  @override
  Map<String, Object?> toJson() => {'type': 'sign_event', 'kind': kind};
}

final class Nip46Nip04EncryptScope extends Nip46PermissionScope {
  const Nip46Nip04EncryptScope();

  @override
  String get wire => 'nip04_encrypt';

  @override
  String get label => 'NIP-04 encrypt';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46Nip04DecryptScope extends Nip46PermissionScope {
  const Nip46Nip04DecryptScope();

  @override
  String get wire => 'nip04_decrypt';

  @override
  String get label => 'NIP-04 decrypt';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46Nip44EncryptScope extends Nip46PermissionScope {
  const Nip46Nip44EncryptScope();

  @override
  String get wire => 'nip44_encrypt';

  @override
  String get label => 'NIP-44 encrypt';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46Nip44DecryptScope extends Nip46PermissionScope {
  const Nip46Nip44DecryptScope();

  @override
  String get wire => 'nip44_decrypt';

  @override
  String get label => 'NIP-44 decrypt';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46DecryptZapEventScope extends Nip46PermissionScope {
  const Nip46DecryptZapEventScope();

  @override
  String get wire => 'decrypt_zap_event';

  @override
  String get label => 'Decrypt zap event';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46SwitchRelaysScope extends Nip46PermissionScope {
  const Nip46SwitchRelaysScope();

  @override
  String get wire => 'switch_relays';

  @override
  String get label => 'Switch relays';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46GetRelaysScope extends Nip46PermissionScope {
  const Nip46GetRelaysScope();

  @override
  String get wire => 'get_relays';

  @override
  String get label => 'Get relays';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip46UnsupportedScope extends Nip46PermissionScope {
  final String value;

  const Nip46UnsupportedScope(this.value);

  @override
  String get wire => value;

  @override
  String get label => 'Unsupported: $value';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': 'unsupported', 'wire': value};
}

extension Nip46PermissionScopeMatching on Nip46PermissionScope {
  bool matches(Nip46PermissionScope requested) {
    if (this is Nip46SignEventScope && requested is Nip46SignEventScope) {
      final grantKind = (this as Nip46SignEventScope).kind;
      return grantKind == null || grantKind == requested.kind;
    }
    // NIP-04/NIP-44 decrypt grants satisfy decrypt_zap_event (same cross-scope rule as NIP-55).
    if (this is Nip46Nip04DecryptScope && requested is Nip46DecryptZapEventScope) {
      return true;
    }
    if (this is Nip46Nip44DecryptScope && requested is Nip46DecryptZapEventScope) {
      return true;
    }
    return runtimeType == requested.runtimeType;
  }
}
