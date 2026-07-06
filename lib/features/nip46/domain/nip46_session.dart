import 'nip46_permission_scope.dart';

enum Nip46SessionStatus { pending, active, revoked, disconnected }

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
  final List<Nip46PermissionScope> grantedScopes;
  final Nip46SessionStatus status;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? connectedAt;
  // Single-use secret; nulled after the first successful connect verification.
  final String? pendingSecret;
  // True if the client's first request used NIP-04 encryption; we respond in kind.
  final bool usesNip04;

  const Nip46Session({
    required this.id,
    required this.clientPubkey,
    required this.remoteSignerPubkey,
    required this.remoteSignerPrivkey,
    required this.relays,
    this.clientName,
    this.clientUrl,
    this.clientImage,
    required this.grantedScopes,
    required this.status,
    required this.createdAt,
    this.lastUsedAt,
    this.connectedAt,
    this.pendingSecret,
    this.usesNip04 = false,
  });

  Nip46Session copyWith({
    String? clientPubkey,
    String? remoteSignerPubkey,
    String? remoteSignerPrivkey,
    List<String>? relays,
    String? clientName,
    String? clientUrl,
    String? clientImage,
    List<Nip46PermissionScope>? grantedScopes,
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
      grantedScopes: grantedScopes ?? this.grantedScopes,
      status: status ?? this.status,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      pendingSecret:
          pendingSecret == _sentinel ? this.pendingSecret : pendingSecret as String?,
      usesNip04: usesNip04 ?? this.usesNip04,
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
    'grantedScopes': grantedScopes.map((s) => s.toJson()).toList(),
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'connectedAt': connectedAt?.toIso8601String(),
    'pendingSecret': pendingSecret,
    'usesNip04': usesNip04,
  };

  factory Nip46Session.fromJson(Map<String, Object?> json) {
    final rawRelays = json['relays'];
    final relays = rawRelays is List ? rawRelays.cast<String>() : <String>[];

    final rawScopes = json['grantedScopes'];
    final scopes = <Nip46PermissionScope>[];
    if (rawScopes is List) {
      for (final raw in rawScopes) {
        if (raw is Map) {
          scopes.add(Nip46PermissionScope.fromJson(raw.cast()));
        }
      }
    }

    return Nip46Session(
      id: json['id'] as String,
      clientPubkey: json['clientPubkey'] as String,
      remoteSignerPubkey: json['remoteSignerPubkey'] as String,
      remoteSignerPrivkey: json['remoteSignerPrivkey'] as String,
      relays: relays,
      clientName: json['clientName'] as String?,
      clientUrl: json['clientUrl'] as String?,
      clientImage: json['clientImage'] as String?,
      grantedScopes: scopes,
      status: Nip46SessionStatus.values.byName(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'] as String)
          : null,
      pendingSecret: json['pendingSecret'] as String?,
      usesNip04: json['usesNip04'] as bool? ?? false,
    );
  }
}

// Sentinel for copyWith pendingSecret to distinguish "not passed" from "null".
const Object _sentinel = Object();
