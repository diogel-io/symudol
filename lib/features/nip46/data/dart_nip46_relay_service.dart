import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:symudol/app/diogel_log.dart';

import '../domain/nip46_relay_event.dart';

/// Signs a NIP-42 AUTH event (kind 22242) for [relayUrl] and [challenge]
/// with the session's key, returning the signed event JSON.
typedef Nip46RelayAuthSigner =
    Map<String, Object?> Function(String relayUrl, String challenge);

/// One open connection to a relay.
abstract interface class Nip46RelaySocket {
  /// Frames from the relay. Done when the connection closes.
  Stream<dynamic> get messages;

  void add(String data);

  Future<void> close();
}

/// Opens a connection to a relay, or throws.
typedef Nip46RelaySocketConnector =
    Future<Nip46RelaySocket> Function(String url);

abstract interface class Nip46RelayService {
  /// Starts relay subscriptions for [sessionId] on [relays], listening for
  /// kind 24133 events addressed to [remoteSignerPubkey] created at or after
  /// [since]. [authSigner] answers NIP-42 AUTH challenges; without it they
  /// are ignored.
  Future<void> startSession(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey, {
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  });

  /// Updates the relay list for an existing session.
  Future<void> updateSessionRelays(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey, {
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  });

  /// Stops all relay connections for [sessionId].
  Future<void> stopSession(String sessionId);

  /// Publishes a pre-signed kind 24133 event JSON to all healthy relays for [sessionId].
  /// Retries up to 5 times with exponential back-off.
  Future<void> publishEvent(String sessionId, Map<String, Object?> signedEventJson);

  /// Connects every relay that is not connected now, without waiting for its
  /// back-off. Called when the app returns to the foreground.
  Future<void> reconnectAll();

  /// Inbound kind 24133 events addressed to a tracked signer pubkey.
  Stream<Nip46InboundRelayEvent> get inboundEvents;

  void dispose();
}

class DartNip46RelayService implements Nip46RelayService {
  static const int _maxRetries = 5;
  static const int _unhealthyThreshold = 10;
  static const Duration _subscriptionRefreshInterval = Duration(seconds: 30);
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _maxReconnectDelay = Duration(seconds: 60);

  /// How far before the previous subscription a re-subscription reaches,
  /// for clock skew between the client, the relay and this phone.
  static const Duration sinceSkew = Duration(minutes: 5);

  /// How long an unhealthy relay is skipped before it is tried again.
  static const Duration unhealthyCooldown = Duration(minutes: 2);

  final Nip46RelaySocketConnector _connector;
  final DateTime Function() _now;
  final Duration _reconnectBaseDelay;
  final Duration _publishBaseDelay;

  final _eventController =
      StreamController<Nip46InboundRelayEvent>.broadcast();

  // sessionId -> _SessionState
  final Map<String, _SessionState> _sessions = {};

  DartNip46RelayService({
    Nip46RelaySocketConnector? connector,
    DateTime Function()? now,
    Duration reconnectBaseDelay = const Duration(seconds: 2),
    Duration publishBaseDelay = const Duration(seconds: 1),
  }) : _connector = connector ?? _connectWebSocket,
       _now = now ?? DateTime.now,
       _reconnectBaseDelay = reconnectBaseDelay,
       _publishBaseDelay = publishBaseDelay;

  static Future<Nip46RelaySocket> _connectWebSocket(String url) async {
    final socket = await WebSocket.connect(url).timeout(_connectTimeout);
    // A socket left half-open by a network change is closed when a ping goes
    // unanswered, and closing it starts a reconnect.
    socket.pingInterval = _pingInterval;
    return _IoRelaySocket(socket);
  }

  /// The delay before reconnect attempt [attempt] (0-based): doubling from
  /// [base], capped at a minute.
  static Duration reconnectDelay(
    int attempt, {
    Duration base = const Duration(seconds: 2),
  }) {
    final ms = base.inMilliseconds * (1 << attempt.clamp(0, 16));
    return Duration(milliseconds: min(ms, _maxReconnectDelay.inMilliseconds));
  }

  @override
  Stream<Nip46InboundRelayEvent> get inboundEvents => _eventController.stream;

  @override
  Future<void> startSession(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey, {
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  }) async {
    await stopSession(sessionId);
    final state = _SessionState(
      remoteSignerPubkey: remoteSignerPubkey,
      since: since,
      authSigner: authSigner,
      relays: Map.fromEntries(
        relays.map((url) => MapEntry(url, _RelayConnection(url))),
      ),
    );
    _sessions[sessionId] = state;
    for (final conn in state.relays.values) {
      _connectRelay(sessionId, conn);
    }
  }

