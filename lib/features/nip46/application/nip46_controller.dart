import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:symudol/app/diogel_log.dart';
import 'package:symudol/features/nip55/domain/nip55_approval_timeframe.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_parser.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_service.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

import '../data/dart_nip46_crypto.dart';
import '../data/dart_nip46_relay_service.dart';
import '../data/nip46_token_codec.dart';
import '../domain/nip46_approval_policy.dart';
import '../domain/nip46_connection_token.dart';
import '../domain/nip46_method.dart';
import '../domain/nip46_pending_method_request.dart';
import '../domain/nip46_permission_grant.dart';
import '../domain/nip46_permission_scope.dart';
import '../domain/nip46_relay_event.dart';
import '../domain/nip46_request.dart';
import '../domain/nip46_response.dart';
import '../domain/nip46_session.dart';
import '../domain/nip46_session_store.dart';
import '../domain/nip46_sign_event.dart';
import 'nip46_background.dart';

class Nip46State {
  final List<Nip46Session> sessions;
  // Session awaiting user approval for a new connection.
  final Nip46Session? pendingApproval;
  // Method requests awaiting user review, oldest first.
  final List<Nip46PendingMethodRequest> pendingMethodRequests;
  final bool isLoading;
  final String? failure;
  final String? lastSuccessMessage;

  /// Whether the user wants remote signing kept running while Symudol is in
  /// the background (#29).
  final bool runInBackground;

  const Nip46State({
    this.sessions = const [],
    this.pendingApproval,
    this.pendingMethodRequests = const [],
    this.isLoading = false,
    this.failure,
    this.lastSuccessMessage,
    this.runInBackground = false,
  });

  bool get hasPendingAction =>
      pendingApproval != null || pendingMethodRequests.isNotEmpty;

