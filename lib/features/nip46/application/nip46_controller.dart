import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:symudol/app/diogel_log.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_parser.dart';
import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

import '../data/dart_nip46_crypto.dart';
import '../data/dart_nip46_relay_service.dart';
import '../data/nip46_token_codec.dart';
import '../domain/nip46_approval_policy.dart';
import '../domain/nip46_connection_token.dart';
import '../domain/nip46_method.dart';
import '../domain/nip46_permission_scope.dart';
import '../domain/nip46_relay_event.dart';
import '../domain/nip46_request.dart';
import '../domain/nip46_response.dart';
import '../domain/nip46_session.dart';
import '../domain/nip46_session_store.dart';

class Nip46PendingMethodRequest {
  final String sessionId;
  final Nip46Request request;
  final bool usesNip04;
  final Map<String, Object?>? signEventTemplate;

  const Nip46PendingMethodRequest({
    required this.sessionId,
    required this.request,
    required this.usesNip04,
    this.signEventTemplate,
  });
}

class Nip46State {
  final List<Nip46Session> sessions;
  // Session awaiting user approval for a new connection.
  final Nip46Session? pendingApproval;
  // Method request awaiting user approval.
  final Nip46PendingMethodRequest? pendingMethodRequest;
  final bool isLoading;
  final String? failure;
  final String? lastSuccessMessage;

  const Nip46State({
    this.sessions = const [],
    this.pendingApproval,
    this.pendingMethodRequest,
    this.isLoading = false,
    this.failure,
    this.lastSuccessMessage,
  });

  bool get hasPendingAction =>
      pendingApproval != null || pendingMethodRequest != null;

  Nip46State copyWith({
    List<Nip46Session>? sessions,
    Object? pendingApproval = _sentinel,
    Object? pendingMethodRequest = _sentinel,
    bool? isLoading,
    Object? failure = _sentinel,
    Object? lastSuccessMessage = _sentinel,
  }) {
    return Nip46State(
      sessions: sessions ?? this.sessions,
      pendingApproval: pendingApproval == _sentinel
          ? this.pendingApproval
          : pendingApproval as Nip46Session?,
      pendingMethodRequest: pendingMethodRequest == _sentinel
          ? this.pendingMethodRequest
          : pendingMethodRequest as Nip46PendingMethodRequest?,
      isLoading: isLoading ?? this.isLoading,
      failure: failure == _sentinel ? this.failure : failure as String?,
      lastSuccessMessage: lastSuccessMessage == _sentinel
          ? this.lastSuccessMessage
          : lastSuccessMessage as String?,
    );
  }
}

const Object _sentinel = Object();