  @override
  Future<void> updateSessionRelays(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey, {
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  }) async {
    final existing = _sessions[sessionId];
    if (existing == null) {
      return startSession(
        sessionId,
        relays,
        remoteSignerPubkey,
        since: since,
        authSigner: authSigner,
      );
    }

    // Disconnect relays that are no longer in the list.
    final toRemove = existing.relays.keys
        .where((url) => !relays.contains(url))
        .toList();
    for (final url in toRemove) {
      await _disconnectRelay(existing.relays.remove(url)!);
    }

    // Connect new relays.
    for (final url in relays) {
      if (!existing.relays.containsKey(url)) {
        final conn = _RelayConnection(url);
        existing.relays[url] = conn;
        _connectRelay(sessionId, conn);
      }
    }
  }

  @override
  Future<void> stopSession(String sessionId) async {
    final state = _sessions.remove(sessionId);
    if (state == null) return;
    for (final conn in state.relays.values) {
      await _disconnectRelay(conn);
    }
  }

  @override
  Future<void> publishEvent(
    String sessionId,
    Map<String, Object?> signedEventJson,
  ) async {
    final state = _sessions[sessionId];
    if (state == null) return;

    final message = jsonEncode(['EVENT', signedEventJson]);
    final eventId = signedEventJson['id'];

    for (final conn in state.relays.values) {
      if (!_isHealthy(conn)) continue;
      if (eventId is String) conn.rememberSent(eventId, message);
      _publishWithRetry(conn, message, sessionId);
    }
  }

