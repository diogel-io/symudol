import 'request_provenance.dart';
import 'signing_action_type.dart';
import 'signing_request_status.dart';

class SigningRequest {
  final String id;
  final RequestProvenance provenance;
  final SigningActionType actionType;
  final int eventKind;
  final Map<String, Object?> eventPayload;
  final String targetIdentityPublicKey;
  final String targetIdentityLocalId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final SigningRequestStatus status;

  const SigningRequest({
    required this.id,
    required this.provenance,
    required this.actionType,
    required this.eventKind,
    required this.eventPayload,
    required this.targetIdentityPublicKey,
    required this.targetIdentityLocalId,
    required this.createdAt,
    this.expiresAt,
    required this.status,
  });

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'provenance': provenance.toJson(),
      'actionType': actionType.name,
      'eventKind': eventKind,
      'eventPayload': eventPayload,
      'targetIdentityPublicKey': targetIdentityPublicKey,
      'targetIdentityLocalId': targetIdentityLocalId,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'status': status.name,
    };
  }

  factory SigningRequest.fromJson(Map<String, Object?> json) {
    return SigningRequest(
      id: json['id'] as String,
      provenance: RequestProvenance.fromJson(
        (json['provenance'] as Map).cast<String, Object?>(),
      ),
      actionType: SigningActionType.values.byName(json['actionType'] as String),
      eventKind: json['eventKind'] as int,
      eventPayload: (json['eventPayload'] as Map).cast<String, Object?>(),
      targetIdentityPublicKey: json['targetIdentityPublicKey'] as String,
      targetIdentityLocalId: json['targetIdentityLocalId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt'] as String) : null,
      status: SigningRequestStatus.values.byName(json['status'] as String),
    );
  }

  SigningRequest copyWith({
    String? id,
    RequestProvenance? provenance,
    SigningActionType? actionType,
    int? eventKind,
    Map<String, Object?>? eventPayload,
    String? targetIdentityPublicKey,
    String? targetIdentityLocalId,
    DateTime? createdAt,
    DateTime? expiresAt,
    SigningRequestStatus? status,
  }) {
    return SigningRequest(
      id: id ?? this.id,
      provenance: provenance ?? this.provenance,
      actionType: actionType ?? this.actionType,
      eventKind: eventKind ?? this.eventKind,
      eventPayload: eventPayload ?? this.eventPayload,
      targetIdentityPublicKey: targetIdentityPublicKey ?? this.targetIdentityPublicKey,
      targetIdentityLocalId: targetIdentityLocalId ?? this.targetIdentityLocalId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
    );
  }
}
