import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

import '../data/nip55_method_channel_gateway.dart';
import '../domain/nip55_failure.dart';
import '../domain/nip55_incoming_request.dart';
import '../domain/nip55_intent_parser.dart';
import '../domain/nip55_method.dart';
import '../domain/nip55_response_builder.dart';
import 'nip55_request_mapper.dart';

class Nip55State {
  final Nip55IncomingRequest? pendingIncoming;
  final String? pendingSigningRequestId;
  final Nip55IncomingRequest? pendingPublicKeyRequest;
  final bool isLoading;
  final Nip55Failure? failure;
  final String? lastSuccessMessage;

  const Nip55State({
    this.pendingIncoming,
    this.pendingSigningRequestId,
    this.pendingPublicKeyRequest,
    this.isLoading = false,
    this.failure,
    this.lastSuccessMessage,
  });

  bool get hasPendingExternalRequest =>
      pendingIncoming != null ||
      pendingSigningRequestId != null ||
      pendingPublicKeyRequest != null;

  bool get isWaitingForUnlock =>
      pendingIncoming != null &&
      pendingSigningRequestId == null &&
      pendingPublicKeyRequest == null;

  Nip55State copyWith({
    Nip55IncomingRequest? pendingIncoming,
    String? pendingSigningRequestId,
    Nip55IncomingRequest? pendingPublicKeyRequest,
    bool? isLoading,
    Nip55Failure? failure,
    String? lastSuccessMessage,
    bool clearPendingIncoming = false,
    bool clearPendingSigningRequestId = false,
    bool clearPendingPublicKeyRequest = false,
    bool clearFailure = false,
    bool clearSuccess = false,
  }) {
    return Nip55State(
      pendingIncoming: clearPendingIncoming
          ? null
          : (pendingIncoming ?? this.pendingIncoming),
      pendingSigningRequestId: clearPendingSigningRequestId
          ? null
          : (pendingSigningRequestId ?? this.pendingSigningRequestId),
      pendingPublicKeyRequest: clearPendingPublicKeyRequest
          ? null
          : (pendingPublicKeyRequest ?? this.pendingPublicKeyRequest),
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
      lastSuccessMessage: clearSuccess
          ? null
          : (lastSuccessMessage ?? this.lastSuccessMessage),
    );
  }
}

class Nip55Controller extends StateNotifier<Nip55State> {
  final Nip55Gateway _gateway;
  final Nip55IntentParser _parser;
  final Nip55RequestMapper _mapper;
  final Nip55ResponseBuilder _responseBuilder;
  final VaultController _vaultController;
  final RequestController _requestController;

  Nip55Controller({
    required Nip55Gateway gateway,
    required VaultController vaultController,
    required RequestController requestController,
    Nip55IntentParser parser = const Nip55IntentParser(),
    Nip55RequestMapper mapper = const Nip55RequestMapper(),
    Nip55ResponseBuilder responseBuilder = const Nip55ResponseBuilder(),
  }) : _gateway = gateway,
       _vaultController = vaultController,
       _requestController = requestController,
       _parser = parser,
       _mapper = mapper,
       _responseBuilder = responseBuilder,
       super(const Nip55State()) {
    _gateway.setIncomingIntentHandler((raw) => handleRawIntent(raw));
  }

  Future<void> consumePendingNativeIntent() async {
    final latest = await _gateway.consumeLatestNip55Intent();
    if (latest != null) {
      await handleRawIntent(latest);
      return;
    }

    final initial = await _gateway.getInitialNip55Intent();
    if (initial != null) {
      await handleRawIntent(initial);
    }
  }

  Future<void> handleRawIntent(Map<String, Object?> raw) async {
    Nip55IncomingRequest? incoming;
    if (state.hasPendingExternalRequest) {
      final busyRequest = _safeParseForRejection(raw);
      if (busyRequest == null) return;
      await _gateway.rejectNip55Intent(
        requestToken: busyRequest.requestToken,
        error: 'Diogel is already reviewing another NIP-55 request',
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearFailure: true,
      clearSuccess: true,
    );
    try {
      incoming = _parser.parse(raw);
      if (incoming.method == Nip55Method.getPublicKey) {
        await _handleGetPublicKey(incoming);
      } else if (incoming.method == Nip55Method.signEvent) {
        await _handleSignEvent(incoming);
      }
    } on Nip55ParseException catch (error) {
      state = state.copyWith(
        isLoading: false,
        failure: Nip55Failure(error.message, error),
      );
      final requestToken = raw['requestToken'] as String?;
      if (requestToken != null) {
        await _gateway.rejectNip55Intent(
          requestToken: requestToken,
          error: error.message,
        );
      }
    } on Nip55Failure catch (error) {
      state = state.copyWith(isLoading: false, failure: error);
      if (incoming == null || !_isWaitingForUnlockFailure(error)) {
        final requestToken =
            incoming?.requestToken ?? raw['requestToken'] as String?;
        if (requestToken != null) {
          await _gateway.rejectNip55Intent(
            requestToken: requestToken,
            error: error.message,
          );
        }
      }
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        failure: Nip55Failure('Unable to handle NIP-55 request', error),
      );
      final requestToken =
          incoming?.requestToken ?? raw['requestToken'] as String?;
      if (requestToken != null) {
        await _gateway.rejectNip55Intent(
          requestToken: requestToken,
          error: 'Unable to handle NIP-55 request',
        );
      }
    }
  }