class Nip46Controller extends StateNotifier<Nip46State> {
  static const List<String> defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
  ];
  static const int _maxDedupCacheSize = 512;
  static const Duration _requestTimeout = Duration(seconds: 60);
  static const Duration _connectTimeout = Duration(seconds: 120);

  final Nip46SessionStore _sessionStore;
  final VaultService _vaultService;
  final VaultController _vaultController;
  final Nip46RelayService _relayService;
  final DartNip46Crypto _crypto;
  final Nip46ApprovalPolicy _approvalPolicy;
  final DateTime Function() _now;
  final Random _random;

  StreamSubscription<Nip46InboundRelayEvent>? _inboundSub;
  StreamSubscription<VaultControllerState>? _vaultSub;
  VaultState? _lastVaultState;

  // LRU dedup cache for processed event IDs.
  final LinkedHashMap<String, bool> _processedEventIds = LinkedHashMap();

  // Timer for pending method request timeout.
  Timer? _methodRequestTimer;
  // Timer for pending connect approval timeout.
  Timer? _connectApprovalTimer;

  Nip46Controller({
    required Nip46SessionStore sessionStore,
    required VaultService vaultService,
    required VaultController vaultController,
    required Nip46RelayService relayService,
    required DartNip46Crypto crypto,
    Nip46ApprovalPolicy approvalPolicy = const Nip46ApprovalPolicy(),
    DateTime Function()? now,
  })  : _sessionStore = sessionStore,
        _vaultService = vaultService,
        _vaultController = vaultController,
        _relayService = relayService,
        _crypto = crypto,
        _approvalPolicy = approvalPolicy,
        _now = now ?? DateTime.now,
        _random = Random.secure(),
        super(const Nip46State()) {
    _initialize();
  }

  // ── public API ─────────────────────────────────────────────────────────────

  /// Generates a bunker:// token and starts waiting for a client connect request.
  Future<Nip46BunkerToken> initiateBunkerSession([List<String>? relays]) async {
    final sessionRelays = relays ?? defaultRelays;
    final sessionPrivkey = _generatePrivkey();
    final pubkey = _crypto.derivePublicKey(sessionPrivkey);
    final token = Nip46TokenCodec.generateBunkerToken(
      remoteSignerPubkey: pubkey,
      relays: sessionRelays,
    );

    final session = Nip46Session(
      id: _generateId(),
      clientPubkey: '', // unknown until connect arrives
      remoteSignerPubkey: pubkey,
      remoteSignerPrivkey: sessionPrivkey,
      relays: sessionRelays,
      grantedScopes: const [],
      status: Nip46SessionStatus.pending,
      createdAt: _now(),
      pendingSecret: token.secret,
    );

    await _sessionStore.saveSession(session);
    await _startRelays(session);
    state = state.copyWith(
      sessions: [...state.sessions, session],
    );
    return token;
  }

  /// Parses a nostrconnect:// token, starts a session, and publishes the connect response.
  Future<void> importNostrconnectToken(String uri) async {
    final parsed = Nip46TokenCodec.parseNostrconnect(uri);
    final sessionPrivkey = _generatePrivkey();
    final sessionPubkey = _crypto.derivePublicKey(sessionPrivkey);

    final session = Nip46Session(
      id: _generateId(),
      clientPubkey: parsed.clientPubkey,
      remoteSignerPubkey: sessionPubkey,
      remoteSignerPrivkey: sessionPrivkey,
      relays: parsed.relays,
      clientName: parsed.name,
      clientUrl: parsed.url,
      clientImage: parsed.image,
      grantedScopes: const [],
      status: Nip46SessionStatus.pending,
      createdAt: _now(),
      pendingSecret: parsed.secret,
      initiatedBy: Nip46ConnectionInitiator.nostrconnect,
    );

    await _sessionStore.saveSession(session);
    await _startRelays(session);

    state = state.copyWith(
      sessions: [...state.sessions, session],
      pendingApproval: session,
    );

    // Start approval timeout.
    _connectApprovalTimer?.cancel();
    _connectApprovalTimer = Timer(_connectTimeout, () {
      if (state.pendingApproval?.id == session.id) {
        rejectConnection();
      }
    });
  }

  /// Called by the approval UI to accept a new connection.
  Future<void> approveConnection({
    List<Nip46PermissionScope> grantedScopes = const [],
  }) async {
    final pending = state.pendingApproval;
    if (pending == null) return;

    _connectApprovalTimer?.cancel();
    _connectApprovalTimer = null;

    final approved = pending.copyWith(
      status: Nip46SessionStatus.active,
      grantedScopes: grantedScopes,
      connectedAt: _now(),
      pendingSecret: null,
    );

    await _sessionStore.saveSession(approved);

    final updatedSessions = state.sessions
        .map((s) => s.id == approved.id ? approved : s)
        .toList();

    state = state.copyWith(
      sessions: updatedSessions,
      pendingApproval: null,
    );

    // In the bunker flow this answers the client's connect request with
    // "ack". In the nostrconnect flow there was no request: the client waits
    // for a connect response carrying the secret from its URI, and must
    // check it (NIP-46).
    if (pending.clientPubkey.isNotEmpty) {
      final isNostrconnect =
          pending.initiatedBy == Nip46ConnectionInitiator.nostrconnect;
      try {
        await _publishResponse(
          session: approved,
          requestId: _connectResponseId(pending),
          result: isNostrconnect ? pending.pendingSecret ?? 'ack' : 'ack',
        );
      } catch (e) {
        diogelLog('Nip46Controller: failed to publish connect ack', error: e);
      }
    }
    _pendingConnectRequestId = null;
  }

  /// Called by the approval UI to reject a new connection.
  Future<void> rejectConnection() async {
    final pending = state.pendingApproval;
    if (pending == null) return;

    _connectApprovalTimer?.cancel();
    _connectApprovalTimer = null;

    if (pending.clientPubkey.isNotEmpty) {
      await _publishErrorResponse(
        session: pending,
        requestId: _connectResponseId(pending),
        error: 'Connection rejected by user',
      );
    }
    _pendingConnectRequestId = null;

    await _sessionStore.deleteSession(pending.id);
    await _relayService.stopSession(pending.id);

    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != pending.id).toList(),
      pendingApproval: null,
    );
  }

  /// Called by the approval UI to approve a pending method request.
  Future<void> approveMethodRequest({
    List<Nip46PermissionScope> newScopes = const [],
  }) async {
    final pending = state.pendingMethodRequest;
    if (pending == null) return;

    _methodRequestTimer?.cancel();
    _methodRequestTimer = null;

    var session =
        state.sessions.firstWhere((s) => s.id == pending.sessionId);

    if (newScopes.isNotEmpty) {
      session = session.copyWith(
        grantedScopes: [...session.grantedScopes, ...newScopes],
      );
      await _sessionStore.saveSession(session);
      state = state.copyWith(
        sessions: state.sessions
            .map((s) => s.id == session.id ? session : s)
            .toList(),
      );
    }

    state = state.copyWith(pendingMethodRequest: null);
    await _dispatchMethod(
      session: session,
      request: pending.request,
      usesNip04: pending.usesNip04,
    );
  }

  /// Called by the approval UI to reject a pending method request.
  Future<void> rejectMethodRequest() async {
    final pending = state.pendingMethodRequest;
    if (pending == null) return;

    _methodRequestTimer?.cancel();
    _methodRequestTimer = null;

    final session =
        state.sessions.firstWhere((s) => s.id == pending.sessionId);

    state = state.copyWith(pendingMethodRequest: null);
    await _publishErrorResponse(
      session: session,
      requestId: pending.request.id,
      error: 'User rejected the request',
    );
  }

  /// Revokes a session — stops relays, deletes from store, removes from state.
  Future<void> revokeSession(String sessionId) async {
    await _relayService.stopSession(sessionId);
    await _sessionStore.deleteSession(sessionId);
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != sessionId).toList(),
    );
  }

  void clearMessages() {
    state = state.copyWith(
      failure: null,
      lastSuccessMessage: null,
    );
  }

  // ── internal ─────────────────────────────────────────────────────────────

  // Holds the connect request ID during the bunker:// approval flow.
  String? _pendingConnectRequestId;

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      final sessions = await _sessionStore.listSessions();
      state = state.copyWith(sessions: sessions, isLoading: false);

      for (final session in sessions) {
        if (session.status == Nip46SessionStatus.active) {
          await _startRelays(session);
        }
      }

      _inboundSub = _relayService.inboundEvents.listen(_onInboundEvent);
      _lastVaultState = _vaultController.state.vaultState;
      _vaultSub = _vaultController.stream.listen(_onVaultStateChanged);
    } catch (e) {
      state = state.copyWith(isLoading: false, failure: e.toString());
    }
  }

  void _onVaultStateChanged(VaultControllerState vaultState) {
    // Lock and unlock need nothing here: relay connections stay alive, and
    // signing fails at the method handler if the vault is locked.
    final previous = _lastVaultState;
    _lastVaultState = vaultState.vaultState;
    if (vaultState.vaultState is NoVault &&
        previous != null &&
        previous is! NoVault) {
      // The vault was wiped (#20): no session may keep answering.
      unawaited(_dropAllSessions());
    }
  }

  /// Stops every relay subscription and forgets every session in memory.
  /// The wipe has already cleared the store.
  Future<void> _dropAllSessions() async {
    _methodRequestTimer?.cancel();
    _methodRequestTimer = null;
    _connectApprovalTimer?.cancel();
    _connectApprovalTimer = null;
    _pendingConnectRequestId = null;

    final ids = {
      for (final session in state.sessions) session.id,
      if (state.pendingApproval != null) state.pendingApproval!.id,
    };
    state = state.copyWith(
      sessions: const [],
      pendingApproval: null,
      pendingMethodRequest: null,
    );
    for (final id in ids) {
      try {
        await _relayService.stopSession(id);
      } catch (e) {
        diogelLog('Nip46Controller: could not stop session $id', error: e);
      }
    }
  }

  void _onInboundEvent(Nip46InboundRelayEvent event) {
    if (!_markProcessed(event.eventId)) {
      diogelLog(
        'Nip46Controller: dropping duplicate event ${event.eventId}',
      );
      return;
    }
    _handleEvent(event);
  }

  void _handleEvent(Nip46InboundRelayEvent event) async {
    // Find the session this event is addressed to.
    Nip46Session? session;
    for (final s in state.sessions) {
      if (s.remoteSignerPubkey == event.recipientPubkey) {
        session = s;
        break;
      }
    }

    if (session == null) {
      diogelLog(
        'Nip46Controller: no session for the event\'s recipient',
      );
      return;
    }

    // Once a session knows its client, only that client may use it. A bunker
    // session waiting for its first connect doesn't know it yet.
    if (session.clientPubkey.isNotEmpty &&
        event.senderPubkey != session.clientPubkey) {
      diogelLog(
        'Nip46Controller: dropping event ${event.eventId} from a key that is not the session\'s client',
      );
      return;
    }

    // Decrypt the request envelope.
    final Nip46Request request;
    final bool usesNip04;
    final String clientPubkeyForDecrypt = session.clientPubkey.isNotEmpty
        ? session.clientPubkey
        : event.senderPubkey;

    try {
      final result = await _crypto.decryptRequest(
        sessionPrivkey: session.remoteSignerPrivkey,
        clientPubkey: clientPubkeyForDecrypt,
        encryptedContent: event.encryptedContent,
      );
      request = result.$1;
      usesNip04 = result.$2;
    } catch (e) {
      diogelLog('Nip46Controller: failed to decrypt event ${event.eventId}', error: e);
      return;
    }

    // For a pending session (bunker flow), only connect is allowed.
    if (session.status == Nip46SessionStatus.pending &&
        request.method == Nip46Method.connect) {
      await _handleConnect(
        session: session,
        request: request,
        usesNip04: usesNip04,
        senderPubkey: event.senderPubkey,
      );
      return;
    }

    // An approved client connecting again, after a restart or a lost
    // connection, is already trusted: acknowledge it and keep its grants.
    // The sender check above means it is the session's own client; a new
    // client needs a new token (a used secret is never accepted again).
    if (session.status == Nip46SessionStatus.active &&
        request.method == Nip46Method.connect) {
      await _publishResponse(
        session: session,
        requestId: request.id,
        result: 'ack',
        usesNip04: usesNip04,
      );
      return;
    }

    // Update usesNip04 flag on session if needed.
    if (usesNip04 && !session.usesNip04) {
      final refreshed = session.copyWith(usesNip04: true);
      await _sessionStore.saveSession(refreshed);
      state = state.copyWith(
        sessions: state.sessions.map((s) => s.id == refreshed.id ? refreshed : s).toList(),
      );
      session = refreshed;
    }

    final vaultState = _vaultController.state.vaultState;
    final activeId = _vaultService.activeIdentity?.publicKey;
    final decision = _approvalPolicy.decide(
      method: request.method,
      session: session,
      vaultState: vaultState,
      activeIdentityPubkey: activeId,
    );

    switch (decision) {
      case Nip46AutoAllow():
        await _dispatchMethod(
          session: session,
          request: request,
          usesNip04: usesNip04,
        );
      case Nip46AutoReject(:final reason):
        await _publishErrorResponse(
          session: session,
          requestId: request.id,
          error: reason,
        );
      case Nip46RequireReview():
        _setPendingMethodRequest(session, request, usesNip04);
      case Nip46RequireUnlock(:final reason):
        await _publishErrorResponse(
          session: session,
          requestId: request.id,
          error: reason,
        );
    }
  }

  Future<void> _handleConnect({
    required Nip46Session session,
    required Nip46Request request,
    required bool usesNip04,
    required String senderPubkey,
  }) async {
    // params: [remoteSignerPubkey, secret, perms?, metadata?]
    final secret = request.optionalParam(1);
    if (session.pendingSecret != null && secret != session.pendingSecret) {
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'Invalid connect secret',
      );
      return;
    }

    // Parse requested permissions from params[2] if present.
    final permsParam = request.optionalParam(2);
    List<Nip46PermissionScope> requestedScopes = const [];
    if (permsParam != null) {
      final parser = const Nip55PermissionParser();
      final parsed = parser.parse(permsParam);
      requestedScopes = parsed.scopes
          .map(_nip55ScopeToNip46)
          .whereType<Nip46PermissionScope>()
          .toList();
    }

    // Update session with the client pubkey and requested scopes (for approval UI).
    // The secret stays until approval, so a second connect while this one
    // waits must carry it too; the sender check then holds it to this client.
    var updatedSession = session.copyWith(
      clientPubkey: senderPubkey,
      usesNip04: usesNip04,
      grantedScopes: requestedScopes,
    );
    await _sessionStore.saveSession(updatedSession);
    state = state.copyWith(
      sessions: state.sessions
          .map((s) => s.id == updatedSession.id ? updatedSession : s)
          .toList(),
      pendingApproval: updatedSession,
    );

    _pendingConnectRequestId = request.id;

    // Start connect approval timeout.
    _connectApprovalTimer?.cancel();
    _connectApprovalTimer = Timer(_connectTimeout, () {
      if (state.pendingApproval?.id == session.id) {
        rejectConnection();
      }
    });
  }

  Future<void> _dispatchMethod({
    required Nip46Session session,
    required Nip46Request request,
    required bool usesNip04,
  }) async {
    final vaultService = _vaultService;
    final identityLocalId = vaultService.activeIdentity?.localId;

    try {
      switch (request.method) {
        case Nip46Method.getPublicKey:
          final pubkey = vaultService.activeIdentity?.publicKey ?? '';
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: pubkey,
            usesNip04: usesNip04,
          );

        case Nip46Method.ping:
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: 'pong',
            usesNip04: usesNip04,
          );

        case Nip46Method.signEvent:
          if (identityLocalId == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'No active identity',
            );
            return;
          }
          final eventJsonRaw = request.optionalParam(0);
          if (eventJsonRaw == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'sign_event: missing event JSON',
            );
            return;
          }
          final Map<String, Object?> eventJson;
          try {
            final decoded = jsonDecode(eventJsonRaw);
            if (decoded is! Map) throw const FormatException('not a map');
            eventJson = decoded.cast();
          } catch (e) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'sign_event: invalid event JSON',
            );
            return;
          }

          final activePubkey = vaultService.activeIdentity?.publicKey ?? '';
          // Inject missing pubkey.
          if (!eventJson.containsKey('pubkey') ||
              (eventJson['pubkey'] as String? ?? '').isEmpty) {
            eventJson['pubkey'] = activePubkey;
          }
          // Reject mismatched pubkey.
          if (eventJson['pubkey'] != activePubkey) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'sign_event: event pubkey does not match active identity',
            );
            return;
          }

          final kind = eventJson['kind'];
          final content = eventJson['content'] ?? '';
          final tags = eventJson['tags'];
          final createdAtRaw = eventJson['created_at'];
          final createdAt = createdAtRaw is int
              ? DateTime.fromMillisecondsSinceEpoch(createdAtRaw * 1000,
                  isUtc: true)
              : DateTime.now().toUtc();

          final draft = NostrEventDraft(
            kind: kind is int ? kind : 1,
            content: content is String ? content : '',
            tags: tags is List
                ? tags
                    .whereType<List>()
                    .map((t) => t.map((e) => e.toString()).toList())
                    .toList()
                : const [],
            createdAt: createdAt,
          );

          final signed = await vaultService.signNostrEvent(
            identityLocalId: identityLocalId,
            draft: draft,
          );
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: jsonEncode(signed.toJson()),
            usesNip04: usesNip04,
          );

        case Nip46Method.nip04Encrypt:
          if (identityLocalId == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'No active identity',
            );
            return;
          }
          final peerPubkey = request.optionalParam(0);
          final plaintext = request.optionalParam(1);
          if (peerPubkey == null || plaintext == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'nip04_encrypt: missing parameters',
            );
            return;
          }
          final ciphertext = await vaultService.nip04Encrypt(
            identityLocalId: identityLocalId,
            peerPubkeyHex: peerPubkey,
            plaintext: plaintext,
          );
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: ciphertext,
            usesNip04: usesNip04,
          );

        case Nip46Method.nip04Decrypt:
          if (identityLocalId == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'No active identity',
            );
            return;
          }
          final peerPubkey = request.optionalParam(0);
          final ciphertextParam = request.optionalParam(1);
          if (peerPubkey == null || ciphertextParam == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'nip04_decrypt: missing parameters',
            );
            return;
          }
          final plaintext2 = await vaultService.nip04Decrypt(
            identityLocalId: identityLocalId,
            peerPubkeyHex: peerPubkey,
            ciphertext: ciphertextParam,
          );
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: plaintext2,
            usesNip04: usesNip04,
          );

        case Nip46Method.nip44Encrypt:
          if (identityLocalId == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'No active identity',
            );
            return;
          }
          final peerPubkey = request.optionalParam(0);
          final plaintext = request.optionalParam(1);
          if (peerPubkey == null || plaintext == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'nip44_encrypt: missing parameters',
            );
            return;
          }
          final ct = await vaultService.nip44Encrypt(
            identityLocalId: identityLocalId,
            peerPubkeyHex: peerPubkey,
            plaintext: plaintext,
          );
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: ct,
            usesNip04: usesNip04,
          );

        case Nip46Method.nip44Decrypt:
          if (identityLocalId == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'No active identity',
            );
            return;
          }
          final peerPubkey = request.optionalParam(0);
          final ciphertextParam = request.optionalParam(1);
          if (peerPubkey == null || ciphertextParam == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'nip44_decrypt: missing parameters',
            );
            return;
          }
          final pt = await vaultService.nip44Decrypt(
            identityLocalId: identityLocalId,
            peerPubkeyHex: peerPubkey,
            ciphertext: ciphertextParam,
          );
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: pt,
            usesNip04: usesNip04,
          );

        case Nip46Method.decryptZapEvent:
          if (identityLocalId == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'No active identity',
            );
            return;
          }
          final eventJsonRaw = request.optionalParam(0);
          if (eventJsonRaw == null) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'decrypt_zap_event: missing event JSON',
            );
            return;
          }
          final Map<String, Object?> zapEventJson;
          try {
            final decoded = jsonDecode(eventJsonRaw);
            if (decoded is! Map) throw const FormatException('not a map');
            zapEventJson = decoded.cast();
          } catch (_) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: 'decrypt_zap_event: invalid event JSON',
            );
            return;
          }
          final result = await vaultService.decryptZapEvent(
            identityLocalId: identityLocalId,
            eventJson: zapEventJson,
          );
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: result,
            usesNip04: usesNip04,
          );

        case Nip46Method.getRelays:
          final relayJson = jsonEncode(session.relays);
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: relayJson,
            usesNip04: usesNip04,
          );

        case Nip46Method.switchRelays:
          // The signer chooses the relays, and the reply is its updated list,
          // or null when nothing changes (NIP-46). Symudol has no relay
          // preference of its own yet, so the session's relays stand. When
          // it does, save the new list, move the session with
          // _relayService.updateSessionRelays, then reply with the list.
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: jsonEncode(null),
            usesNip04: usesNip04,
          );

        case Nip46Method.logout:
          await _publishResponse(
            session: session,
            requestId: request.id,
            result: 'ack',
            usesNip04: usesNip04,
          );
          await revokeSession(session.id);

        case Nip46Method.connect:
          // Handled separately before dispatch.
          break;

        // auth_url challenges (NIP-46 "Auth Challenge") are never sent: they
        // are for signers that authenticate the user somewhere else, and
        // Symudol asks in the app.
        case Nip46Method.unsupported:
          await _publishErrorResponse(
            session: session,
            requestId: request.id,
            error: 'unsupported method: ${request.method.wireName}',
          );
      }

      // Update lastUsedAt.
      final updated = session.copyWith(lastUsedAt: _now());
      await _sessionStore.saveSession(updated);
      state = state.copyWith(
        sessions:
            state.sessions.map((s) => s.id == updated.id ? updated : s).toList(),
      );
    } catch (e) {
      diogelLog('Nip46Controller: error dispatching ${request.method}', error: e);
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'Internal error: ${e.runtimeType}',
      );
    }
  }

  void _setPendingMethodRequest(
    Nip46Session session,
    Nip46Request request,
    bool usesNip04,
  ) {
    _methodRequestTimer?.cancel();
    state = state.copyWith(
      pendingMethodRequest: Nip46PendingMethodRequest(
        sessionId: session.id,
        request: request,
        usesNip04: usesNip04,
      ),
    );
    _methodRequestTimer = Timer(_requestTimeout, () async {
      if (state.pendingMethodRequest?.request.id == request.id) {
        state = state.copyWith(pendingMethodRequest: null);
        await _publishErrorResponse(
          session: session,
          requestId: request.id,
          error: 'Request timed out',
        );
      }
    });
  }

  Future<void> _publishResponse({
    required Nip46Session session,
    required String requestId,
    required String result,
    bool? usesNip04,
  }) async {
    final response = Nip46Response.ok(requestId, result);
    final useNip04 = usesNip04 ?? session.usesNip04;
    final encrypted = await _crypto.encryptResponse(
      sessionPrivkey: session.remoteSignerPrivkey,
      clientPubkey: session.clientPubkey,
      response: response,
      useNip04: useNip04,
    );
    final signed = _crypto.buildSignedResponseEvent(
      sessionPrivkey: session.remoteSignerPrivkey,
      clientPubkey: session.clientPubkey,
      encryptedContent: encrypted,
    );
    await _relayService.publishEvent(session.id, signed.toJson());
  }

  Future<void> _publishErrorResponse({
    required Nip46Session session,
    required String requestId,
    required String error,
  }) async {
    if (session.clientPubkey.isEmpty) return;
    final response = Nip46Response.error(requestId, error);
    try {
      final encrypted = await _crypto.encryptResponse(
        sessionPrivkey: session.remoteSignerPrivkey,
        clientPubkey: session.clientPubkey,
        response: response,
        useNip04: session.usesNip04,
      );
      final signed = _crypto.buildSignedResponseEvent(
        sessionPrivkey: session.remoteSignerPrivkey,
        clientPubkey: session.clientPubkey,
        encryptedContent: encrypted,
      );
      await _relayService.publishEvent(session.id, signed.toJson());
    } catch (e) {
      diogelLog('Nip46Controller: failed to publish error response', error: e);
    }
  }

  /// Starts the session's relays, listening from just before its last use so
  /// requests sent while the app was closed arrive and older ones don't.
  Future<void> _startRelays(Nip46Session session) {
    final lastSeen =
        session.lastUsedAt ?? session.connectedAt ?? session.createdAt;
    final privkey = session.remoteSignerPrivkey;
    return _relayService.startSession(
      session.id,
      session.relays,
      session.remoteSignerPubkey,
      since: lastSeen.subtract(DartNip46RelayService.sinceSkew),
      authSigner: (relayUrl, challenge) => _crypto
          .buildSignedRelayAuthEvent(
            sessionPrivkey: privkey,
            relayUrl: relayUrl,
            challenge: challenge,
          )
          .toJson(),
    );
  }

  /// The id for the reply to a connect: the client's request id in the bunker
  /// flow. A nostrconnect reply answers no request, so it gets a fresh id.
  String _connectResponseId(Nip46Session session) {
    if (session.initiatedBy == Nip46ConnectionInitiator.nostrconnect) {
      return _generateId();
    }
    return _pendingConnectRequestId ?? _generateId();
  }

  bool _markProcessed(String eventId) {
    if (_processedEventIds.containsKey(eventId)) return false;
    if (_processedEventIds.length >= _maxDedupCacheSize) {
      _processedEventIds.remove(_processedEventIds.keys.first);
    }
    _processedEventIds[eventId] = true;
    return true;
  }

  String _generateId() {
    return List.generate(16, (_) => _random.nextInt(16).toRadixString(16))
        .join();
  }

  String _generatePrivkey() {
    final bytes = List.generate(32, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Nip46PermissionScope? _nip55ScopeToNip46(dynamic nip55Scope) {
    // Map Nip55PermissionScope wire names to Nip46PermissionScope equivalents.
    // Both use the same wire name format.
    final wire = (nip55Scope?.wire as String?) ?? '';
    return switch (wire) {
      'get_public_key' => const Nip46GetPublicKeyScope(),
      'sign_event' => const Nip46SignEventScope(),
      String s when s.startsWith('sign_event:') =>
        Nip46SignEventScope(int.tryParse(s.substring('sign_event:'.length))),
      'nip04_encrypt' => const Nip46Nip04EncryptScope(),
      'nip04_decrypt' => const Nip46Nip04DecryptScope(),
      'nip44_encrypt' => const Nip46Nip44EncryptScope(),
      'nip44_decrypt' => const Nip46Nip44DecryptScope(),
      'decrypt_zap_event' => const Nip46DecryptZapEventScope(),
      _ => null,
    };
  }

  @override
  void dispose() {
    _inboundSub?.cancel();
    _vaultSub?.cancel();
    _methodRequestTimer?.cancel();
    _connectApprovalTimer?.cancel();
    _relayService.dispose();
    super.dispose();
  }
}