  Nip46State copyWith({
    List<Nip46Session>? sessions,
    Object? pendingApproval = _sentinel,
    List<Nip46PendingMethodRequest>? pendingMethodRequests,
    bool? isLoading,
    Object? failure = _sentinel,
    Object? lastSuccessMessage = _sentinel,
    bool? runInBackground,
  }) {
    return Nip46State(
      sessions: sessions ?? this.sessions,
      pendingApproval: pendingApproval == _sentinel
          ? this.pendingApproval
          : pendingApproval as Nip46Session?,
      pendingMethodRequests:
          pendingMethodRequests ?? this.pendingMethodRequests,
      isLoading: isLoading ?? this.isLoading,
      failure: failure == _sentinel ? this.failure : failure as String?,
      lastSuccessMessage: lastSuccessMessage == _sentinel
          ? this.lastSuccessMessage
          : lastSuccessMessage as String?,
      runInBackground: runInBackground ?? this.runInBackground,
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
  static const Duration defaultRequestTimeout = Duration(seconds: 60);
  static const Duration _connectTimeout = Duration(seconds: 120);

  /// Requests one session may have waiting for review. Beyond this a client
  /// is refused at once, so it cannot flood the queue (diogel-io/symudol#27).
  static const int maxPendingRequestsPerSession = 20;

  static const String _signEventPubkeyMismatch =
      'sign_event: event pubkey does not match active identity';

  final Nip46SessionStore _sessionStore;
  final VaultService _vaultService;
  final VaultController _vaultController;
  final Nip46RelayService _relayService;
  final DartNip46Crypto _crypto;
  final Nip46ApprovalPolicy _approvalPolicy;
  final Nip46Notifier _notifier;
  final DateTime Function() _now;
  final Random _random;

  /// How long a request waits for review, from when it arrives.
  final Duration _requestTimeout;

  StreamSubscription<Nip46InboundRelayEvent>? _inboundSub;
  StreamSubscription<VaultControllerState>? _vaultSub;
  VaultState? _lastVaultState;

  // LRU dedup cache for processed event IDs.
  final LinkedHashMap<String, bool> _processedEventIds = LinkedHashMap();

  // Requests that arrived while the vault was locked, oldest first, by
  // session and request id (#29).
  final Map<String, _HeldRequest> _heldRequests = {};

  // Session saves, one at a time (see _updateSession).
  Future<void> _saveQueue = Future.value();

  // Timeout for each request awaiting review, by [Nip46PendingMethodRequest.key].
  final Map<String, Timer> _methodRequestTimers = {};
  // Timer for pending connect approval timeout.
  Timer? _connectApprovalTimer;

  Nip46Controller({
    required Nip46SessionStore sessionStore,
    required VaultService vaultService,
    required VaultController vaultController,
    required Nip46RelayService relayService,
    required DartNip46Crypto crypto,
    Nip46ApprovalPolicy approvalPolicy = const Nip46ApprovalPolicy(),
    Nip46Notifier notifier = const NoopNip46Notifier(),
    DateTime Function()? now,
    Duration requestTimeout = defaultRequestTimeout,
  })  : _requestTimeout = requestTimeout,
        _sessionStore = sessionStore,
        _vaultService = vaultService,
        _vaultController = vaultController,
        _relayService = relayService,
        _crypto = crypto,
        _approvalPolicy = approvalPolicy,
        _notifier = notifier,
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
    // A link can arrive as the controller starts: the store has the vault's
    // key only once the sessions are read (#31, #32).
    await _loadSessions();
    // The same link opened again, or a client that is already paired (#31).
    if (state.sessions.any(
      (s) =>
          s.clientPubkey == parsed.clientPubkey &&
          s.status == Nip46SessionStatus.active,
    )) {
      throw const Nip46AlreadyConnectedException();
    }
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
      // Requested by the client; saved only if the user approves them (#28).
      requestedScopes: _requestedScopes(parsed.perms),
      status: Nip46SessionStatus.pending,
      createdAt: _now(),
      pendingSecret: parsed.secret,
      initiatedBy: Nip46ConnectionInitiator.nostrconnect,
    );

    // No relay is opened until the user approves: the URI can come from a
    // link any page opens, and its relays are the client's choice (#31). A
    // rejected connection so never reaches the network.
    await _sessionStore.saveSession(session);

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
  ///
  /// With a [timeframe] other than just once, the permissions the client
  /// asked for are remembered as allow grants for the active identity, except
  /// a broad sign_event, which is reviewed every time (#28).
  Future<void> approveConnection({
    Nip55ApprovalTimeframe timeframe = Nip55ApprovalTimeframe.justOnce,
  }) async {
    final pending = state.pendingApproval;
    if (pending == null) return;

    _connectApprovalTimer?.cancel();
    _connectApprovalTimer = null;

    final identity = _vaultService.activeIdentity?.publicKey;
    final expiresAt = _expiresAtFor(timeframe);
    final grants = [
      if (identity != null && timeframe != Nip55ApprovalTimeframe.justOnce)
        for (final scope in pending.requestedScopes)
          Nip46PermissionGrant(
            scope: scope,
            decision: Nip55PermissionDecision.allow,
            identityPubkey: identity,
            createdAt: _now(),
            expiresAt: expiresAt,
          ),
    ].where((grant) => grant.isRememberable).toList();

    final approved = pending.copyWith(
      status: Nip46SessionStatus.active,
      requestedScopes: const [],
      grants: grants,
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

    // A nostrconnect session opens its relays only now (#31). The connect
    // response below waits for them to connect.
    if (pending.initiatedBy == Nip46ConnectionInitiator.nostrconnect) {
      await _startRelays(approved);
    }

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

  /// Called by the approval UI to approve the queued request with [key].
  /// Does nothing if it has already been answered, for example timed out.
  /// A [timeframe] other than just once remembers the decision (#28).
  Future<void> approveMethodRequest(
    String key, {
    Nip55ApprovalTimeframe timeframe = Nip55ApprovalTimeframe.justOnce,
  }) async {
    final pending = _takePendingMethodRequest(key);
    if (pending == null) return;
    final session = _sessionById(pending.sessionId);
    if (session == null) return;

    final active = _vaultService.activeIdentity;
    if (active?.localId != pending.identityLocalId ||
        active?.publicKey != pending.identityPubkey) {
      await _publishErrorResponse(
        session: session,
        requestId: pending.request.id,
        error: 'Active identity changed',
      );
      return;
    }

    await _rememberDecision(
      pending,
      Nip55PermissionDecision.allow,
      timeframe,
    );
    await _dispatchMethod(
      session: _sessionById(pending.sessionId) ?? session,
      request: pending.request,
      usesNip04: pending.usesNip04,
    );
  }

  /// Called by the approval UI to reject the queued request with [key].
  /// A [timeframe] other than just once remembers the rejection (#28).
  Future<void> rejectMethodRequest(
    String key, {
    Nip55ApprovalTimeframe timeframe = Nip55ApprovalTimeframe.justOnce,
  }) async {
    final pending = _takePendingMethodRequest(key);
    if (pending == null) return;
    final session = _sessionById(pending.sessionId);
    if (session == null) return;

    await _rememberDecision(
      pending,
      Nip55PermissionDecision.reject,
      timeframe,
    );
    await _publishErrorResponse(
      session: session,
      requestId: pending.request.id,
      error: 'User rejected the request',
    );
  }

  /// Saves [decision] on [pending]'s scope for the identity it was reviewed
  /// under, replacing any earlier decision for that scope and identity.
  /// Nothing is saved just once, or for a broad sign_event allow.
  Future<void> _rememberDecision(
    Nip46PendingMethodRequest pending,
    Nip55PermissionDecision decision,
    Nip55ApprovalTimeframe timeframe,
  ) async {
    if (timeframe == Nip55ApprovalTimeframe.justOnce) return;
    final session = _sessionById(pending.sessionId);
    final scope = _requestScope(pending.request, pending.identityPubkey);
    if (session == null || scope == null) return;
    final grant = Nip46PermissionGrant(
      scope: scope,
      decision: decision,
      identityPubkey: pending.identityPubkey,
      createdAt: _now(),
      expiresAt: _expiresAtFor(timeframe),
    );
    if (!grant.isRememberable) return;

    // The request is already out of the queue: failing to remember the
    // decision must not stop it being answered.
    try {
      await _updateSession(
        session.id,
        (latest) => latest.copyWith(grants: _withGrant(latest.grants, grant)),
      );
    } catch (e) {
      diogelLog('Nip46Controller: could not remember a decision', error: e);
      // A rejection still applies, in memory, so a failed write cannot leave
      // an earlier allow for the same scope in force. The next successful
      // save of this session stores it.
      final latest = _sessionById(session.id);
      if (decision == Nip55PermissionDecision.reject && latest != null) {
        final rejected = latest.copyWith(
          grants: _withGrant(latest.grants, grant),
        );
        state = state.copyWith(
          sessions: [
            for (final s in state.sessions) s.id == rejected.id ? rejected : s,
          ],
        );
      }
    }
  }

  /// [grants] with [grant] in place of any earlier decision for the same
  /// scope and identity.
  static List<Nip46PermissionGrant> _withGrant(
    List<Nip46PermissionGrant> grants,
    Nip46PermissionGrant grant,
  ) => [
    for (final g in grants)
      if (g.identityPubkey != grant.identityPubkey ||
          g.scope.wire != grant.scope.wire)
        g,
    grant,
  ];

  /// The scope a remembered decision on [request] covers: `sign_event` with
  /// its event's kind, or the method's own scope.
  Nip46PermissionScope? _requestScope(Nip46Request request, String pubkey) {
    int? kind;
    if (request.method == Nip46Method.signEvent) {
      try {
        kind = Nip46SignEvent.parse(
          request.optionalParam(0),
          activePubkey: pubkey,
        ).draft.kind;
      } on Nip46SignEventException {
        return null;
      }
    }
    return Nip46ApprovalPolicy.scopeFor(request.method, kind);
  }

  DateTime? _expiresAtFor(Nip55ApprovalTimeframe timeframe) =>
      switch (timeframe) {
        Nip55ApprovalTimeframe.justOnce => null,
        Nip55ApprovalTimeframe.eightHours =>
          _now().add(const Duration(hours: 8)),
        Nip55ApprovalTimeframe.always => null,
      };

  /// Removes the queued request with [key] and cancels its timeout.
  Nip46PendingMethodRequest? _takePendingMethodRequest(String key) {
    Nip46PendingMethodRequest? pending;
    for (final queued in state.pendingMethodRequests) {
      if (queued.key == key) pending = queued;
    }
    if (pending == null) return null;
    _methodRequestTimers.remove(key)?.cancel();
    state = state.copyWith(
      pendingMethodRequests: state.pendingMethodRequests
          .where((queued) => queued.key != key)
          .toList(),
    );
    return pending;
  }

  Nip46Session? _sessionById(String id) {
    for (final session in state.sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  /// Revokes a session — stops relays, deletes from store, removes from state.
  Future<void> revokeSession(String sessionId) async {
    // Its waiting requests are answered first, while the relays still run.
    final session = _sessionById(sessionId);
    // Out of state at once, so no save started from here on can keep it
    // (see [_updateSession]); its grants go with it (#28).
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != sessionId).toList(),
    );
    // Its queued and held requests (#29) are all taken before the first
    // await, so no timeout can answer one a second time or remove one
    // mid-loop, and an answer that fails cannot skip the relay stop and
    // delete below.
    final requestIds = [
      for (final pending in state.pendingMethodRequests.toList())
        if (pending.sessionId == sessionId &&
            _takePendingMethodRequest(pending.key) != null)
          pending.request.id,
      for (final entry in _heldRequests.entries.toList())
        if (entry.value.sessionId == sessionId)
          ?_takeHeldRequest(entry.key)?.request.id,
    ];
    for (final requestId in requestIds) {
      if (session == null) continue;
      try {
        await _publishErrorResponse(
          session: session,
          requestId: requestId,
          error: 'Session has been revoked.',
        );
      } catch (e) {
        diogelLog('Nip46Controller: could not answer a request', error: e);
      }
    }
    try {
      await _relayService.stopSession(sessionId);
    } finally {
      // Even when the relays fail to stop, or the session would come back on
      // the next start. After any save already in flight, which would
      // otherwise write it back.
      await _enqueueSave(() => _sessionStore.deleteSession(sessionId));
    }
  }

  /// Turns background running on or off (#29). The app starts the service
  /// when it goes to the background with this on and a session active.
  Future<void> setRunInBackground(bool value) async {
    state = state.copyWith(runInBackground: value);
    try {
      await _sessionStore.setRunInBackground(value);
    } catch (e) {
      diogelLog('Nip46Controller: could not save background running', error: e);
    }
  }

  /// Whether going to the background should start the service.
  bool get wantsBackgroundService =>
      state.runInBackground &&
      state.sessions.any((s) => s.status == Nip46SessionStatus.active);

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
    _inboundSub = _relayService.inboundEvents.listen(_onInboundEvent);
    // Listening from the start, so an unlock before the sessions are read
    // still loads them (#32).
    _lastVaultState = _vaultController.state.vaultState;
    _vaultSub = _vaultController.stream.listen(_onVaultStateChanged);
    await _loadSessions();
  }

  // Whether the stored sessions have been read. Until then no relay runs.
  bool _sessionsLoaded = false;
  Future<void>? _loading;

  /// Reads the stored sessions and starts their relays. Their keys are
  /// encrypted under the vault, so with the vault locked this waits for the
  /// next unlock (#32).
  Future<void> _loadSessions() =>
      _loading ??= _readSessions().whenComplete(() => _loading = null);

  Future<void> _readSessions() async {
    if (_sessionsLoaded) return;
    if (!await _provideStorageKey()) {
      state = state.copyWith(isLoading: false);
      return;
    }
    try {
      final sessions = await _sessionStore.listSessions();
      final runInBackground = await _sessionStore.getRunInBackground();
      _sessionsLoaded = true;
      // A session made between the unlock and now, such as a new bunker
      // token, is kept.
      final loadedIds = {for (final s in sessions) s.id};
      state = state.copyWith(
        sessions: [
          ...sessions,
          for (final s in state.sessions)
            if (!loadedIds.contains(s.id)) s,
        ],
        isLoading: false,
        runInBackground: runInBackground,
      );

      for (final session in sessions) {
        if (session.status == Nip46SessionStatus.active) {
          await _startRelays(session);
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, failure: e.toString());
    }
  }

  /// Gives the store the vault's NIP-46 storage key, or returns false while
  /// the vault is locked.
  Future<bool> _provideStorageKey() async {
    try {
      final key = await _vaultService.nip46StorageKey();
      _sessionStore.useStorageKey(key);
      key.fillRange(0, key.length, 0);
      return true;
    } on VaultLockedException {
      return false;
    }
  }

  void _onVaultStateChanged(VaultControllerState vaultState) {
    // Relay connections stay alive across a lock. Requests that arrived while
    // it was locked were held, and are decided now (#29).
    final previous = _lastVaultState;
    _lastVaultState = vaultState.vaultState;
    if (vaultState.vaultState is VaultUnlocked && previous is! VaultUnlocked) {
      unawaited(_onUnlocked());
    }
    if (vaultState.vaultState is NoVault &&
        previous != null &&
        previous is! NoVault) {
      // The vault was wiped (#20): no session may keep answering.
      unawaited(_dropAllSessions());
    }
  }

  Future<void> _onUnlocked() async {
    // Given on every unlock: a vault set up after a wipe has a new key.
    if (_sessionsLoaded) {
      await _provideStorageKey();
    } else {
      await _loadSessions();
    }
    await _releaseHeldRequests();
  }

  /// Stops every relay subscription and forgets every session in memory.
  /// The wipe has already cleared the store.
  Future<void> _dropAllSessions() async {
    for (final timer in _methodRequestTimers.values) {
      timer.cancel();
    }
    _methodRequestTimers.clear();
    final queued = state.pendingMethodRequests;
    final sessions = state.sessions;
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
      pendingMethodRequests: const [],
      // The wipe cleared the store, the setting with it.
      runInBackground: false,
    );
    // Every queued or held request gets its one answer before the relays
    // stop. Held ones are answered from the sessions as they were, all taken
    // before the first await so no timeout can remove one mid-loop.
    final heldAll = _heldRequests.values.toList();
    _heldRequests.clear();
    for (final held in heldAll) {
      held.timer.cancel();
      unawaited(
        _notifySafely(() => _notifier.cancelHeldRequest(held.sessionId)),
      );
    }
    for (final held in heldAll) {
      for (final session in sessions) {
        if (session.id != held.sessionId) continue;
        try {
          await _publishErrorResponse(
            session: session,
            requestId: held.request.id,
            error: 'The Symudol vault was erased',
          );
        } catch (e) {
          diogelLog('Nip46Controller: could not answer a request', error: e);
        }
      }
    }
    for (final pending in queued) {
      for (final session in sessions) {
        if (session.id != pending.sessionId) continue;
        try {
          await _publishErrorResponse(
            session: session,
            requestId: pending.request.id,
            error: 'The Symudol vault was erased',
          );
        } catch (e) {
          diogelLog('Nip46Controller: could not answer a request', error: e);
        }
      }
    }
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
      try {
        await _publishResponse(
          session: session,
          requestId: request.id,
          result: 'ack',
          usesNip04: usesNip04,
        );
      } catch (e) {
        diogelLog('Nip46Controller: failed to acknowledge a reconnect', error: e);
      }
      return;
    }

    // Update usesNip04 flag on session if needed.
    if (usesNip04 && !session.usesNip04) {
      final refreshed = await _updateSession(
        session.id,
        (latest) => latest.copyWith(usesNip04: true),
      );
      // Revoked meanwhile: nothing to answer with.
      if (refreshed == null) return;
      session = refreshed;
    }

    await _decide(session, request, usesNip04, arrivedAt: _now());
  }

  /// Answers [request] by the policy: signs it, refuses it, queues it for
  /// review, or holds it while the vault is locked. A held request comes back
  /// here on unlock with its original [arrivedAt], so it keeps the time it
  /// has left (#29).
  Future<void> _decide(
    Nip46Session session,
    Nip46Request request,
    bool usesNip04, {
    required DateTime arrivedAt,
  }) async {
    final vaultState = _vaultController.state.vaultState;
    final activeId = _vaultService.activeIdentity?.publicKey;

    // A sign_event that can only fail is refused now: never reviewed, and
    // never matched against a remembered decision. Grants are per kind, so
    // the policy needs the event's (#27, #28).
    int? signEventKind;
    if (request.method == Nip46Method.signEvent &&
        vaultState is VaultUnlocked &&
        activeId != null) {
      final Nip46SignEvent event;
      try {
        event = Nip46SignEvent.parse(
          request.optionalParam(0),
          activePubkey: activeId,
        );
      } on Nip46SignEventException catch (e) {
        await _publishErrorResponse(
          session: session,
          requestId: request.id,
          error: e.message,
        );
        return;
      }
      if (event.pubkey != activeId) {
        await _publishErrorResponse(
          session: session,
          requestId: request.id,
          error: _signEventPubkeyMismatch,
        );
        return;
      }
      signEventKind = event.draft.kind;
    }

    final decision = _approvalPolicy.decide(
      method: request.method,
      session: session,
      vaultState: vaultState,
      activeIdentityPubkey: activeId,
      signEventKind: signEventKind,
      now: _now(),
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
        await _queueMethodRequest(
          session,
          request,
          usesNip04,
          arrivedAt: arrivedAt,
        );
      case Nip46RequireUnlock(:final reason):
        // Locked: held, never signed, and decided after unlock (#29). With
        // no vault or no active identity there is nothing to wait for.
        if (vaultState is VaultLocked || vaultState is SessionExpired) {
          await _holdRequest(session, request, usesNip04, arrivedAt);
        } else {
          await _publishErrorResponse(
            session: session,
            requestId: request.id,
            error: reason,
          );
        }
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
    final requestedScopes = _requestedScopes(request.optionalParam(2));

    // Update session with the client pubkey and requested scopes (for approval UI).
    // The secret stays until approval, so a second connect while this one
    // waits must carry it too; the sender check then holds it to this client.
    var updatedSession = session.copyWith(
      clientPubkey: senderPubkey,
      usesNip04: usesNip04,
      requestedScopes: requestedScopes,
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

    // Set when the switch completes. Its early returns answer with an error
    // and leave lastUsedAt as it was.
    var answered = false;
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
          final activePubkey = vaultService.activeIdentity?.publicKey ?? '';
          final Nip46SignEvent event;
          try {
            event = Nip46SignEvent.parse(
              request.optionalParam(0),
              activePubkey: activePubkey,
            );
          } on Nip46SignEventException catch (e) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: e.message,
            );
            return;
          }
          if (event.pubkey != activePubkey) {
            await _publishErrorResponse(
              session: session,
              requestId: request.id,
              error: _signEventPubkeyMismatch,
            );
            return;
          }
          final draft = event.draft;

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

      answered = true;
    } catch (e) {
      diogelLog('Nip46Controller: error dispatching ${request.method}', error: e);
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'Internal error: ${e.runtimeType}',
      );
    }
    if (!answered) return;

