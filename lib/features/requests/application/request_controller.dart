import 'package:android_diogel/features/requests/domain/request_failure.dart';
import 'package:android_diogel/features/requests/domain/request_provenance.dart';
import 'package:android_diogel/features/requests/domain/request_state.dart';
import 'package:android_diogel/features/requests/domain/request_trust_status.dart';
import 'package:android_diogel/features/requests/domain/signed_request_result.dart';
import 'package:android_diogel/features/requests/domain/signer_service.dart';
import 'package:android_diogel/features/requests/domain/signing_action_type.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

class RequestController extends StateNotifier<RequestState> {
  final VaultController _vaultController;
  final SignerService _signerService;

  RequestController(this._vaultController, this._signerService)
      : super(const RequestState(requests: []));

  RequestFailure? get failure => state.failure;

  /// Exposes the current pending request, if any.
  SigningRequest? get pendingRequest {
    try {
      return state.requests.firstWhere(
        (r) => r.status == SigningRequestStatus.pending,
      );
    } catch (_) {
      return null;
    }
  }

  /// Accepts a new request into the pending state.
  Future<void> acceptRequest(SigningRequest request) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    // In-memory implementation for now.
    final updatedRequests = List<SigningRequest>.from(state.requests)..add(request);
    state = state.copyWith(requests: updatedRequests, isLoading: false);
  }

  /// Rejects a request, marking it as rejected and clearing it from pending.
  Future<void> rejectRequest(String requestId) async {
    state = state.copyWith(isLoading: true);
    final updatedRequests = state.requests.map((r) {
      if (r.id == requestId) {
        return r.copyWith(status: SigningRequestStatus.rejected);
      }
      return r;
    }).toList();
    state = state.copyWith(requests: updatedRequests, isLoading: false);
  }

  /// Approves a request through the signer service.
  /// 
  /// Blocks approval if the vault is locked or no active identity exists.
  Future<void> approveRequest(String requestId) async {
    state = state.copyWith(isLoading: true, clearFailure: true);

    final vaultState = _vaultController.state.vaultState;
    final activeIdentity = _vaultController.state.activeIdentity;

    if (vaultState is! VaultUnlocked) {
      state = state.copyWith(
        isLoading: false,
        failure: const RequestFailure('Approval blocked: Vault is locked'),
      );
      return;
    }

    if (activeIdentity == null) {
      state = state.copyWith(
        isLoading: false,
        failure: const RequestFailure('Approval failed: No active identity'),
      );
      return;
    }

    final request = _findRequest(requestId);
    if (request == null) {
      state = state.copyWith(
        isLoading: false,
        failure: const RequestFailure('Approval failed: Request no longer exists'),
      );
      return;
    }

    if (request.targetIdentityPublicKey != activeIdentity.publicKey ||
        request.targetIdentityLocalId != activeIdentity.localId) {
      state = state.copyWith(
        isLoading: false,
        failure: const RequestFailure('Approval blocked: Identity mismatch'),
      );
      return;
    }

    try {
      final result = await _signerService.sign(request);

      if (result is SignedRequestFailure) {
        _markRequestFailed(requestId, result.failure);
        return;
      }

      // On success
      final updatedRequests = state.requests.map((r) {
        if (r.id == requestId) {
          return r.copyWith(status: SigningRequestStatus.approved);
        }
        return r;
      }).toList();

      state = state.copyWith(requests: updatedRequests, isLoading: false);
    } catch (error) {
      _markRequestFailed(
        requestId,
        RequestFailure('Approval failed: Unexpected error during signing', error),
      );
    }
  }

  void _markRequestFailed(String requestId, RequestFailure failure) {
    final updatedRequests = state.requests.map((r) {
      if (r.id == requestId) {
        return r.copyWith(status: SigningRequestStatus.failed);
      }
      return r;
    }).toList();
    state = state.copyWith(
      requests: updatedRequests,
      isLoading: false,
      failure: failure,
    );
  }

  void clearFailure() {
    state = state.copyWith(clearFailure: true);
  }

  SigningRequest? _findRequest(String requestId) {
    for (final request in state.requests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  /// Injects a demo request for development/demo purposes.
  /// 
  /// This should only be used in development or demo modes.
  Future<void> injectDemoRequest() async {
    final activeIdentity = _vaultController.state.activeIdentity;
    if (activeIdentity == null) {
      state = state.copyWith(
        failure: const RequestFailure('Cannot inject demo request: No active identity'),
      );
      return;
    }

    final demoRequest = SigningRequest(
      id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      provenance: const RequestProvenance(
        sourceDisplayName: 'Demo DApp',
        sourceIdentifier: 'https://demo.example.com',
        trustStatus: RequestTrustStatus.unknown,
      ),
      actionType: SigningActionType.signEvent,
      eventKind: 1,
      eventPayload: {
        'content': 'This is a demo request for development purposes.',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'tags': [],
        'pubkey': activeIdentity.publicKey,
      },
      targetIdentityPublicKey: activeIdentity.publicKey,
      targetIdentityLocalId: activeIdentity.localId,
      createdAt: DateTime.now(),
      status: SigningRequestStatus.pending,
    );

    await acceptRequest(demoRequest);
  }
}
