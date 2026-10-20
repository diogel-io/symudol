class Nip55ClientIdentity {
  final String? packageName;
  final String? appLabel;
  final String? certificateSha256;
  final String? referrer;
  final bool provenanceVerified;

  const Nip55ClientIdentity({
    this.packageName,
    this.appLabel,
    this.certificateSha256,
    this.referrer,
    this.provenanceVerified = false,
  });

  /// Whether a decision for this caller can be remembered: it needs the
  /// package and the signing certificate, since a grant without the
  /// certificate would match no caller (REQ-NIP55-010, #17).
  bool get canBeRemembered => packageName != null && certificateSha256 != null;

  String get displayName {
    final label = appLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final package = packageName?.trim();
    if (package != null && package.isNotEmpty) return package;
    final referrerValue = referrer?.trim();
    if (referrerValue != null && referrerValue.isNotEmpty) return referrerValue;
    return 'Unknown Android caller';
  }

  Map<String, Object?> toJson() {
    return {
      'packageName': packageName,
      'appLabel': appLabel,
      'certificateSha256': certificateSha256,
      'referrer': referrer,
      'provenanceVerified': provenanceVerified,
    };
  }

  factory Nip55ClientIdentity.fromJson(Map<String, Object?> json) {
    return Nip55ClientIdentity(
      packageName: json['packageName'] as String?,
      appLabel: json['appLabel'] as String?,
      certificateSha256: json['certificateSha256'] as String?,
      referrer: json['referrer'] as String?,
      provenanceVerified: json['provenanceVerified'] as bool? ?? false,
    );
  }
}