  @override
  Future<void> reconnectAll() async {
    for (final entry in _sessions.entries) {
      for (final conn in entry.value.relays.values) {
        if (conn.socket != null || conn.connecting) continue;
        conn.reconnectAttempts = 0;
        _connectRelay(entry.key, conn);
      }
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  bool _isCurrent(String sessionId, _RelayConnection conn) =>
      _sessions[sessionId]?.relays[conn.url] == conn;

  bool _isHealthy(_RelayConnection conn) {
    final until = conn.unhealthyUntil;
    return until == null || !_now().isBefore(until);
  }

  void _connectRelay(String sessionId, _RelayConnection conn) {
    conn.reconnectTimer?.cancel();
    conn.reconnectTimer = null;
    _doConnect(sessionId, conn);
  }

  void _doConnect(String sessionId, _RelayConnection conn) async {
    if (!_isCurrent(sessionId, conn)) return;
    if (conn.connecting || conn.socket != null) return;

    conn.connecting = true;
    final Nip46RelaySocket socket;
    try {
      diogelLog('Nip46RelayService: connecting to ${conn.url}');
      socket = await _connector(conn.url);
    } catch (e) {
      conn.connecting = false;
      diogelLog('Nip46RelayService: failed to connect to ${conn.url}', error: e);
      if (_isCurrent(sessionId, conn)) _scheduleReconnect(sessionId, conn);
      return;
    }
    conn.connecting = false;

    // The session, or this relay, may have gone while connecting.
    if (!_isCurrent(sessionId, conn)) {
      unawaited(socket.close().catchError((_) {}));
      return;
    }

    conn.socket = socket;
    conn.reconnectAttempts = 0;
    conn.consecutiveFailures = 0;
    conn.unhealthyUntil = null;
    conn.authEventId = null;

    conn.messageSub = socket.messages.listen(
      (data) => _onMessage(sessionId, conn, data),
      onDone: () => _onDisconnected(sessionId, conn, socket),
      onError: (_) => _onDisconnected(sessionId, conn, socket),
      cancelOnError: true,
    );

    _subscribe(sessionId, conn);
    _scheduleSubscriptionRefresh(sessionId, conn);
  }

  void _onDisconnected(
    String sessionId,
    _RelayConnection conn,
    Nip46RelaySocket socket,
  ) {
    if (conn.socket != socket) return;
    diogelLog('Nip46RelayService: disconnected from ${conn.url}');
    conn.socket = null;
    conn.messageSub = null;
    conn.subscriptionId = null;
    conn.authEventId = null;
    conn.refreshTimer?.cancel();
    conn.refreshTimer = null;
    if (_isCurrent(sessionId, conn)) {
      _scheduleReconnect(sessionId, conn);
    }
  }

  void _scheduleReconnect(String sessionId, _RelayConnection conn) {
    conn.reconnectTimer?.cancel();
    final delay = reconnectDelay(
      conn.reconnectAttempts,
      base: _reconnectBaseDelay,
    );
    conn.reconnectAttempts++;
    conn.reconnectTimer = Timer(delay, () {
      conn.reconnectTimer = null;
      _doConnect(sessionId, conn);
    });
  }

  void _subscribe(String sessionId, _RelayConnection conn) {
    final state = _sessions[sessionId];
    if (state == null || conn.socket == null) return;

    // Close the previous subscription so a refresh doesn't stack them.
    final previous = conn.subscriptionId;
    if (previous != null) {
      _send(conn, jsonEncode(['CLOSE', previous]));
    }

    // The first subscription reaches back to the session's start, and each
    // later one to just before the one it replaces: nothing sent in between
    // is missed, and older requests are not replayed.
    final lastSubscribedAt = conn.lastSubscribedAt;
    final since = lastSubscribedAt != null
        ? lastSubscribedAt.subtract(sinceSkew)
        : state.since;
    conn.lastSubscribedAt = _now();

    final subId = _randomSubId();
    conn.subscriptionId = subId;
    _send(
      conn,
      jsonEncode([
        'REQ',
        subId,
        {
          'kinds': [24133],
          '#p': [state.remoteSignerPubkey],
          if (since != null) 'since': since.millisecondsSinceEpoch ~/ 1000,
        },
      ]),
    );
  }

  void _send(_RelayConnection conn, String message) {
    try {
      conn.socket?.add(message);
    } catch (e) {
      diogelLog('Nip46RelayService: failed to send to ${conn.url}', error: e);
    }
  }

  void _scheduleSubscriptionRefresh(String sessionId, _RelayConnection conn) {
    conn.refreshTimer?.cancel();
    conn.refreshTimer = Timer.periodic(_subscriptionRefreshInterval, (_) {
      _subscribe(sessionId, conn);
    });
  }

  void _onMessage(String sessionId, _RelayConnection conn, dynamic raw) {
    if (raw is! String) return;
    final List<Object?> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    if (msg.isEmpty || msg[0] is! String) return;
    final type = msg[0] as String;

    if (type == 'EVENT' && msg.length >= 3) {
      final eventJson = msg[2];
      if (eventJson is! Map) return;
      _handleEvent(conn, eventJson.cast<String, Object?>());
    } else if (type == 'OK' && msg.length >= 3) {
      _handleOk(sessionId, conn, msg);
    } else if (type == 'AUTH' && msg.length >= 2 && msg[1] is String) {
      _handleAuthChallenge(sessionId, conn, msg[1] as String);
    } else if (type == 'CLOSED' && msg.length >= 2) {
      if (msg[1] == conn.subscriptionId) {
        // An auth-required close is answered by re-subscribing after AUTH.
        conn.subscriptionId = null;
        diogelLog(
          'Nip46RelayService: ${conn.url} closed the subscription: ${msg.elementAtOrNull(2)}',
        );
      }
    } else if (type == 'NOTICE') {
      diogelLog('Nip46RelayService: NOTICE from ${conn.url}: ${msg.elementAtOrNull(1)}');
    }
  }

  void _handleOk(String sessionId, _RelayConnection conn, List<Object?> msg) {
    final eventId = msg[1];
    final accepted = msg[2] == true;
    final reason = msg.elementAtOrNull(3);

    if (eventId is String && eventId == conn.authEventId) {
      conn.authEventId = null;
      if (accepted) {
        _afterAuthenticated(sessionId, conn);
      } else {
        diogelLog('Nip46RelayService: ${conn.url} refused AUTH: $reason');
      }
      return;
    }

    if (accepted) {
      conn.consecutiveFailures = 0;
      conn.unhealthyUntil = null;
      if (eventId is String) conn.sentEvents.remove(eventId);
      return;
    }

    // An event refused until we authenticate is sent again once we have.
    if (reason is String && reason.startsWith('auth-required:')) {
      if (eventId is String) conn.awaitingAuth.add(eventId);
      return;
    }

    if (eventId is String) conn.sentEvents.remove(eventId);
    conn.consecutiveFailures++;
    _checkUnhealthy(conn);
  }

  void _handleAuthChallenge(
    String sessionId,
    _RelayConnection conn,
    String challenge,
  ) {
    final signer = _sessions[sessionId]?.authSigner;
    if (signer == null) return;
    final Map<String, Object?> authEvent;
    try {
      authEvent = signer(conn.url, challenge);
    } catch (e) {
      diogelLog('Nip46RelayService: could not sign AUTH for ${conn.url}', error: e);
      return;
    }
    final id = authEvent['id'];
    conn.authEventId = id is String ? id : null;
    _send(conn, jsonEncode(['AUTH', authEvent]));
  }

  void _afterAuthenticated(String sessionId, _RelayConnection conn) {
    // The relay may have closed or held back the subscription until AUTH, so
    // subscribe again from the session's start, and resend anything it
    // refused for auth-required.
    conn.lastSubscribedAt = null;
    _subscribe(sessionId, conn);
    for (final eventId in conn.awaitingAuth) {
      final message = conn.sentEvents[eventId];
      if (message != null) _send(conn, message);
    }
    conn.awaitingAuth.clear();
  }

  void _handleEvent(_RelayConnection conn, Map<String, Object?> eventJson) {
    final eventId = eventJson['id'];
    final pubkey = eventJson['pubkey'];
    final content = eventJson['content'];
    final createdAt = eventJson['created_at'];

    if (eventId is! String ||
        pubkey is! String ||
        content is! String ||
        createdAt is! int) {
      return;
    }

    // Extract the #p tag value — the remote-signer pubkey this event is addressed to.
    final recipientPubkey = _extractPTag(eventJson);
    if (recipientPubkey == null) return;

    _eventController.add(
      Nip46InboundRelayEvent(
        eventId: eventId,
        senderPubkey: pubkey,
        recipientPubkey: recipientPubkey,
        encryptedContent: content,
        relay: conn.url,
        createdAt: createdAt,
      ),
    );
  }

  String? _extractPTag(Map<String, Object?> eventJson) {
    final tags = eventJson['tags'];
    if (tags is! List) return null;
    for (final tag in tags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'p') {
        final v = tag[1];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  void _publishWithRetry(
    _RelayConnection conn,
    String message,
    String sessionId,
  ) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      if (!_sessions.containsKey(sessionId)) return;
      if (!_isHealthy(conn)) return;

      final socket = conn.socket;
      if (socket == null) {
        // Wait for reconnect.
        await Future<void>.delayed(_publishBackoff(attempt));
        continue;
      }

      try {
        socket.add(message);
        // The relay's OK is handled in _onMessage.
        return;
      } catch (e) {
        diogelLog(
          'Nip46RelayService: publish attempt ${attempt + 1} failed on ${conn.url}',
          error: e,
        );
        conn.consecutiveFailures++;
        _checkUnhealthy(conn);
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(_publishBackoff(attempt));
        }
      }
    }
    diogelLog(
      'Nip46RelayService: giving up publishing to ${conn.url} after $_maxRetries attempts',
    );
  }

  /// After [_unhealthyThreshold] failures in a row a relay is skipped for
  /// [unhealthyCooldown], then tried again.
  void _checkUnhealthy(_RelayConnection conn) {
    if (conn.consecutiveFailures >= _unhealthyThreshold) {
      diogelLog('Nip46RelayService: marking ${conn.url} as unhealthy');
      conn.unhealthyUntil = _now().add(unhealthyCooldown);
      conn.consecutiveFailures = 0;
    }
  }

  Duration _publishBackoff(int attempt) =>
      _publishBaseDelay * (1 << attempt.clamp(0, 4));

  Future<void> _disconnectRelay(_RelayConnection conn) async {
    conn.refreshTimer?.cancel();
    conn.reconnectTimer?.cancel();
    conn.refreshTimer = null;
    conn.reconnectTimer = null;
    final socket = conn.socket;
    conn.socket = null;
    await conn.messageSub?.cancel();
    conn.messageSub = null;
    try {
      await socket?.close();
    } catch (_) {}
  }

  String _randomSubId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  @override
  void dispose() {
    for (final state in _sessions.values) {
      for (final conn in state.relays.values) {
        conn.refreshTimer?.cancel();
        conn.reconnectTimer?.cancel();
        conn.messageSub?.cancel();
        try {
          conn.socket?.close();
        } catch (_) {}
      }
    }
    _sessions.clear();
    _eventController.close();
  }
}

class _IoRelaySocket implements Nip46RelaySocket {
  final WebSocket _socket;

