import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';

class FakeRelaySocket implements Nip46RelaySocket {
  final String url;
  final _incoming = StreamController<dynamic>();
  final List<List<Object?>> sent = [];
  bool closed = false;

  FakeRelaySocket(this.url);

  /// Sends [message] to the service as the relay.
  Future<void> relay(List<Object?> message) async {
    _incoming.add(jsonEncode(message));
    await pump();
  }

  /// Drops the connection from the relay's side.
  Future<void> drop() async {
    await _incoming.close();
    await pump();
  }

  List<List<Object?>> sentOfType(String type) =>
      sent.where((m) => m.first == type).toList();

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void add(String data) => sent.add((jsonDecode(data) as List).cast());

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  const sessionId = 'session-1';
  const signerPubkey =
      'b0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1';
  const relayUrl = 'wss://relay.example.com';

  late DateTime now;
  late List<FakeRelaySocket> sockets;
  late int failConnects;
  late DartNip46RelayService service;

  DartNip46RelayService build({
    Duration reconnectBaseDelay = Duration.zero,
  }) {
    return DartNip46RelayService(
      connector: (url) async {
        if (failConnects > 0) {
          failConnects--;
          throw Exception('offline');
        }
        final socket = FakeRelaySocket(url);
        sockets.add(socket);
        return socket;
      },
      now: () => now,
      reconnectBaseDelay: reconnectBaseDelay,
      publishBaseDelay: Duration.zero,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 24, 12);
    sockets = [];
    failConnects = 0;
    service = build();
  });

  tearDown(() => service.dispose());

  Map<String, Object?> authEvent(String relay, String challenge) => {
    'id': 'auth-$challenge',
    'kind': 22242,
    'tags': [
      ['relay', relay],
      ['challenge', challenge],
    ],
  };

  Future<FakeRelaySocket> start({
    DateTime? since,
    Nip46RelayAuthSigner? authSigner,
  }) async {
    await service.startSession(
      sessionId,
      [relayUrl],
      signerPubkey,
      since: since,
      authSigner: authSigner,
    );
    await pump();
    return sockets.last;
  }

  group('subscription', () {
    test('asks for kind 24133 to the signer since the session start', () async {
      final since = DateTime.utc(2026, 10, 24, 11, 55);
      final socket = await start(since: since);

      final req = socket.sentOfType('REQ').single;
      expect(req[2], {
        'kinds': [24133],
        '#p': [signerPubkey],
        'since': since.millisecondsSinceEpoch ~/ 1000,
      });
    });

    test('a reconnect subscribes from just before the last subscription',
        () async {
      final first = await start(since: DateTime.utc(2026, 10, 24, 11));
      final subscribedAt = now;

      now = now.add(const Duration(hours: 1));
      await first.drop();
      await pump();

      final req = sockets.last.sentOfType('REQ').single;
      expect(sockets, hasLength(2));
      expect(
        (req[2] as Map)['since'],
        subscribedAt.subtract(DartNip46RelayService.sinceSkew)
                .millisecondsSinceEpoch ~/
            1000,
      );
    });

    test('inbound requests reach the stream', () async {
      final socket = await start();
      final received = service.inboundEvents.first;

      await socket.relay([
        'EVENT',
        'sub',
        {
          'id': 'e1',
          'pubkey': 'client',
          'content': 'ciphertext',
          'created_at': 1,
          'tags': [
            ['p', signerPubkey],
          ],
        },
      ]);

      final event = await received;
      expect(event.eventId, 'e1');
      expect(event.senderPubkey, 'client');
      expect(event.recipientPubkey, signerPubkey);
    });
  });

  group('NIP-42 AUTH', () {
    test('answers a challenge, then closes and renews the subscription',
        () async {
      final socket = await start(authSigner: authEvent);
      final firstSub = socket.sentOfType('REQ').single[1];

      await socket.relay(['AUTH', 'challenge-1']);
      expect(socket.sentOfType('AUTH').single, [
        'AUTH',
        authEvent(relayUrl, 'challenge-1'),
      ]);

      await socket.relay(['OK', 'auth-challenge-1', true, '']);
      expect(socket.sentOfType('CLOSE').single, ['CLOSE', firstSub]);
      expect(socket.sentOfType('REQ'), hasLength(2));
    });

    test('resends an event refused as auth-required once authenticated',
        () async {
      final socket = await start(authSigner: authEvent);
      await service.publishEvent(sessionId, {'id': 'response-1'});
      await pump();
      expect(socket.sentOfType('EVENT'), hasLength(1));

      await socket.relay(['OK', 'response-1', false, 'auth-required: sign in']);
      await socket.relay(['AUTH', 'challenge-1']);
      await socket.relay(['OK', 'auth-challenge-1', true, '']);

      expect(socket.sentOfType('EVENT'), hasLength(2));
      expect(socket.sentOfType('EVENT').last[1], {'id': 'response-1'});
    });

    test('ignores a challenge without a signer', () async {
      final socket = await start();

      await socket.relay(['AUTH', 'challenge-1']);

      expect(socket.sentOfType('AUTH'), isEmpty);
    });
  });

  group('relay health', () {
    Future<void> refuse(FakeRelaySocket socket, int times) async {
      for (var i = 0; i < times; i++) {
        await socket.relay(['OK', 'e$i', false, 'blocked: no']);
      }
    }

    test('an unhealthy relay is skipped, then tried again after the cooldown',
        () async {
      final socket = await start();
      await refuse(socket, 10);

      await service.publishEvent(sessionId, {'id': 'skipped'});
      await pump();
      expect(socket.sentOfType('EVENT'), isEmpty);

      now = now.add(DartNip46RelayService.unhealthyCooldown);
      await service.publishEvent(sessionId, {'id': 'retried'});
      await pump();
      expect(socket.sentOfType('EVENT').single[1], {'id': 'retried'});
    });

    test('an accepted event clears earlier failures', () async {
      final socket = await start();
      await refuse(socket, 9);
      await socket.relay(['OK', 'good', true, '']);
      await refuse(socket, 9);

      await service.publishEvent(sessionId, {'id': 'still-healthy'});
      await pump();
      expect(socket.sentOfType('EVENT'), hasLength(1));
    });
  });

  group('reconnecting', () {
    test('the back-off doubles from two seconds up to a minute', () {
      expect(
        [for (var i = 0; i < 7; i++) DartNip46RelayService.reconnectDelay(i)],
        const [
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 16),
          Duration(seconds: 32),
          Duration(seconds: 60),
          Duration(seconds: 60),
        ],
      );
    });

    test('reconnectAll connects a relay waiting on its back-off', () async {
      service.dispose();
      service = build(reconnectBaseDelay: const Duration(hours: 1));
      failConnects = 1;

      await service.startSession(sessionId, [relayUrl], signerPubkey);
      await pump();
      expect(sockets, isEmpty);

      await service.reconnectAll();
      await pump();

      expect(sockets, hasLength(1));
      expect(sockets.single.sentOfType('REQ'), hasLength(1));
    });

    test('a relay that drops the connection at once keeps backing off',
        () async {
      await (await start()).drop();
      await pump();
      await sockets.last.drop();
      await pump();

      expect(service.reconnectAttemptsFor(sessionId, relayUrl), 2);
    });

    test('a connection that stayed up resets the back-off', () async {
      await (await start()).drop();
      await pump();

      now = now.add(DartNip46RelayService.stableConnection);
      await sockets.last.drop();
      await pump();

      expect(service.reconnectAttemptsFor(sessionId, relayUrl), 1);
    });

    test('reconnectAll leaves a connected relay alone', () async {
      await start();

      await service.reconnectAll();
      await pump();

      expect(sockets, hasLength(1));
    });

    test('stopping a session closes its sockets and stops reconnecting',
        () async {
      final socket = await start();

      await service.stopSession(sessionId);
      await pump();

      expect(socket.closed, isTrue);
      expect(sockets, hasLength(1));
    });
  });
}
