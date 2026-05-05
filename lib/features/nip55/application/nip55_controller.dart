import 'dart:async';
import 'dart:developer' as dev;
import 'package:android_diogel/app/utils/concurrency_utils.dart';
import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

import '../data/nip55_method_channel_gateway.dart';
import '../domain/nip55_approval_policy.dart';
import '../domain/nip55_client_permission.dart';
import '../domain/nip55_failure.dart';
import '../domain/nip55_incoming_request.dart';
import '../domain/nip55_intent_parser.dart';
import '../domain/nip55_method.dart';
import '../domain/nip55_payload.dart';
import '../domain/nip55_permission_decision.dart';
import '../domain/nip55_permission_scope.dart';
import '../domain/nip55_permission_store.dart';
import '../domain/nip55_response_builder.dart';
import 'nip55_request_mapper.dart';

class Nip55State {
  final Nip55IncomingRequest? pendingIncoming;
  final String? pendingSigningRequestId;
  final Nip55IncomingRequest? pendingPublicKeyRequest;
  final Nip55IncomingRequest? pendingCryptoRequest;
  final bool isLoading;
  final Nip55Failure? failure;
  final String? lastSuccessMessage;
  final DateTime? approvalSessionExpiresAt;

  const Nip55State({
    this.pendingIncoming,
    this.pendingSigningRequestId,
    this.pendingPublicKeyRequest,
    this.pendingCryptoRequest,
    this.isLoading = false,
    this.failure,
    this.lastSuccessMessage,
    this.approvalSessionExpiresAt,
  });

  bool get hasPendingExternalRequest =>
      isLoading ||
      pendingIncoming != null ||
      pendingSigningRequestId != null ||
      pendingPublicKeyRequest != null ||
      pendingCryptoRequest != null;

  bool get isWaitingForUnlock =>
      pendingIncoming != null &&
      pendingSigningRequestId == null &&
      pendingPublicKeyRequest == null &&
      pendingCryptoRequest == null;

  Nip55State copyWith({
    Nip55IncomingRequest? pendingIncoming,
    String? pendingSigningRequestId,
    Nip55IncomingRequest? pendingPublicKeyRequest,
    Nip55IncomingRequest? pendingCryptoRequest,
    bool? isLoading,
    Nip55Failure? failure,
    String? lastSuccessMessage,
    DateTime? approvalSessionExpiresAt,
    bool clearPendingIncoming = false,
    bool clearPendingSigningRequestId = false,
    bool clearPendingPublicKeyRequest = false,
    bool clearPendingCryptoRequest = false,
    bool clearFailure = false,
    bool clearSuccess = false,
    bool clearApprovalSession = false,
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
      pendingCryptoRequest: clearPendingCryptoRequest
          ? null
          : (pendingCryptoRequest ?? this.pendingCryptoRequest),
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
      lastSuccessMessage: clearSuccess
          ? null
          : (lastSuccessMessage ?? this.lastSuccessMessage),
      approvalSessionExpiresAt: clearApprovalSession
          ? null
          : (approvalSessionExpiresAt ?? this.approvalSessionExpiresAt),
    );
  }
}

class Nip55Controller extends StateNotifier<Nip55State> {
  final Nip55Gateway _gateway;
  final Nip55IntentParser _parser;
  final Nip55RequestMapper _mapper;
  final Nip55ResponseBuilder _responseBuilder;
  final Nip55PermissionStore? _permissionStore;
  final Nip55ApprovalPolicy _approvalPolicy;
  final VaultController _vaultController;
  final VaultService _vaultService;
  final RequestController _requestController;
  final Duration _pendingUnlockTimeout;
  final DateTime Function() _now;
  Timer? _pendingUnlockTimer;

  // Track concurrency synchronously to avoid races in async flows
  bool _isParsingIntent = false;

