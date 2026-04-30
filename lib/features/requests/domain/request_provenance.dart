import 'request_trust_status.dart';

class RequestProvenance {
  final String sourceDisplayName;
  final String? sourceIdentifier; // e.g. origin URL
  final RequestTrustStatus trustStatus;

  const RequestProvenance({
    required this.sourceDisplayName,
    this.sourceIdentifier,
    required this.trustStatus,
  });

  Map<String, dynamic> toJson() {
    return {
      'sourceDisplayName': sourceDisplayName,
      'sourceIdentifier': sourceIdentifier,
      'trustStatus': trustStatus.name,
    };
  }

  factory RequestProvenance.fromJson(Map<String, dynamic> json) {
    return RequestProvenance(
      sourceDisplayName: json['sourceDisplayName'] as String,
      sourceIdentifier: json['sourceIdentifier'] as String?,
      trustStatus: RequestTrustStatus.values.byName(json['trustStatus'] as String),
    );
  }
}
