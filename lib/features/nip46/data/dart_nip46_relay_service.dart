import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/nip46_relay_event.dart';

abstract interface class Nip46RelayService {
  /// Starts relay subscriptions for [sessionId] on [relays], listening for
  /// kind 24133 events addressed to [remoteSignerPubkey].
  Future<void> startSession(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey,
  );

  /// Updates the relay list for an existing session.
  Future<void> updateSessionRelays(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey,
  );

  /// Stops all relay connections for [sessionId].
  Future<void> stopSession(String sessionId);

  /// Publishes a pre-signed kind 24133 event JSON to all healthy relays for [sessionId].
  /// Retries up to 5 times with exponential back-off.
  Future<void> publishEvent(String sessionId, Map<String, Object?> signedEventJson);

  /// Inbound kind 24133 events addressed to a tracked signer pubkey.
  Stream<Nip46InboundRelayEvent> get inboundEvents;

  void dispose();
}

class DartNip46RelayService implements Nip46RelayService {
  static const int _maxRetries = 5;
  static const int _unhealthyThreshold = 10;
  static const Duration _subscriptionRefreshInterval = Duration(seconds: 30);
  static const Duration _reconnectDelay = Duration(seconds: 2);

  final _eventController =
      StreamController<Nip46InboundRelayEvent>.broadcast();

  // sessionId -> _SessionState
  final Map<String, _SessionState> _sessions = {};

  @override
  Stream<Nip46InboundRelayEvent> get inboundEvents => _eventController.stream;

  @override
  Future<void> startSession(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey,
  ) async {
    await stopSession(sessionId);
    final state = _SessionState(
      remoteSignerPubkey: remoteSignerPubkey,
      relays: Map.fromEntries(
        relays.map((url) => MapEntry(url, _RelayConnection(url))),
      ),
    );
    _sessions[sessionId] = state;
    for (final conn in state.relays.values) {
      _connectRelay(sessionId, conn, remoteSignerPubkey);
    }
  }

