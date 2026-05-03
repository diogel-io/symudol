sealed class Nip55PermissionScope {
  const Nip55PermissionScope();

  String get wire;
  String get label;
  bool get isBroad => false;
  bool get isSensitive => false;

  Map<String, Object?> toJson();

  static Nip55PermissionScope fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'get_public_key' => const GetPublicKeyScope(),
      'sign_event' => SignEventScope(json['kind'] as int?),
      'nip44_encrypt' => const Nip44EncryptScope(),
      'nip44_decrypt' => const Nip44DecryptScope(),
      'nip04_encrypt' => const Nip04EncryptScope(),
      'nip04_decrypt' => const Nip04DecryptScope(),
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
  const Nip44EncryptScope();

  @override
  String get wire => 'nip44_encrypt';

  @override
  String get label => 'NIP-44 encrypt';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip44DecryptScope extends Nip55PermissionScope {
  const Nip44DecryptScope();

  @override
  String get wire => 'nip44_decrypt';

  @override
  String get label => 'NIP-44 decrypt';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip04EncryptScope extends Nip55PermissionScope {
  const Nip04EncryptScope();

  @override
  String get wire => 'nip04_encrypt';

  @override
  String get label => 'NIP-04 encrypt';

  @override
  Map<String, Object?> toJson() => {'type': wire};
}

final class Nip04DecryptScope extends Nip55PermissionScope {
  const Nip04DecryptScope();

  @override
  String get wire => 'nip04_decrypt';

  @override
  String get label => 'NIP-04 decrypt';

  @override
  bool get isSensitive => true;

  @override
  Map<String, Object?> toJson() => {'type': wire};
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
    return runtimeType == requested.runtimeType;
  }
}
