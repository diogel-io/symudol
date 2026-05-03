import 'nip55_permission_decision.dart';
import 'nip55_permission_scope.dart';

class Nip55PermissionGrant {
  final String id;
  final String identityPubkey;
  final String? packageName;
  final String? certificateSha256;
  final Nip55PermissionScope scope;
  final Nip55PermissionDecision decision;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final String? userLabel;

  const Nip55PermissionGrant({
    required this.id,
    required this.identityPubkey,
    this.packageName,
    this.certificateSha256,
    required this.scope,
    required this.decision,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.userLabel,
  });

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now());
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'identityPubkey': identityPubkey,
      'packageName': packageName,
      'certificateSha256': certificateSha256,
      'scope': scope.toJson(),
      'decision': decision.name,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'userLabel': userLabel,
    };
  }

  Nip55PermissionGrant copyWith({DateTime? lastUsedAt}) {
    return Nip55PermissionGrant(
      id: id,
      identityPubkey: identityPubkey,
      packageName: packageName,
      certificateSha256: certificateSha256,
      scope: scope,
      decision: decision,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      expiresAt: expiresAt,
      userLabel: userLabel,
    );
  }

  factory Nip55PermissionGrant.fromJson(Map<String, Object?> json) {
    return Nip55PermissionGrant(
      id: json['id'] as String,
      identityPubkey: json['identityPubkey'] as String,
      packageName: json['packageName'] as String?,
      certificateSha256: json['certificateSha256'] as String?,
      scope: Nip55PermissionScope.fromJson(
        (json['scope'] as Map).cast<String, Object?>(),
      ),
      decision: Nip55PermissionDecision.values.byName(
        json['decision'] as String,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      userLabel: json['userLabel'] as String?,
    );
  }
}
