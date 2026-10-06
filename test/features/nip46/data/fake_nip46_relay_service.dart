import 'dart:async';

import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/domain/nip46_relay_event.dart';

class FakeNip46RelayService implements Nip46RelayService {
  final _eventController =
      StreamController<Nip46InboundRelayEvent>.broadcast();

  final List<Map<String, Object?>> capturedPublishes = [];
  final Set<String> connectedSessions = {};

  void simulateInbound(Nip46InboundRelayEvent event) {
    _eventController.add(event);
  }

  @override
  Future<void> startSession(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey,
  ) async {
    connectedSessions.add(sessionId);
  }

  @override
  Future<void> updateSessionRelays(
    String sessionId,
    List<String> relays,
    String remoteSignerPubkey,
  ) async {}

  @override
  Future<void> stopSession(String sessionId) async {
    connectedSessions.remove(sessionId);
  }

  @override
  Future<void> publishEvent(
    String sessionId,
    Map<String, Object?> signedEventJson,
  ) async {
    capturedPublishes.add({'sessionId': sessionId, ...signedEventJson});
  }

  @override
  Stream<Nip46InboundRelayEvent> get inboundEvents => _eventController.stream;

  @override
  void dispose() {
    _eventController.close();
  }
}