    // Outside the try above: the client already has its answer, so a failed
    // save must not send it a second, contradictory one. Applied to the
    // latest session, so a decision remembered while this request was
    // signed is kept, and skipped for one revoked meanwhile, such as by
    // logout (#28).
    try {
      await _updateSession(
        session.id,
        (latest) => latest.copyWith(lastUsedAt: _now()),
      );
    } catch (e) {
      diogelLog('Nip46Controller: could not record lastUsedAt', error: e);
    }
  }

  /// Applies [change] to the session's latest state, stores it and puts it
  /// in state, one save at a time. Returns the saved session, or null when
  /// the session is gone, revoked or wiped, in which case nothing is saved.
  ///
  /// Every change to a stored session's grants or lastUsedAt goes through
  /// here, so no save writes back an older copy over a decision made while
  /// it waited, and none can bring back a revoked session (#28).
  Future<Nip46Session?> _updateSession(
    String id,
    Nip46Session Function(Nip46Session latest) change,
  ) {
    return _enqueueSave(() async {
      final latest = _sessionById(id);
      if (latest == null) return null;
      final updated = change(latest);
      await _sessionStore.saveSession(updated);
      // Revoked while it was being written: undo the write.
      if (_sessionById(id) == null) {
        await _sessionStore.deleteSession(id);
        return null;
      }
      state = state.copyWith(
        sessions: [
          for (final s in state.sessions) s.id == id ? updated : s,
        ],
      );
      return updated;
    });
  }

  /// Runs [save] after every save queued before it. A failure is returned
  /// to the caller and doesn't stop later saves.
  Future<T> _enqueueSave<T>(Future<T> Function() save) {
    final result = _saveQueue.then((_) => save());
    _saveQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Queues [request] for review, timing out [_requestTimeout] after it
  /// arrived.
  Future<void> _queueMethodRequest(
    Nip46Session session,
    Nip46Request request,
    bool usesNip04, {
    required DateTime arrivedAt,
  }) async {
    final identity = _vaultService.activeIdentity;
    if (identity == null) {
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'No active identity',
      );
      return;
    }
    final pending = Nip46PendingMethodRequest(
      sessionId: session.id,
      request: request,
      usesNip04: usesNip04,
      identityLocalId: identity.localId,
      identityPubkey: identity.publicKey,
      receivedAt: arrivedAt,
      clientPubkey: session.clientPubkey,
      clientName: session.clientName,
      clientUrl: session.clientUrl,
    );
    final queued = state.pendingMethodRequests;
    // The same request sent again, queued or still held for unlock (#29):
    // the first one gets the answer.
    if (queued.any((q) => q.key == pending.key) ||
        _heldRequests.containsKey(pending.key)) {
      return;
    }
    if (_waitingFor(session.id) >= maxPendingRequestsPerSession) {
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'Too many pending requests',
      );
      return;
    }

    final left = _timeLeft(arrivedAt);
    if (left == null) {
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'Request timed out',
      );
      return;
    }
    state = state.copyWith(pendingMethodRequests: [...queued, pending]);
    _methodRequestTimers[pending.key] = Timer(left, () async {
      if (_takePendingMethodRequest(pending.key) == null) return;
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: 'Request timed out',
      );
    });
  }

  /// How long a request that arrived at [arrivedAt] may still wait, or null
  /// once its [_requestTimeout] has passed.
  Duration? _timeLeft(DateTime arrivedAt) {
    final left = _requestTimeout - _now().difference(arrivedAt);
    return left > Duration.zero ? left : null;
  }

  /// Requests from [sessionId] waiting for review or for unlock.
  int _waitingFor(String sessionId) =>
      state.pendingMethodRequests.where((q) => q.sessionId == sessionId).length +
      _heldRequests.values.where((h) => h.sessionId == sessionId).length;

  /// Holds [request] until the vault unlocks, or until it times out
  /// [_requestTimeout] after it arrived, and notifies the user (#29).
  Future<void> _holdRequest(
    Nip46Session session,
    Nip46Request request,
    bool usesNip04,
    DateTime arrivedAt,
  ) async {
    final key = '${session.id}/${request.id}';
    // The same request sent again, held or still queued for review from
    // before the lock: the first one gets the answer.
    if (_heldRequests.containsKey(key) ||
        state.pendingMethodRequests.any((q) => q.key == key)) {
      return;
    }
    final left = _timeLeft(arrivedAt);
    if (_waitingFor(session.id) >= maxPendingRequestsPerSession ||
        left == null) {
      await _publishErrorResponse(
        session: session,
        requestId: request.id,
        error: left == null ? 'Request timed out' : 'Too many pending requests',
      );
      return;
    }
    _heldRequests[key] = _HeldRequest(
      sessionId: session.id,
      request: request,
      usesNip04: usesNip04,
      arrivedAt: arrivedAt,
      timer: Timer(left, () async {
        final held = _takeHeldRequest(key);
        if (held == null) return;
        final current = _sessionById(held.sessionId) ?? session;
        await _publishErrorResponse(
          session: current,
          requestId: held.request.id,
          error: 'Request timed out',
        );
      }),
    );
    await _notifySafely(() => _notifier.showHeldRequest(session.id));
  }

  /// Removes the held request with [key], cancels its timer, and clears its
  /// session's notice when it was the last one.
  _HeldRequest? _takeHeldRequest(String key) {
    final held = _heldRequests.remove(key);
    if (held == null) return null;
    held.timer.cancel();
    if (!_heldRequests.values.any((h) => h.sessionId == held.sessionId)) {
      unawaited(
        _notifySafely(() => _notifier.cancelHeldRequest(held.sessionId)),
      );
    }
    return held;
  }

  /// On unlock, decides every held request as if it had just arrived, but
  /// with the time it has left (#29).
  Future<void> _releaseHeldRequests() async {
    for (final key in _heldRequests.keys.toList()) {
      final held = _takeHeldRequest(key);
      if (held == null) continue;
      final session = _sessionById(held.sessionId);
      if (session == null) continue;
      try {
        await _decide(
          session,
          held.request,
          held.usesNip04,
          arrivedAt: held.arrivedAt,
        );
      } catch (e) {
        diogelLog('Nip46Controller: could not decide a held request', error: e);
      }
    }
  }

  /// A notification that cannot be shown must not stop a request.
  Future<void> _notifySafely(Future<void> Function() notify) async {
    try {
      await notify();
    } catch (e) {
      diogelLog('Nip46Controller: could not update the notification', error: e);
    }
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

  /// The scopes in a client's `perms` (NIP-46: `method[:kind]`, comma
  /// separated), from a connect request or a nostrconnect:// URI.
  List<Nip46PermissionScope> _requestedScopes(String? perms) {
    if (perms == null || perms.isEmpty) return const [];
    return const Nip55PermissionParser()
        .parse(perms)
        .scopes
        .map(_nip55ScopeToNip46)
        .whereType<Nip46PermissionScope>()
        .toList();
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
    for (final timer in _methodRequestTimers.values) {
      timer.cancel();
    }
    for (final held in _heldRequests.values) {
      held.timer.cancel();
    }
    _connectApprovalTimer?.cancel();
    _relayService.dispose();
    super.dispose();
  }
}

/// A request that arrived while the vault was locked (#29).
class _HeldRequest {
  final String sessionId;
  final Nip46Request request;
  final bool usesNip04;
  final DateTime arrivedAt;
  final Timer timer;

  _HeldRequest({
    required this.sessionId,
    required this.request,
    required this.usesNip04,
    required this.arrivedAt,
    required this.timer,
  });
}
