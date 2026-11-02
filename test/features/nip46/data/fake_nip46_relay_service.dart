import 'dart:async';

import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/domain/nip46_relay_event.dart';

class FakeNip46RelayService implements Nip46RelayService {
  final _eventController =
      StreamController<Nip46InboundRelayEvent>.broadcast();

  final List<Map<String, Object?>> capturedPublishes = [];
  final Set<String> connectedSessions = {};
  final Map<String, DateTime?> sinceBySession = {};
  final Map<String, Nip46RelayAuthSigner?> authSignerBySession = {};
  final Map<String, List<String>> relaysBySession = {};
  int reconnectAllCalls = 0;

  void simulateInbound(Nip46InboundRelayEvent event) {
    _eventController.add(event);
  }

  @override
  Future<void> startSession(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey, {
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  }) async {
    connectedSessions.add(sessionId);
    sinceBySession[sessionId] = since;
    authSignerBySession[sessionId] = authSigner;
    relaysBySession[sessionId] = relays;
  }

  @override
  Future<void> updateSessionRelays(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey, {
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  }) async {
    relaysBySession[sessionId] = relays;
  }

  /// Makes stopping a session fail, as a relay error would.
  bool failStopSession = false;

  @override
  Future<void> stopSession(String sessionId) async {
    if (failStopSession) throw StateError('relay did not stop');
    connectedSessions.remove(sessionId);
  }

  /// While set, each publish is recorded and then waits for it, as a slow
  /// relay would.
  Completer<void>? holdPublishes;

  /// Completes when a publish first waits on [holdPublishes].
  final publishHeld = Completer<void>();

  @override
  Future<void> publishEvent(
    String sessionId,
    Map<String, Object?> signedEventJson,
  ) async {
    capturedPublishes.add({'sessionId': sessionId, ...signedEventJson});
    final hold = holdPublishes;
    if (hold != null) {
      if (!publishHeld.isCompleted) publishHeld.complete();
      await hold.future;
    }
  }

  @override
  Future<void> reconnectAll() async {
    reconnectAllCalls++;
  }

  @override
  Stream<Nip46InboundRelayEvent> get inboundEvents => _eventController.stream;

  @override
  void dispose() {
    _eventController.close();
  }
}
