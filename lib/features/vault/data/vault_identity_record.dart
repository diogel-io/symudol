import '../../identity/domain/vault_identity.dart';

class VaultIdentityRecord {
  final int version;
  final String identityId;
  final String publicKey;
  final String secretPayload;
  final IdentityOrigin origin;
  final DateTime createdAt;

  const VaultIdentityRecord({
    this.version = 1,
    required this.identityId,
    required this.publicKey,
    required this.secretPayload,
    required this.origin,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'identityId': identityId,
      'publicKey': publicKey,
      'secretPayload': secretPayload,
      'origin': origin.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VaultIdentityRecord.fromJson(Map<String, dynamic> json) {
    return VaultIdentityRecord(
      version: json['version'] as int,
      identityId: json['identityId'] as String,
      publicKey: json['publicKey'] as String,
      secretPayload: json['secretPayload'] as String,
      origin: IdentityOrigin.values.byName(json['origin'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  VaultIdentity toVaultIdentity() {
    return VaultIdentity(
      localId: identityId,
      publicKey: publicKey,
      createdAt: createdAt,
      origin: origin,
    );
  }
}
