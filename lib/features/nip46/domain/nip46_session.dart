import 'nip46_permission_grant.dart';
import 'nip46_permission_scope.dart';

enum Nip46SessionStatus { pending, active, revoked, disconnected }

/// Which side started the connection: Symudol with a `bunker://` token, or
/// the client with a `nostrconnect://` one. The connect reply differs.
enum Nip46ConnectionInitiator { bunker, nostrconnect }

class Nip46Session {
  final String id;
  final String clientPubkey;
  final String remoteSignerPubkey;
  // Session private key stored here; secured via flutter_secure_storage in the store.
  final String remoteSignerPrivkey;
  final List<String> relays;
  // Display hints only — never used for authorization.
  final String? clientName;
  final String? clientUrl;
  final String? clientImage;
  /// What the client asked for at connect: shown on the connect approval,
  /// and saved as grants only if the user approves with a timeframe (#28).
  final List<Nip46PermissionScope> requestedScopes;

  /// The user's remembered decisions for this client (#28).
  final List<Nip46PermissionGrant> grants;
  final Nip46SessionStatus status;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? connectedAt;
  // Single-use secret; nulled after the first successful connect verification.
  final String? pendingSecret;
  // True if the client's first request used NIP-04 encryption; we respond in kind.
  final bool usesNip04;
  // Sessions stored before this field existed read as bunker.
  final Nip46ConnectionInitiator initiatedBy;

  const Nip46Session({
    required this.id,
    required this.clientPubkey,
    required this.remoteSignerPubkey,
    required this.remoteSignerPrivkey,
    required this.relays,
    this.clientName,
    this.clientUrl,
    this.clientImage,
    this.requestedScopes = const [],
    this.grants = const [],
    required this.status,
    required this.createdAt,
    this.lastUsedAt,
    this.connectedAt,
    this.pendingSecret,
    this.usesNip04 = false,
    this.initiatedBy = Nip46ConnectionInitiator.bunker,
  });

  Nip46Session copyWith({
    String? clientPubkey,
    String? remoteSignerPubkey,
    String? remoteSignerPrivkey,
    List<String>? relays,
    String? clientName,
    String? clientUrl,
    String? clientImage,
    List<Nip46PermissionScope>? requestedScopes,
    List<Nip46PermissionGrant>? grants,
    Nip46SessionStatus? status,
    DateTime? lastUsedAt,
    DateTime? connectedAt,
    Object? pendingSecret = _sentinel,
    bool? usesNip04,
  }) {
    return Nip46Session(
      id: id,
      clientPubkey: clientPubkey ?? this.clientPubkey,
      remoteSignerPubkey: remoteSignerPubkey ?? this.remoteSignerPubkey,
      remoteSignerPrivkey: remoteSignerPrivkey ?? this.remoteSignerPrivkey,
      relays: relays ?? this.relays,
      clientName: clientName ?? this.clientName,
      clientUrl: clientUrl ?? this.clientUrl,
      clientImage: clientImage ?? this.clientImage,
      requestedScopes: requestedScopes ?? this.requestedScopes,
      grants: grants ?? this.grants,
      status: status ?? this.status,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      pendingSecret:
          pendingSecret == _sentinel ? this.pendingSecret : pendingSecret as String?,
      usesNip04: usesNip04 ?? this.usesNip04,
      initiatedBy: initiatedBy,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'clientPubkey': clientPubkey,
    'remoteSignerPubkey': remoteSignerPubkey,
    'remoteSignerPrivkey': remoteSignerPrivkey,
    'relays': relays,
    'clientName': clientName,
    'clientUrl': clientUrl,
    'clientImage': clientImage,
    'requestedScopes': requestedScopes.map((s) => s.toJson()).toList(),
    'grants': grants.map((g) => g.toJson()).toList(),
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'connectedAt': connectedAt?.toIso8601String(),
    'pendingSecret': pendingSecret,
    'usesNip04': usesNip04,
    'initiatedBy': initiatedBy.name,
  };

  factory Nip46Session.fromJson(Map<String, Object?> json) {
    final rawRelays = json['relays'];
    final relays = rawRelays is List ? rawRelays.cast<String>() : <String>[];

    final status = Nip46SessionStatus.values.byName(json['status'] as String);
    // Before #28, `grantedScopes` held the requested scopes while a session
    // waited for approval, and was always saved empty on approval: it holds
    // no decisions to keep.
    final legacyScopes = status == Nip46SessionStatus.pending
        ? _scopes(json['grantedScopes'])
        : const <Nip46PermissionScope>[];
    final rawGrants = json['grants'];

    return Nip46Session(
      id: json['id'] as String,
      clientPubkey: json['clientPubkey'] as String,
      remoteSignerPubkey: json['remoteSignerPubkey'] as String,
      remoteSignerPrivkey: json['remoteSignerPrivkey'] as String,
      relays: relays,
      clientName: json['clientName'] as String?,
      clientUrl: json['clientUrl'] as String?,
      clientImage: json['clientImage'] as String?,
      requestedScopes: json.containsKey('requestedScopes')
          ? _scopes(json['requestedScopes'])
          : legacyScopes,
      grants: [
        if (rawGrants is List)
          for (final raw in rawGrants)
            if (raw is Map) ?Nip46PermissionGrant.fromJson(raw.cast()),
      ],
      status: status,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'] as String)
          : null,
      pendingSecret: json['pendingSecret'] as String?,
      usesNip04: json['usesNip04'] as bool? ?? false,
      initiatedBy: Nip46ConnectionInitiator.values.asNameMap()[json['initiatedBy']] ??
          Nip46ConnectionInitiator.bunker,
    );
  }
}

List<Nip46PermissionScope> _scopes(Object? raw) => [
  if (raw is List)
    for (final scope in raw)
      if (scope is Map) Nip46PermissionScope.fromJson(scope.cast()),
];

// Sentinel for copyWith pendingSecret to distinguish "not passed" from "null".
const Object _sentinel = Object();