  _IoRelaySocket(this._socket);

  @override
  Stream<dynamic> get messages => _socket;

  @override
  void add(String data) => _socket.add(data);

  @override
  Future<void> close() => _socket.close();
}

class _SessionState {
  final String remoteSignerPubkey;
  final DateTime? since;
  final Nip46RelayAuthSigner? authSigner;
  final Map<String, _RelayConnection> relays;

  _SessionState({
    required this.remoteSignerPubkey,
    required this.since,
    required this.authSigner,
    required this.relays,
  });
}

class _RelayConnection {
  static const int _maxSentEvents = 32;

  final String url;
  Nip46RelaySocket? socket;
  StreamSubscription<dynamic>? messageSub;
  bool connecting = false;
  String? subscriptionId;
  DateTime? lastSubscribedAt;
  int consecutiveFailures = 0;
  int reconnectAttempts = 0;
  DateTime? unhealthyUntil;
  String? authEventId;
  // Recently published events by id, so one refused for auth-required can be
  // sent again after AUTH.
  final Map<String, String> sentEvents = {};
  final Set<String> awaitingAuth = {};
  Timer? refreshTimer;
  Timer? reconnectTimer;

  _RelayConnection(this.url);

  void rememberSent(String eventId, String message) {
    sentEvents[eventId] = message;
    if (sentEvents.length > _maxSentEvents) {
      sentEvents.remove(sentEvents.keys.first);
    }
  }
}
