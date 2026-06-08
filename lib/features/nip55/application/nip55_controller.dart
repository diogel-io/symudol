import 'dart:async';
import 'dart:developer' as dev;
import 'package:android_diogel/app/utils/concurrency_utils.dart';
import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

import '../data/nip55_native_mirror_sync.dart';
import '../data/secure_storage_nip55_permission_store.dart';
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
  final Nip55NativeMirrorSync? _nativeSync;
  final Duration _pendingUnlockTimeout;
  final DateTime Function() _now;
  Timer? _pendingUnlockTimer;
  StreamSubscription<VaultControllerState>? _vaultStateSubscription;

  // Track concurrency synchronously to avoid races in async flows
  bool _isParsingIntent = false;
  final List<Nip55IncomingRequest> _deferredClientAuthRequests = [];

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
    Nip55NativeMirrorSync? nativeSync,
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
       _nativeSync = nativeSync,
       _pendingUnlockTimeout = pendingUnlockTimeout,
       _now = now ?? DateTime.now,
       super(const Nip55State()) {
    _gateway.setIncomingIntentHandler((raw) => handleRawIntent(raw));
    _gateway.setProviderQueryHandler((raw) => handleProviderQuery(raw));
    _vaultStateSubscription = _vaultController.stream.listen((vaultState) {
      _onVaultStateChanged(vaultState);
    });
    // Sync initial vault state (the stream only fires on changes)
    _onVaultStateChanged(_vaultController.state);
    // Eagerly sync permission grants to native mirror on startup
    _syncGrantsToNative();
  }

  @override
  void dispose() {
    _pendingUnlockTimer?.cancel();
    _vaultStateSubscription?.cancel();
    super.dispose();
  }

  /// Eagerly sync permission grants to native mirror on startup.
  Future<void> _syncGrantsToNative() async {
    final store = _permissionStore;
    if (store is SecureStorageNip55PermissionStore) {
      await store.syncToNative();
    }
  }

  /// Syncs the active key to the native ContentProvider bridge when
  /// the vault state changes.
  Future<void> _onVaultStateChanged(VaultControllerState state) async {
    final vaultUnlocked = state.vaultState is VaultUnlocked;
    final pubkey = state.activeIdentity?.publicKey;
    // Use android logging via MethodChannel for visibility in logcat
    try {
      await _nativeSync?.setActiveIdentityPubkey(pubkey);
    } catch (_) {}
    dev.log('Nip55Controller: _onVaultStateChanged: vaultState=${state.vaultState.runtimeType}, hasPubkey=${pubkey != null}, nativeSync=${_nativeSync != null}', name: 'Diogel');
    if (vaultUnlocked && pubkey != null) {
      try {
        final privateKey = await _vaultService.getActivePrivateKey();
        dev.log('Nip55Controller: got privateKey=${privateKey != null ? "yes(${privateKey.length}chars)" : "null"}', name: 'Diogel');
        if (privateKey != null) {
          await _nativeSync?.setActiveKey(
            privateKey: privateKey,
            publicKey: pubkey,
            localId: state.activeIdentity!.localId,
          );
          dev.log('Nip55Controller: synced active key to native bridge', name: 'Diogel');
        } else {
          dev.log('Nip55Controller: privateKey was null, not syncing to native bridge', name: 'Diogel');
        }
      } catch (e) {
        dev.log('Failed to sync active key to native bridge: $e', name: 'Diogel');
      }
    } else {
      dev.log('Nip55Controller: vault locked or no active identity, clearing native bridge', name: 'Diogel');
      await _nativeSync?.clearActiveKey();
    }
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
      final busyRequest = _safeParseForRejection(raw);
      if (busyRequest == null) return;
      // When still parsing the previous intent (_isParsingIntent == true),
      // skip async permission lookups — the first intent hasn't produced any
      // pending UI or approval session yet, so auto-completion is impossible
      // and the async _decide call could block indefinitely (e.g. slow store).
      // Only try auto-completion when a pending request already exists in
      // the UI, meaning an approval session may be active.
      if (!_isParsingIntent) {
        if (await _tryCompleteRememberedBusyRequest(busyRequest)) return;
      }
      if (_shouldDeferClientAuthenticationRequest(busyRequest)) {
        _deferClientAuthenticationRequest(busyRequest);
        return;
      }
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
        clearPendingIncoming: true,
        clearPendingSigningRequestId: true,
        clearPendingPublicKeyRequest: true,
        clearPendingCryptoRequest: true,
      );
      final requestToken = raw['requestToken'] as String?;
      if (requestToken != null) {
        await _gateway.rejectNip55Intent(
          requestToken: requestToken,
          error: error.message,
        );
      }
    } on Nip55Failure catch (error) {
      if (incoming == null || !_isWaitingForUnlockFailure(error)) {
        state = state.copyWith(
          isLoading: false,
          failure: error,
          clearPendingIncoming: true,
          clearPendingSigningRequestId: true,
          clearPendingPublicKeyRequest: true,
          clearPendingCryptoRequest: true,
        );
        final requestToken =
            incoming?.requestToken ?? raw['requestToken'] as String?;
        if (requestToken != null) {
          await _gateway.rejectNip55Intent(
            requestToken: requestToken,
            error: error.message,
          );
        }
      } else {
        state = state.copyWith(isLoading: false, failure: error);
      }
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        failure: Nip55Failure('Unable to handle NIP-55 request', error),
        clearPendingIncoming: true,
        clearPendingSigningRequestId: true,
        clearPendingPublicKeyRequest: true,
        clearPendingCryptoRequest: true,
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
    final parser = _parser;
    final incoming = parser.parse(raw);
    if (state.hasPendingExternalRequest &&
        !_isClientAuthenticationRequest(incoming)) {
      return null;
    }
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked) {
      return null;
    }
    if (activeIdentity == null) {
      return null;
    }
    if (!_matchesCurrentUser(incoming, activeIdentity.publicKey)) {
      return null;
    }

    final decision = await _decide(incoming, activeIdentity.publicKey);
    if (decision is AutoReject) {
      await _markGrantUsed(decision.grant);
      return {'rejected': decision.reason};
    }
    if (decision is! AutoAllow ||
        !_canUseRememberedGrantWithoutReview(incoming, decision.grant)) {
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

    if (decision is AutoAllow &&
        _canUseRememberedGrantWithoutReview(incoming, decision.grant)) {
      await _completeRememberedSignEvent(
        incoming: incoming,
        activeIdentity: activeIdentity,
        grant: decision.grant,
      );
      state = state.copyWith(
        isLoading: false,
        clearPendingIncoming: true,
        clearPendingSigningRequestId: true,
        lastSuccessMessage: 'Event signed using remembered NIP-55 permission.',
      );
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

    // Enter loading state to prevent duplicate submissions
    state = state.copyWith(isLoading: true);

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
      clearPendingCryptoRequest: true,
      clearPendingSigningRequestId: true,
      approvalSessionExpiresAt: approvalSessionExpiresAt,
      clearApprovalSession: approvalSessionExpiresAt == null,
      lastSuccessMessage: remember
          ? 'Public key shared and permission remembered.'
          : 'Public key shared with requesting Android app.',
      isLoading: false,
    );
  }

  Future<void> rejectPublicKeyRequest({bool remember = false}) async {
    final request = state.pendingPublicKeyRequest;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (request == null) return;

    // Enter loading to disable buttons while we complete the rejection
    state = state.copyWith(isLoading: true);

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
      isLoading: false,
    );
  }

  Future<void> approveCryptoRequest({bool remember = false}) async {
    final request = state.pendingCryptoRequest;
    if (request == null) return;

    // Enter loading state immediately to prevent double taps
    state = state.copyWith(isLoading: true);

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

    // Enter loading to disable the UI while completing rejection
    state = state.copyWith(isLoading: true);

    final activeIdentity = _vaultController.state.activeIdentity;
    if (remember &&
        activeIdentity != null &&
        _canRememberCryptoRequest(request)) {
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
      isLoading: false,
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
    if (remember && _canRememberCryptoRequest(request)) {
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
      SignMessagePayload(:final message) => _vaultService.signMessage(
        identityLocalId: identityLocalId,
        message: message,
      ),
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
      if (remember) {
        await _completeDeferredClientAuthenticationRequests();
      } else {
        await _rejectDeferredClientAuthenticationRequests(
          'Client authentication request was not remembered.',
        );
      }
    }
  }

  Future<bool> _tryCompleteRememberedBusyRequest(
    Nip55IncomingRequest incoming,
  ) async {
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked ||
        activeIdentity == null) {
      return false;
    }
    if (!_matchesCurrentUser(incoming, activeIdentity.publicKey)) {
      return false;
    }
    if (incoming.method == Nip55Method.signEvent) {
      final eventPubkey = incoming.eventJson?['pubkey'];
      if (eventPubkey != null && eventPubkey != activeIdentity.publicKey) {
        return false;
      }
    }
    // Auto-complete if we have a remembered grant that covers this request.
    // This includes: kind 22242 relay auth, nip04/nip44 decrypt with wildcard
    // or matching peer grants.
    if (!_isAutoCompletableMethod(incoming)) return false;

    final decision = await _decide(incoming, activeIdentity.publicKey);
    if (decision is AutoReject) {
      await _markGrantUsed(decision.grant);
      await _gateway.rejectNip55Intent(
        requestToken: incoming.requestToken,
        error: decision.reason,
      );
      return true;
    }
    if (decision is! AutoAllow ||
        !_canUseRememberedGrantWithoutReview(incoming, decision.grant)) {
      return false;
    }

    if (incoming.method == Nip55Method.signEvent) {
      await _completeRememberedSignEvent(
        incoming: incoming,
        activeIdentity: activeIdentity,
        grant: decision.grant,
      );
      return true;
    }
    if (incoming.method == Nip55Method.getPublicKey) {
      await _markGrantUsed(decision.grant);
      await _gateway.completeNip55Intent(
        requestToken: incoming.requestToken,
        extras: _responseBuilder.getPublicKeyExtras(
          activeIdentity,
          incoming: incoming,
        ),
      );
      return true;
    }

    final result = await _cryptoResult(incoming, activeIdentity.localId);
    await _markGrantUsed(decision.grant);
    await _gateway.completeNip55Intent(
      requestToken: incoming.requestToken,
      extras: _responseBuilder.operationResultExtras(
        incoming: incoming,
        result: result,
        clipboardLabel: _clipboardLabelFor(incoming),
      ),
    );
    return true;
  }

  Future<void> _completeRememberedSignEvent({
    required Nip55IncomingRequest incoming,
    required VaultIdentity activeIdentity,
    required Nip55PermissionGrant grant,
  }) async {
    final signingRequest = _mapper.mapSignEvent(
      incoming: incoming,
      activeIdentity: activeIdentity,
    );
    final draft = const NostrEventPayloadParser().parse(signingRequest);
    final signedEvent = await _vaultService.signNostrEvent(
      identityLocalId: activeIdentity.localId,
      draft: draft,
    );
    await _markGrantUsed(grant);
    await _gateway.completeNip55Intent(
      requestToken: incoming.requestToken,
      extras: _responseBuilder.signEventExtras(
        incoming: incoming,
        signedEvent: signedEvent,
      ),
    );
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
    if (_isClientAuthenticationRequest(incoming)) {
      await _rejectDeferredClientAuthenticationRequests(
        'User rejected signing request',
      );
    }
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
    return _canRememberCryptoRequest(request);
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
      Nip55Method.signMessage => const SignMessageScope(),
      // Decrypt scopes use wildcard (null) peer: if you trust an app to decrypt
      // one DM, you trust it to decrypt all DMs. Encrypt keeps the specific peer
      // since you want to know who you're encrypting to.
      Nip55Method.nip04Encrypt => Nip04EncryptScope(peerPubkey),
      Nip55Method.nip04Decrypt => const Nip04DecryptScope(null),
      Nip55Method.nip44Encrypt => Nip44EncryptScope(peerPubkey),
      Nip55Method.nip44Decrypt => const Nip44DecryptScope(null),
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

  bool _canUseRememberedGrantWithoutReview(
    Nip55IncomingRequest incoming,
    Nip55PermissionGrant grant,
  ) {
    if (_isRememberedClientAuthentication(incoming, grant)) return true;
    if (_isRememberedScopedDecrypt(incoming, grant)) return true;
    return _canUseApprovalSession(grant);
  }

  bool _isRememberedClientAuthentication(
    Nip55IncomingRequest incoming,
    Nip55PermissionGrant grant,
  ) {
    if (!_isClientAuthenticationRequest(incoming)) return false;
    final grantScope = grant.scope;
    return grantScope is SignEventScope && grantScope.kind == 22242;
  }

  bool _isRememberedScopedDecrypt(
    Nip55IncomingRequest incoming,
    Nip55PermissionGrant grant,
  ) {
    // Build the requested scope using the actual peer pubkey from the
    // incoming request — NOT the controller's _scopeFor which always
    // uses null/wildcard for decrypt.  The wildcard _scopeFor is correct
    // for *saving* grants (trust-all-DMs policy) but breaks *matching*
    // peer-scoped grants because it strips the peer.  This must match
    // Nip55ApprovalPolicy._scopeFor which preserves the peer.
    //
    // decrypt_zap_event is also matched here because NIP-57 zap receipts
    // are NIP-04 encrypted to the recipient. If the user trusts an app
    // to decrypt DMs, they trust it to decrypt zap receipts too, so
    // nip04_decrypt/nip44_decrypt grants also satisfy decrypt_zap_event.
    final requested = switch (incoming.method) {
      Nip55Method.nip04Decrypt => Nip04DecryptScope(incoming.pubkey),
      Nip55Method.nip44Decrypt => Nip44DecryptScope(incoming.pubkey),
      Nip55Method.decryptZapEvent => const DecryptZapEventScope(),
      _ => null,
    };
    if (requested == null) return false;
    final grantScope = grant.scope;
    return switch ((grantScope, requested)) {
      // Wildcard (null peer) matches any requested peer;
      // specific peer only matches that exact peer.
      (
        Nip04DecryptScope(peerPubkey: final grantPeer),
        Nip04DecryptScope(peerPubkey: final requestedPeer),
      ) =>
        grantPeer == null || grantPeer == requestedPeer,
      (
        Nip44DecryptScope(peerPubkey: final grantPeer),
        Nip44DecryptScope(peerPubkey: final requestedPeer),
      ) =>
        grantPeer == null || grantPeer == requestedPeer,
      // nip04_decrypt and nip44_decrypt grants also satisfy decrypt_zap_event.
      // This mirrors Nip55PermissionMirror.scopeMatches on the Kotlin side.
      (Nip04DecryptScope(), DecryptZapEventScope()) => true,
      (Nip44DecryptScope(), DecryptZapEventScope()) => true,
      // Direct decrypt_zap_event grant matches directly.
      (DecryptZapEventScope(), DecryptZapEventScope()) => true,
      _ => false,
    };
  }

  bool _canRememberCryptoRequest(Nip55IncomingRequest request) {
    if (request.clientIdentity.packageName == null ||
        request.webReturnOptions.isBrowserFlow == true ||
        _permissionStore == null) {
      return false;
    }
    final scope = _scopeFor(request);
    if (!scope.isSensitive) return true;
    return switch (scope) {
      Nip04DecryptScope() => true,
      Nip44DecryptScope() => true,
      DecryptZapEventScope() => true,
      _ => false,
    };
  }

  bool _isClientAuthenticationRequest(Nip55IncomingRequest incoming) {
    return incoming.method == Nip55Method.signEvent &&
        incoming.eventJson?['kind'] == 22242;
  }

  bool _isAutoCompletableMethod(Nip55IncomingRequest incoming) {
    // Methods that can be auto-completed without UI when a remembered grant exists.
    // kind 22242 relay auth is always auto-approved (no grant needed when vault unlocked).
    // Decrypt operations can be auto-completed when a matching grant exists.
    return incoming.method == Nip55Method.getPublicKey ||
        incoming.method == Nip55Method.nip04Decrypt ||
        incoming.method == Nip55Method.nip44Decrypt ||
        incoming.method == Nip55Method.signEvent ||
        incoming.method == Nip55Method.nip04Encrypt ||
        incoming.method == Nip55Method.nip44Encrypt ||
        incoming.method == Nip55Method.signMessage ||
        incoming.method == Nip55Method.decryptZapEvent;
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

  bool _shouldDeferClientAuthenticationRequest(Nip55IncomingRequest incoming) {
    // Defer any request that has a remembered grant (not just kind 22242).
    if (!_isAutoCompletableMethod(incoming)) return false;
    // Do not defer while still parsing the previous intent. At this point no
    // pending UI or approval session exists yet, so we don't know whether
    // the first request will be auto-completed, rejected, or shown to the
    // user. Deferring would leave the caller hanging without a response,
    // which can cause deadlocks (e.g. slow permission store).
    if (_isParsingIntent) return false;
    final pending = state.pendingIncoming;
    if (pending == null) return false;
    // Only defer if the pending request is also auto-completable (i.e. same class)
    if (!_isAutoCompletableMethod(pending)) return false;
    return _sameClientAndIdentity(incoming, pending);
  }

  void _deferClientAuthenticationRequest(Nip55IncomingRequest incoming) {
    final token = incoming.requestToken;
    if (_deferredClientAuthRequests.any(
      (request) => request.requestToken == token,
    )) {
      return;
    }
    _deferredClientAuthRequests.add(incoming);
  }

  Future<void> _completeDeferredClientAuthenticationRequests() async {
    if (_deferredClientAuthRequests.isEmpty) return;
    final activeIdentity = _vaultController.state.activeIdentity;
    if (_vaultController.state.vaultState is! VaultUnlocked ||
        activeIdentity == null) {
      return;
    }

    final deferred = List<Nip55IncomingRequest>.from(
      _deferredClientAuthRequests,
    );
    _deferredClientAuthRequests.clear();
    for (final incoming in deferred) {
      if (!_matchesCurrentUser(incoming, activeIdentity.publicKey)) {
        await _gateway.rejectNip55Intent(
          requestToken: incoming.requestToken,
          error: 'Requested account does not match active identity.',
        );
        continue;
      }
      final decision = await _decide(incoming, activeIdentity.publicKey);
      if (decision is AutoAllow &&
          _canUseRememberedGrantWithoutReview(incoming, decision.grant)) {
        // Dispatch to the appropriate completion handler
        if (incoming.method == Nip55Method.signEvent) {
          await _completeRememberedSignEvent(
            incoming: incoming,
            activeIdentity: activeIdentity,
            grant: decision.grant,
          );
        } else if (incoming.method == Nip55Method.getPublicKey) {
          await _markGrantUsed(decision.grant);
          await _gateway.completeNip55Intent(
            requestToken: incoming.requestToken,
            extras: _responseBuilder.getPublicKeyExtras(
              activeIdentity,
              incoming: incoming,
            ),
          );
        } else {
          // Crypto operations (decrypt, encrypt, etc.)
          final result = await _cryptoResult(incoming, activeIdentity.localId);
          await _markGrantUsed(decision.grant);
          await _gateway.completeNip55Intent(
            requestToken: incoming.requestToken,
            extras: _responseBuilder.operationResultExtras(
              incoming: incoming,
              result: result,
              clipboardLabel: _clipboardLabelFor(incoming),
            ),
          );
        }
      } else if (decision is AutoReject) {
        await _markGrantUsed(decision.grant);
        await _gateway.rejectNip55Intent(
          requestToken: incoming.requestToken,
          error: decision.reason,
        );
      } else {
        await _gateway.rejectNip55Intent(
          requestToken: incoming.requestToken,
          error: 'Client authentication request was not remembered.',
        );
      }
    }
  }

  Future<void> _rejectDeferredClientAuthenticationRequests(String error) async {
    if (_deferredClientAuthRequests.isEmpty) return;
    final deferred = List<Nip55IncomingRequest>.from(
      _deferredClientAuthRequests,
    );
    _deferredClientAuthRequests.clear();
    for (final incoming in deferred) {
      await _gateway.rejectNip55Intent(
        requestToken: incoming.requestToken,
        error: error,
      );
    }
  }

  bool _sameClientAndIdentity(
    Nip55IncomingRequest left,
    Nip55IncomingRequest right,
  ) {
    final leftClient = left.clientIdentity;
    final rightClient = right.clientIdentity;
    if (leftClient.packageName == null ||
        leftClient.packageName != rightClient.packageName) {
      return false;
    }
    if (left.currentUser != right.currentUser) return false;
    final leftPubkey = left.eventJson?['pubkey'];
    final rightPubkey = right.eventJson?['pubkey'];
    if (leftPubkey != rightPubkey) return false;
    final leftCert = leftClient.certificateSha256;
    final rightCert = rightClient.certificateSha256;
    return leftCert == null || rightCert == null || leftCert == rightCert;
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