  Nip55Controller({
    required Nip55Gateway gateway,
    required VaultController vaultController,
    required VaultService vaultService,
    required RequestController requestController,
    Nip55IntentParser parser = const Nip55IntentParser(),
    Nip55RequestMapper mapper = const Nip55RequestMapper(),
    Nip55ResponseBuilder responseBuilder = const Nip55ResponseBuilder(),
    Nip55PermissionStore? permissionStore,
    Nip55ApprovalPolicy approvalPolicy = const Nip55ApprovalPolicy(),
    Duration pendingUnlockTimeout = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _gateway = gateway,
       _vaultController = vaultController,
       _vaultService = vaultService,
       _requestController = requestController,
       _parser = parser,
       _mapper = mapper,
       _responseBuilder = responseBuilder,
       _permissionStore = permissionStore,
       _approvalPolicy = approvalPolicy,
       _pendingUnlockTimeout = pendingUnlockTimeout,
       _now = now ?? DateTime.now,
       super(const Nip55State()) {
    _gateway.setIncomingIntentHandler((raw) => handleRawIntent(raw));
    _gateway.setProviderQueryHandler((raw) => handleProviderQuery(raw));
  }

  @override
  void dispose() {
    _pendingUnlockTimer?.cancel();
    super.dispose();
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
    // Check busy synchronously
    if (_isParsingIntent || state.hasPendingExternalRequest) {
      // Rejection parsing still happens in isolate (or sync in test) to avoid jank
      final busyRequest = _safeParseForRejection(raw);
      if (busyRequest == null) return;
      await _gateway.rejectNip55Intent(
        requestToken: busyRequest.requestToken,
        error: 'Diogel is already reviewing another NIP-55 request',
      );
      return;
    }

    _isParsingIntent = true;
    state = state.copyWith(
      isLoading: true,
      clearFailure: true,
      clearSuccess: true,
    );

    // The rest is async
    try {
      await _continueHandleRawIntent(raw);
    } finally {
      _isParsingIntent = false;
    }
  }

  Future<void> _continueHandleRawIntent(Map<String, Object?> raw) async {
    Nip55IncomingRequest? incoming;
    try {
      final parser = _parser;
      final parsedIncoming = await ConcurrencyUtils.runTask(
        () => parser.parse(raw),
      );
      incoming = parsedIncoming;
      if (parsedIncoming.method == Nip55Method.getPublicKey) {
        await _handleGetPublicKey(parsedIncoming);
      } else if (parsedIncoming.method == Nip55Method.signEvent) {
        await _handleSignEvent(parsedIncoming);
      } else {
        await _handleCryptoOperation(parsedIncoming);
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

  Future<Map<String, Object?>?> handleProviderQuery(
    Map<String, Object?> raw,
  ) async {
    if (state.hasPendingExternalRequest) return null;
    final parser = _parser;
    final incoming = parser.parse(raw);
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked ||
        activeIdentity == null) {
      return null;
    }
    if (!_matchesCurrentUser(incoming, activeIdentity.publicKey)) {
      return {'rejected': 'Requested account does not match active identity.'};
    }

    final decision = await _decide(incoming, activeIdentity.publicKey);
    if (decision is AutoReject) {
      await _markGrantUsed(decision.grant);
      return {'rejected': decision.reason};
    }
    if (decision is! AutoAllow || !_canUseApprovalSession(decision.grant)) {
      return null;
    }

    await _markGrantUsed(decision.grant);
    if (incoming.method == Nip55Method.getPublicKey) {
      return _responseBuilder.getPublicKeyExtras(
        activeIdentity,
        incoming: incoming,
      );
    }
    if (incoming.method == Nip55Method.signEvent) {
      final signingRequest = _mapper.mapSignEvent(
        incoming: incoming,
        activeIdentity: activeIdentity,
      );
      final draft = const NostrEventPayloadParser().parse(signingRequest);
      final signedEvent = await _vaultService.signNostrEvent(
        identityLocalId: activeIdentity.localId,
        draft: draft,
      );
      return _responseBuilder.signEventExtras(
        incoming: incoming,
        signedEvent: signedEvent,
      );
    }

    final result = await _cryptoResult(incoming, activeIdentity.localId);
    return _responseBuilder.operationResultExtras(
      incoming: incoming,
      result: result,
      clipboardLabel: _clipboardLabelFor(incoming),
    );
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
    _pendingUnlockTimer?.cancel();
    try {
      if (incoming.method == Nip55Method.getPublicKey) {
        await _handleGetPublicKey(incoming);
      } else if (incoming.method == Nip55Method.signEvent) {
        await _handleSignEvent(incoming);
      } else {
        await _handleCryptoOperation(incoming);
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
      _startPendingUnlockTimer(incoming);
      throw const Nip55Failure(
        'Unlock Diogel and select an identity before sharing a public key.',
      );
    }
    if (activeIdentity == null) {
      throw const Nip55Failure(
        'Select an identity before sharing a public key.',
      );
    }
    if (!_matchesCurrentUser(incoming, activeIdentity.publicKey)) {
      throw const Nip55Failure(
        'Requested account does not match active identity.',
      );
    }

    final decision = await _decide(incoming, activeIdentity.publicKey);
    if (decision is AutoReject) {
      await _markGrantUsed(decision.grant);
      await _gateway.rejectNip55Intent(
        requestToken: incoming.requestToken,
        error: decision.reason,
      );
      state = state.copyWith(isLoading: false, clearPendingIncoming: true);
      return;
    }
    if (decision is AutoAllow) {
      if (!_canUseApprovalSession(decision.grant)) {
        state = state.copyWith(
          isLoading: false,
          pendingIncoming: incoming,
          pendingPublicKeyRequest: incoming,
        );
        return;
      }
      await _markGrantUsed(decision.grant);
      await _gateway.completeNip55Intent(
        requestToken: incoming.requestToken,
        extras: _responseBuilder.getPublicKeyExtras(
          activeIdentity,
          incoming: incoming,
        ),
      );
      state = state.copyWith(
        isLoading: false,
        lastSuccessMessage:
            'Public key shared using remembered NIP-55 permission.',
      );
      return;
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
      _startPendingUnlockTimer(incoming);
      throw const Nip55Failure(
        'Unlock Diogel and select an identity before signing.',
      );
    }
    if (activeIdentity == null) {
      throw const Nip55Failure('Select an identity before signing.');
    }

    final decision = await _decide(incoming, activeIdentity.publicKey);
    if (decision is AutoReject) {
      await _markGrantUsed(decision.grant);
      await _gateway.rejectNip55Intent(
        requestToken: incoming.requestToken,
        error: decision.reason,
      );
      state = state.copyWith(isLoading: false, clearPendingIncoming: true);
      return;
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

    if (decision is AutoAllow) {
      if (!_canUseApprovalSession(decision.grant)) return;
      await _markGrantUsed(decision.grant);
      await _requestController.approveRequest(signingRequest.id);
      await completeApprovedSigningRequest(signingRequest.id);
    }
  }

  Future<void> _handleCryptoOperation(Nip55IncomingRequest incoming) async {
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked) {
      state = state.copyWith(
        isLoading: false,
        pendingIncoming: incoming,
        failure: Nip55Failure(
          'Unlock Diogel and select an identity before ${incoming.method.wireName}.',
        ),
      );
      _startPendingUnlockTimer(incoming);
      throw Nip55Failure(
        'Unlock Diogel and select an identity before ${incoming.method.wireName}.',
      );
    }
    if (activeIdentity == null) {
      throw Nip55Failure(
        'Select an identity before ${incoming.method.wireName}.',
      );
    }
    final currentUser = incoming.currentUser;
    if (currentUser != null && currentUser != activeIdentity.publicKey) {
      throw const Nip55Failure(
        'Requested account does not match active identity.',
      );
    }

    final decision = await _decide(incoming, activeIdentity.publicKey);
    if (decision is AutoReject) {
      await _markGrantUsed(decision.grant);
      await _gateway.rejectNip55Intent(
        requestToken: incoming.requestToken,
        error: decision.reason,
      );
      state = state.copyWith(isLoading: false, clearPendingIncoming: true);
      return;
    }
    if (decision is AutoAllow && _canUseApprovalSession(decision.grant)) {
      await _markGrantUsed(decision.grant);
      await _completeCryptoOperation(incoming, remember: false);
      return;
    }

    state = state.copyWith(
      isLoading: false,
      pendingIncoming: incoming,
      pendingCryptoRequest: incoming,
    );
  }

  Future<void> approvePublicKeyRequest({bool remember = false}) async {
    final request = state.pendingPublicKeyRequest;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (request == null || activeIdentity == null) return;

    if (remember) {
      await _saveGrant(
        incoming: request,
        identityPubkey: activeIdentity.publicKey,
        scope: const GetPublicKeyScope(),
        decision: Nip55PermissionDecision.allow,
      );
    }

    await _gateway.completeNip55Intent(
      requestToken: request.requestToken,
      extras: _responseBuilder.getPublicKeyExtras(
        activeIdentity,
        incoming: request,
      ),
    );
    final approvalSessionExpiresAt = _nextApprovalSessionExpiry();
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingPublicKeyRequest: true,
      approvalSessionExpiresAt: approvalSessionExpiresAt,
      clearApprovalSession: approvalSessionExpiresAt == null,
      lastSuccessMessage: remember
          ? 'Public key shared and permission remembered.'
          : 'Public key shared with requesting Android app.',
    );
  }

  Future<void> rejectPublicKeyRequest({bool remember = false}) async {
    final request = state.pendingPublicKeyRequest;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (request == null) return;
    if (remember && activeIdentity != null) {
      await _saveGrant(
        incoming: request,
        identityPubkey: activeIdentity.publicKey,
        scope: const GetPublicKeyScope(),
        decision: Nip55PermissionDecision.reject,
      );
    }
    await _gateway.rejectNip55Intent(
      requestToken: request.requestToken,
      error: 'User rejected public key request',
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingPublicKeyRequest: true,
    );
  }

  Future<void> approveCryptoRequest({bool remember = false}) async {
    final request = state.pendingCryptoRequest;
    if (request == null) return;
    try {
      await _completeCryptoOperation(request, remember: remember);
      _extendApprovalSession();
    } on VaultException catch (error) {
      await _gateway.rejectNip55Intent(
        requestToken: request.requestToken,
        error: error.message,
      );
      state = state.copyWith(
        isLoading: false,
        failure: Nip55Failure(error.message, error),
        clearPendingIncoming: true,
        clearPendingCryptoRequest: true,
      );
    } catch (error) {
      await _gateway.rejectNip55Intent(
        requestToken: request.requestToken,
        error: 'Unable to complete NIP-55 operation',
      );
      state = state.copyWith(
        isLoading: false,
        failure: Nip55Failure('Unable to complete NIP-55 operation', error),
        clearPendingIncoming: true,
        clearPendingCryptoRequest: true,
      );
    }
  }

  Future<void> rejectCryptoRequest({bool remember = false}) async {
    final request = state.pendingCryptoRequest;
    if (request == null) return;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (remember && activeIdentity != null && !_scopeFor(request).isSensitive) {
      await _saveGrant(
        incoming: request,
        identityPubkey: activeIdentity.publicKey,
        scope: _scopeFor(request),
        decision: Nip55PermissionDecision.reject,
      );
    }
    await _gateway.rejectNip55Intent(
      requestToken: request.requestToken,
      error: 'User rejected ${request.method.wireName} request',
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingCryptoRequest: true,
    );
  }

  Future<void> _completeCryptoOperation(
    Nip55IncomingRequest request, {
    required bool remember,
  }) async {
    final activeIdentity = _vaultController.state.activeIdentity;
    if (activeIdentity == null) {
      throw const Nip55Failure('Select an identity before completing request.');
    }
    final result = await _cryptoResult(request, activeIdentity.localId);
    if (remember && !_scopeFor(request).isSensitive) {
      await _saveGrant(
        incoming: request,
        identityPubkey: activeIdentity.publicKey,
        scope: _scopeFor(request),
        decision: Nip55PermissionDecision.allow,
      );
    }
    await _gateway.completeNip55Intent(
      requestToken: request.requestToken,
      extras: _responseBuilder.operationResultExtras(
        incoming: request,
        result: result,
        clipboardLabel: _clipboardLabelFor(request),
      ),
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingCryptoRequest: true,
      isLoading: false,
      lastSuccessMessage: _cryptoCompletionMessageFor(request),
    );
  }

  Future<String> _cryptoResult(
    Nip55IncomingRequest request,
    String identityLocalId,
  ) async {
    final payload = request.payload;
    return switch (payload) {
      Nip04EncryptPayload(:final content, :final peerPubkey) =>
        _vaultService.nip04Encrypt(
          identityLocalId: identityLocalId,
          peerPubkeyHex: peerPubkey,
          plaintext: content,
        ),
      Nip04DecryptPayload(:final content, :final peerPubkey) =>
        _vaultService.nip04Decrypt(
          identityLocalId: identityLocalId,
          peerPubkeyHex: peerPubkey,
          ciphertext: content,
        ),
      Nip44EncryptPayload(:final content, :final peerPubkey) =>
        _vaultService.nip44Encrypt(
          identityLocalId: identityLocalId,
          peerPubkeyHex: peerPubkey,
          plaintext: content,
        ),
      Nip44DecryptPayload(:final content, :final peerPubkey) =>
        _vaultService.nip44Decrypt(
          identityLocalId: identityLocalId,
          peerPubkeyHex: peerPubkey,
          ciphertext: content,
        ),
      DecryptZapEventPayload(:final eventJson) => _vaultService.decryptZapEvent(
        identityLocalId: identityLocalId,
        eventJson: eventJson,
      ),
      GetPublicKeyPayload() || SignEventPayload() => throw Nip55Failure(
        '${request.method.wireName} is not a crypto operation.',
      ),
    };
  }

  Future<void> completeApprovedSigningRequest(String requestId) async {
    if (state.pendingSigningRequestId != requestId) return;
    final incoming = state.pendingIncoming;
    final signedEvent = _requestController.state.signedEvents[requestId];
    if (incoming == null) return;
    if (signedEvent == null) {
      final request = _findRequest(requestId);
      if (request?.status == SigningRequestStatus.failed ||
          _requestController.state.failure != null) {
        await _gateway.rejectNip55Intent(
          requestToken: incoming.requestToken,
          error: 'Signing failed. No event was returned.',
        );
        await _requestController.dismissRequest(requestId);
        state = state.copyWith(
          clearPendingIncoming: true,
          clearPendingSigningRequestId: true,
        );
      }
      return;
    }

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
      lastSuccessMessage: _completionMessageFor(incoming),
    );
  }

  Future<void> approveSigningRequest(
    String requestId, {
    bool remember = false,
  }) async {
    if (state.pendingSigningRequestId != requestId) return;
    final incoming = state.pendingIncoming;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (incoming == null || activeIdentity == null) return;

    await _requestController.approveRequest(requestId);
    final signedEvent = _requestController.state.signedEvents[requestId];

    if (remember && signedEvent != null) {
      try {
        await _saveGrant(
          incoming: incoming,
          identityPubkey: activeIdentity.publicKey,
          scope: _scopeFor(incoming),
          decision: Nip55PermissionDecision.allow,
        );
      } catch (e) {
        dev.log('Failed to save permission grant: $e', name: 'Diogel');
      }
    }
    await completeApprovedSigningRequest(requestId);
    if (signedEvent != null) {
      _extendApprovalSession();
    }
  }

  Future<void> rejectSigningRequest(
    String requestId, {
    bool remember = false,
  }) async {
    if (state.pendingSigningRequestId != requestId) return;
    final incoming = state.pendingIncoming;
    if (incoming == null) return;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (remember && activeIdentity != null) {
      await _saveGrant(
        incoming: incoming,
        identityPubkey: activeIdentity.publicKey,
        scope: _scopeFor(incoming),
        decision: Nip55PermissionDecision.reject,
      );
    }
    await _gateway.rejectNip55Intent(
      requestToken: incoming.requestToken,
      error: 'User rejected signing request',
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingSigningRequestId: true,
    );
  }

  Future<void> cancelPendingExternalRequest({
    String error = 'User cancelled NIP-55 request',
  }) async {
    final incoming = state.pendingIncoming;
    if (incoming == null) return;
    _pendingUnlockTimer?.cancel();
    await _gateway.rejectNip55Intent(
      requestToken: incoming.requestToken,
      error: error,
    );
    state = state.copyWith(
      clearPendingIncoming: true,
      clearPendingSigningRequestId: true,
      clearPendingPublicKeyRequest: true,
      clearPendingCryptoRequest: true,
      isLoading: false,
    );
  }

  void clearMessages() {
    state = state.copyWith(clearFailure: true, clearSuccess: true);
  }

  bool canRememberPendingSigningRequest(String requestId) {
    return state.pendingSigningRequestId == requestId &&
        state.pendingIncoming?.clientIdentity.packageName != null &&
        state.pendingIncoming?.webReturnOptions.isBrowserFlow != true &&
        _permissionStore != null;
  }

  bool canRememberPendingPublicKeyRequest() {
    return state.pendingPublicKeyRequest?.clientIdentity.packageName != null &&
        state.pendingPublicKeyRequest?.webReturnOptions.isBrowserFlow != true &&
        _permissionStore != null;
  }

  bool canRememberPendingCryptoRequest() {
    final request = state.pendingCryptoRequest;
    if (request == null) return false;
    return request.clientIdentity.packageName != null &&
        request.webReturnOptions.isBrowserFlow != true &&
        !_scopeFor(request).isSensitive &&
        _permissionStore != null;
  }

  Future<Nip55ApprovalDecision> _decide(
    Nip55IncomingRequest incoming,
    String activeIdentityPubkey,
  ) async {
    final grants = await _permissionStore?.listGrants() ?? const [];
    return _approvalPolicy.decide(
      request: incoming,
      vaultState: _vaultController.state.vaultState,
      activeIdentityPubkey: activeIdentityPubkey,
      grants: grants,
    );
  }

  Future<void> _saveGrant({
    required Nip55IncomingRequest incoming,
    required String identityPubkey,
    required Nip55PermissionScope scope,
    required Nip55PermissionDecision decision,
  }) async {
    final store = _permissionStore;
    final packageName = incoming.clientIdentity.packageName;
    if (store == null || packageName == null) return;
    await store.saveGrant(
      Nip55PermissionGrant(
        id: 'nip55-${decision.name}-${scope.wire}-${DateTime.now().microsecondsSinceEpoch}',
        identityPubkey: identityPubkey,
        packageName: packageName,
        certificateSha256: incoming.clientIdentity.certificateSha256,
        scope: scope,
        decision: decision,
        createdAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
        userLabel: incoming.clientIdentity.displayName,
      ),
    );
  }

  Future<void> _markGrantUsed(Nip55PermissionGrant grant) async {
    final store = _permissionStore;
    if (store == null) return;
    await store.saveGrant(grant.copyWith(lastUsedAt: DateTime.now()));
  }

  Nip55PermissionScope _scopeFor(Nip55IncomingRequest incoming) {
    if (incoming.method == Nip55Method.getPublicKey) {
      return const GetPublicKeyScope();
    }
    if (incoming.method == Nip55Method.signEvent) {
      final kind = incoming.eventJson?['kind'];
      return SignEventScope(kind is int ? kind : null);
    }
    final peerPubkey = incoming.pubkey;
    return switch (incoming.method) {
      Nip55Method.nip04Encrypt => Nip04EncryptScope(peerPubkey),
      Nip55Method.nip04Decrypt => Nip04DecryptScope(peerPubkey),
      Nip55Method.nip44Encrypt => Nip44EncryptScope(peerPubkey),
      Nip55Method.nip44Decrypt => Nip44DecryptScope(peerPubkey),
      Nip55Method.decryptZapEvent => const DecryptZapEventScope(),
      Nip55Method.getPublicKey ||
      Nip55Method.signEvent ||
      Nip55Method.unsupported => UnsupportedScope(incoming.method.wireName),
    };
  }

  SigningRequest? _findRequest(String requestId) {
    for (final request in _requestController.state.requests) {
      if (request.id == requestId) return request;
    }
    return null;
  }

  bool _isWaitingForUnlockFailure(Nip55Failure error) {
    return error.message.startsWith('Unlock Diogel');
  }

  String _completionMessageFor(Nip55IncomingRequest incoming) {
    if (incoming.webReturnOptions.hasCallback) {
      return 'Event signed locally and returned through the browser callback.';
    }
    if (incoming.webReturnOptions.isBrowserFlow) {
      return 'Event signed locally and copied to clipboard for the browser flow.';
    }
    if (incoming.clientIdentity.provenanceVerified) {
      return 'Event signed locally and returned to requesting Android app.';
    }
    return 'Event signed locally and returned to requesting Android app.';
  }

  String _cryptoCompletionMessageFor(Nip55IncomingRequest incoming) {
    if (incoming.webReturnOptions.hasCallback) {
      return '${incoming.method.wireName} completed and returned through the browser callback.';
    }
    if (incoming.webReturnOptions.isBrowserFlow) {
      return '${incoming.method.wireName} completed and copied to clipboard for the browser flow.';
    }
    return '${incoming.method.wireName} completed and returned to requesting Android app.';
  }

  String _clipboardLabelFor(Nip55IncomingRequest incoming) {
    if (_scopeFor(incoming).isSensitive) return 'Sensitive NIP-55 result';
    return 'NIP-55 ${incoming.method.wireName} result';
  }

  bool _canUseApprovalSession(Nip55PermissionGrant grant) {
    if (grant.scope.isSensitive || grant.scope.isBroad) return false;
    final expiresAt = state.approvalSessionExpiresAt;
    return expiresAt != null && expiresAt.isAfter(_now());
  }

  DateTime? _nextApprovalSessionExpiry() {
    final minutes = _vaultController.state.approvalSessionDurationMinutes;
    if (minutes <= 0) return null;
    return _now().add(Duration(minutes: minutes));
  }

  void _extendApprovalSession() {
    final expiresAt = _nextApprovalSessionExpiry();
    if (expiresAt == null) {
      state = state.copyWith(clearApprovalSession: true);
      return;
    }
    state = state.copyWith(approvalSessionExpiresAt: expiresAt);
  }

  void _startPendingUnlockTimer(Nip55IncomingRequest incoming) {
    _pendingUnlockTimer?.cancel();
    _pendingUnlockTimer = Timer(_pendingUnlockTimeout, () {
      if (!mounted) return;
      if (state.pendingIncoming?.requestToken != incoming.requestToken ||
          !state.isWaitingForUnlock) {
        return;
      }
      unawaited(
        cancelPendingExternalRequest(
          error: 'NIP-55 request timed out waiting for unlock',
        ),
      );
    });
  }

  bool _matchesCurrentUser(
    Nip55IncomingRequest incoming,
    String activeIdentityPubkey,
  ) {
    final currentUser = incoming.currentUser;
    return currentUser == null || currentUser == activeIdentityPubkey;
  }

  Nip55IncomingRequest? _safeParseForRejection(Map<String, Object?> raw) {
    try {
      final parser = _parser;
      return parser.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