  @override
  Future<void> updateSessionRelays(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey,
  ) async {
    final existing = _sessions[sessionId];
    if (existing == null) {
      return startSession(sessionId, relays, remoteSignerPubkey);
    }

    // Disconnect relays that are no longer in the list.
    final toRemove = existing.relays.keys
        .where((url) => !relays.contains(url))
        .toList();
    for (final url in toRemove) {
      await _disconnectRelay(existing.relays[url]!);
      existing.relays.remove(url);
    }

    // Connect new relays.
    for (final url in relays) {
      if (!existing.relays.containsKey(url)) {
        final conn = _RelayConnection(url);
        existing.relays[url] = conn;
        _connectRelay(sessionId, conn, remoteSignerPubkey);
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

    for (final conn in state.relays.values) {
      if (conn.consecutiveFailures >= _unhealthyThreshold) continue;
      _publishWithRetry(conn, message, sessionId, signedEventJson);
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  void _connectRelay(
    String sessionId,
    _RelayConnection conn,
    String remoteSignerPubkey,
  ) {
    conn.reconnectTimer?.cancel();
    conn.reconnectTimer = null;
    _doConnect(sessionId, conn, remoteSignerPubkey);
  }

  void _doConnect(
    String sessionId,
    _RelayConnection conn,
    String remoteSignerPubkey,
  ) async {
    // Check session still alive.
    if (!_sessions.containsKey(sessionId)) return;

    try {
      debugPrint('Nip46RelayService: connecting to ${conn.url}');
      final socket = await WebSocket.connect(conn.url);
      conn.socket = socket;
      conn.consecutiveFailures = 0;

      _subscribe(conn, remoteSignerPubkey);
      _scheduleSubscriptionRefresh(sessionId, conn, remoteSignerPubkey);

      socket.listen(
        (data) => _onMessage(conn, data),
        onDone: () => _onDisconnected(sessionId, conn, remoteSignerPubkey),
        onError: (_) => _onDisconnected(sessionId, conn, remoteSignerPubkey),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Nip46RelayService: failed to connect to ${conn.url}: $e');
      _scheduleReconnect(sessionId, conn, remoteSignerPubkey);
    }
  }

  void _onDisconnected(
    String sessionId,
    _RelayConnection conn,
    String remoteSignerPubkey,
  ) {
    debugPrint('Nip46RelayService: disconnected from ${conn.url}');
    conn.socket = null;
    conn.subscriptionId = null;
    conn.refreshTimer?.cancel();
    conn.refreshTimer = null;
    if (_sessions.containsKey(sessionId)) {
      _scheduleReconnect(sessionId, conn, remoteSignerPubkey);
    }
  }

  void _scheduleReconnect(
    String sessionId,
    _RelayConnection conn,
    String remoteSignerPubkey,
  ) {
    conn.reconnectTimer?.cancel();
    conn.reconnectTimer = Timer(_reconnectDelay, () {
      if (_sessions.containsKey(sessionId)) {
        _doConnect(sessionId, conn, remoteSignerPubkey);
      }
    });
  }

  void _subscribe(_RelayConnection conn, String remoteSignerPubkey) {
    final socket = conn.socket;
    if (socket == null) return;
    final subId = _randomSubId();
    conn.subscriptionId = subId;
    // No 'since' filter — clock skew tolerance per Nostria behavior.
    final req = jsonEncode([
      'REQ',
      subId,
      {
        'kinds': [24133],
        '#p': [remoteSignerPubkey],
      },
    ]);
    try {
      socket.add(req);
    } catch (e) {
      debugPrint('Nip46RelayService: failed to send REQ to ${conn.url}: $e');
    }
  }

  void _scheduleSubscriptionRefresh(
    String sessionId,
    _RelayConnection conn,
    String remoteSignerPubkey,
  ) {
    conn.refreshTimer?.cancel();
    conn.refreshTimer = Timer.periodic(_subscriptionRefreshInterval, (_) {
      if (!_sessions.containsKey(sessionId) || conn.socket == null) return;
      _subscribe(conn, remoteSignerPubkey);
    });
  }

  void _onMessage(_RelayConnection conn, dynamic raw) {
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
      final ok = msg[2];
      if (ok == true) {
        conn.consecutiveFailures = 0;
      } else {
        conn.consecutiveFailures++;
        _checkUnhealthy(conn);
      }
    } else if (type == 'NOTICE') {
      debugPrint('Nip46RelayService: NOTICE from ${conn.url}: ${msg.elementAtOrNull(1)}');
    }
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
    Map<String, Object?> eventJson,
  ) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      if (!_sessions.containsKey(sessionId)) return;
      if (conn.consecutiveFailures >= _unhealthyThreshold) return;

      final socket = conn.socket;
      if (socket == null) {
        // Wait for reconnect.
        await Future<void>.delayed(
          Duration(milliseconds: _backoffMs(attempt)),
        );
        continue;
      }

      try {
        socket.add(message);
        // OK confirmation is handled in _onMessage; optimistically decrement.
        return;
      } catch (e) {
        debugPrint(
          'Nip46RelayService: publish attempt ${attempt + 1} failed on ${conn.url}: $e',
        );
        conn.consecutiveFailures++;
        _checkUnhealthy(conn);
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: _backoffMs(attempt)),
          );
        }
      }
    }
    debugPrint(
      'Nip46RelayService: giving up publishing to ${conn.url} after $_maxRetries attempts',
    );
  }

  void _checkUnhealthy(_RelayConnection conn) {
    if (conn.consecutiveFailures >= _unhealthyThreshold) {
      debugPrint('Nip46RelayService: marking ${conn.url} as unhealthy');
    }
  }

  int _backoffMs(int attempt) => 1000 * (1 << attempt.clamp(0, 4));

  Future<void> _disconnectRelay(_RelayConnection conn) async {
    conn.refreshTimer?.cancel();
    conn.reconnectTimer?.cancel();
    conn.refreshTimer = null;
    conn.reconnectTimer = null;
    try {
      await conn.socket?.close();
    } catch (_) {}
    conn.socket = null;
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
        try {
          conn.socket?.close();
        } catch (_) {}
      }
    }
    _sessions.clear();
    _eventController.close();
  }
}

class _SessionState {
  final String remoteSignerPubkey;
  final Map<String, _RelayConnection> relays;

  _SessionState({required this.remoteSignerPubkey, required this.relays});
}

class _RelayConnection {
  final String url;
  WebSocket? socket;
  String? subscriptionId;
  int consecutiveFailures = 0;
  Timer? refreshTimer;
  Timer? reconnectTimer;

  _RelayConnection(this.url);
}
