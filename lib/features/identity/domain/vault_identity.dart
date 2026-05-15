enum IdentityOrigin {
  generated,
  imported,
}

class VaultIdentity {
  final String localId;
  final String publicKey;
  final String? displayName;
  final bool isActive;
  final DateTime createdAt;
  final IdentityOrigin origin;

  const VaultIdentity({
    required this.localId,
    required this.publicKey,
    this.displayName,
    this.isActive = true,
    required this.createdAt,
    required this.origin,
  });

  Map<String, dynamic> toJson() {
    return {
      'localId': localId,
      'publicKey': publicKey,
      'displayName': displayName,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'origin': origin.name,
    };
  }

  factory VaultIdentity.fromJson(Map<String, dynamic> json) {
    return VaultIdentity(
      localId: json['localId'] as String,
      publicKey: json['publicKey'] as String,
      displayName: json['displayName'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      origin: IdentityOrigin.values.byName(json['origin'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultIdentity &&
          runtimeType == other.runtimeType &&
          publicKey == other.publicKey;

  @override
  int get hashCode => publicKey.hashCode;

  VaultIdentity copyWith({
    String? localId,
    String? publicKey,
    String? displayName,
    bool? isActive,
    DateTime? createdAt,
    IdentityOrigin? origin,
  }) {
    return VaultIdentity(
      localId: localId ?? this.localId,
      publicKey: publicKey ?? this.publicKey,
      displayName: displayName ?? this.displayName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      origin: origin ?? this.origin,
    );
  }
}
