import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';

import 'nip46_permission_scope.dart';

/// A remembered NIP-46 decision: allow or reject one scope for one session's
/// client, under the identity active when it was made (diogel-io/symudol#28).
///
/// Shares NIP-55's decision type, and its rules: see [isRememberable].
class Nip46PermissionGrant {
  final Nip46PermissionScope scope;

  /// [Nip55PermissionDecision.allow] or [Nip55PermissionDecision.reject];
  /// never `ask`.
  final Nip55PermissionDecision decision;

  /// The identity the decision was made under. It only applies while that
  /// identity is active: a session serves whichever identity is.
  final String identityPubkey;
  final DateTime createdAt;

  /// Null for a decision kept until the session is revoked.
  final DateTime? expiresAt;

  const Nip46PermissionGrant({
    required this.scope,
    required this.decision,
    required this.identityPubkey,
    required this.createdAt,
    this.expiresAt,
  });

  /// Whether this grant may be kept. A broad allow (signing any event kind)
  /// never is, as for NIP-55 (diogel-io/symudol#5, #6): every such signature
  /// is reviewed. A broad reject is kept: refusing every kind is safe.
  bool get isRememberable =>
      !(decision == Nip55PermissionDecision.allow && scope.isBroad);

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(now);
  }

  Map<String, Object?> toJson() => {
    'scope': scope.toJson(),
    'decision': decision.name,
    'identityPubkey': identityPubkey,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
  };

  /// Null for a grant this version cannot use, which is then dropped.
  /// Never throws, so one bad stored grant cannot stop a session loading.
  static Nip46PermissionGrant? fromJson(Map<String, Object?> json) {
    final scope = json['scope'];
    final decision = Nip55PermissionDecision.values.asNameMap()[json['decision']];
    final identityPubkey = json['identityPubkey'];
    final rawCreatedAt = json['createdAt'];
    final createdAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt)
        : null;
    // Missing or null means kept until revoked. Anything else must parse: a
    // damaged expiry would otherwise make a timed grant permanent.
    final rawExpiry = json['expiresAt'];
    final expiresAt = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
    if (rawExpiry != null && expiresAt == null) return null;
    if (scope is! Map ||
        identityPubkey is! String ||
        createdAt == null ||
        (decision != Nip55PermissionDecision.allow &&
            decision != Nip55PermissionDecision.reject)) {
      return null;
    }
    final grant = Nip46PermissionGrant(
      scope: Nip46PermissionScope.fromJson(scope.cast()),
      decision: decision!,
      identityPubkey: identityPubkey,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
    return grant.isRememberable ? grant : null;
  }
}