  Future<void> resumePendingAfterUnlock() async {
    final incoming = state.pendingIncoming;
    if (incoming == null || !state.isWaitingForUnlock || state.isLoading) {
      return;
    }
    if (_vaultController.state.vaultState is! VaultUnlocked) return;

    state = state.copyWith(
      isLoading: true,
      clearFailure: true,
      clearSuccess: true,
    );
    try {
      if (incoming.method == Nip55Method.getPublicKey) {
        await _handleGetPublicKey(incoming);
      } else if (incoming.method == Nip55Method.signEvent) {
        await _handleSignEvent(incoming);
      }
    } on Nip55Failure catch (error) {
      state = state.copyWith(isLoading: false, failure: error);
      await _gateway.rejectNip55Intent(
        requestToken: incoming.requestToken,
        error: error.message,
      );
      state = state.copyWith(clearPendingIncoming: true);
    }
  }

  Future<void> _handleGetPublicKey(Nip55IncomingRequest incoming) async {
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked) {
      state = state.copyWith(
        isLoading: false,
        pendingIncoming: incoming,
        failure: const Nip55Failure(
          'Unlock Diogel and select an identity before sharing a public key.',
        ),
      );
      throw const Nip55Failure(
        'Unlock Diogel and select an identity before sharing a public key.',
      );
    }
    if (activeIdentity == null) {
      throw const Nip55Failure(
        'Select an identity before sharing a public key.',
      );
    }

    state = state.copyWith(
      isLoading: false,
      pendingIncoming: incoming,
      pendingPublicKeyRequest: incoming,
    );
  }

  Future<void> _handleSignEvent(Nip55IncomingRequest incoming) async {
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked) {
      state = state.copyWith(
        isLoading: false,
        pendingIncoming: incoming,
        failure: const Nip55Failure(
          'Unlock Diogel and select an identity before signing.',
        ),
      );
      throw const Nip55Failure(
        'Unlock Diogel and select an identity before signing.',
      );
    }
    if (activeIdentity == null) {
      throw const Nip55Failure('Select an identity before signing.');
    }

    final signingRequest = _mapper.mapSignEvent(
      incoming: incoming,
      activeIdentity: activeIdentity,
    );
    await _requestController.acceptRequest(signingRequest);
    state = state.copyWith(
      isLoading: false,
      pendingIncoming: incoming,
      pendingSigningRequestId: signingRequest.id,
    );
  }

  Future<void> approvePublicKeyRequest() async {
    final request = state.pendingPublicKeyRequest;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (request == null || activeIdentity == null) return;

    await _gateway.completeNip55Intent(
      requestToken: request.requestToken,
      extras: _responseBuilder.getPublicKeyExtras(activeIdentity),
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingPublicKeyRequest: true,
      lastSuccessMessage: 'Public key shared with requesting Android app.',
    );
  }

  Future<void> rejectPublicKeyRequest() async {
    if (state.pendingPublicKeyRequest == null) return;
    await _gateway.rejectNip55Intent(
      requestToken: state.pendingPublicKeyRequest!.requestToken,
      error: 'User rejected public key request',
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingPublicKeyRequest: true,
    );
  }

  Future<void> completeApprovedSigningRequest(String requestId) async {
    if (state.pendingSigningRequestId != requestId) return;
    final incoming = state.pendingIncoming;
    final signedEvent = _requestController.state.signedEvents[requestId];
    if (incoming == null || signedEvent == null) return;

    await _gateway.completeNip55Intent(
      requestToken: incoming.requestToken,
      extras: _responseBuilder.signEventExtras(
        incoming: incoming,
        signedEvent: signedEvent,
      ),
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingSigningRequestId: true,
      lastSuccessMessage:
          'Event signed locally and returned to requesting Android app.',
    );
  }

  Future<void> rejectSigningRequest(String requestId) async {
    if (state.pendingSigningRequestId != requestId) return;
    final incoming = state.pendingIncoming;
    if (incoming == null) return;
    await _gateway.rejectNip55Intent(
      requestToken: incoming.requestToken,
      error: 'User rejected signing request',
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingSigningRequestId: true,
    );
  }

  void clearMessages() {
    state = state.copyWith(clearFailure: true, clearSuccess: true);
  }

  Nip55IncomingRequest? _safeParseForRejection(Map<String, Object?> raw) {
    try {
      return _parser.parse(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isWaitingForUnlockFailure(Nip55Failure error) {
    return error.message.startsWith('Unlock Diogel');
  }
}
