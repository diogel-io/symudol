import 'dart:convert';

import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/domain/nip46_connection_token.dart';
import 'package:symudol/features/nip46/domain/nip46_relay_event.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip55/domain/nip55_approval_timeframe.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';
import '../../../fakes/fake_nip46_session_store.dart';

void main() {
  late FakeVaultStore vaultStore;
  late VaultController vaultController;
  late FakeNip46RelayService relayService;
  late FakeNip46SessionStore sessionStore;
  late Nip46Controller controller;
  late VaultServiceImpl vaultService;

  setUp(() async {
    vaultStore = FakeVaultStore();
    vaultService = VaultServiceImpl(vaultStore);
    await vaultService.init();
    vaultController = VaultController(vaultService);
    relayService = FakeNip46RelayService();
    sessionStore = FakeNip46SessionStore();
    final crypto = DartNip46Crypto(const DartNostrCryptoService());
    controller = Nip46Controller(
      sessionStore: sessionStore,
      vaultService: vaultService,
      vaultController: vaultController,
      relayService: relayService,
      crypto: crypto,
    );
    // Allow the async _initialize() to complete.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    controller.dispose();
    relayService.dispose();
    vaultController.dispose();
  });

  /// Replaces the controller with one whose review timeout is [timeout], on a
  /// fresh relay, so a timeout test needn't wait the real 60 s.
  Future<void> useRequestTimeout(Duration timeout) async {
    controller.dispose();
    relayService = FakeNip46RelayService();
    controller = Nip46Controller(
      sessionStore: sessionStore,
      vaultService: vaultService,
      vaultController: vaultController,
      relayService: relayService,
      crypto: DartNip46Crypto(const DartNostrCryptoService()),
      requestTimeout: timeout,
    );
    await Future<void>.delayed(Duration.zero);
  }

  group('initiateBunkerSession', () {
    test('returns a valid bunker token', () async {
      final token = await controller.initiateBunkerSession();
      expect(token, isA<Nip46BunkerToken>());
      expect(token.remoteSignerPubkey, hasLength(64));
      expect(token.relays, isNotEmpty);
      expect(token.secret, hasLength(64));
    });

    test('creates a pending session in state', () async {
      await controller.initiateBunkerSession();
      expect(controller.state.sessions, hasLength(1));
      expect(controller.state.sessions.first.status, Nip46SessionStatus.pending);
    });

    test('persists session to store', () async {
      await controller.initiateBunkerSession();
      final stored = await sessionStore.listSessions();
      expect(stored, hasLength(1));
    });

    test('starts relay subscription', () async {
      await controller.initiateBunkerSession();
      expect(relayService.connectedSessions, hasLength(1));
    });

    test('custom relays are used', () async {
      final token = await controller.initiateBunkerSession(
        ['wss://custom.relay.example'],
      );
      expect(token.relays, ['wss://custom.relay.example']);
      expect(controller.state.sessions.first.relays, [
        'wss://custom.relay.example',
      ]);
    });
  });

  group('importNostrconnectToken', () {
    const validClientPubkey =
        'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1';

    String buildNostrconnect({
      String? pubkey,
      String secret = 'testsecret123',
      String? name,
      String? perms,
    }) {
      final p = pubkey ?? validClientPubkey;
      var uri = 'nostrconnect://$p?secret=$secret';
      uri += '&relay=${Uri.encodeComponent("wss://relay.example.com")}';
      if (name != null) uri += '&name=${Uri.encodeComponent(name)}';
      if (perms != null) uri += '&perms=${Uri.encodeComponent(perms)}';
      return uri;
    }

    test('sets pendingApproval in state', () async {
      await controller.importNostrconnectToken(buildNostrconnect());
      expect(controller.state.pendingApproval, isNotNull);
    });

    test('creates a pending session with correct client pubkey', () async {
      await controller.importNostrconnectToken(buildNostrconnect());
      expect(controller.state.sessions, hasLength(1));
      expect(
        controller.state.sessions.first.clientPubkey,
        validClientPubkey,
      );
    });

    test('parses client metadata from perms and name', () async {
      await controller.importNostrconnectToken(
        buildNostrconnect(name: 'Test Client'),
      );
      expect(controller.state.sessions.first.clientName, 'Test Client');
    });

    test('starts relay for the session', () async {
      await controller.importNostrconnectToken(buildNostrconnect());
      expect(relayService.connectedSessions, hasLength(1));
    });

    test('throws on malformed URI', () async {
      await expectLater(
        controller.importNostrconnectToken('not-a-uri'),
        throwsException,
      );
    });
  });

  group('approveConnection', () {
    test('activates pending session and clears pendingApproval', () async {
      await controller.importNostrconnectToken(
        'nostrconnect://a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1?secret=abc&relay=${Uri.encodeComponent("wss://r.example.com")}',
      );
      expect(controller.state.pendingApproval, isNotNull);

      await controller.approveConnection();

      expect(controller.state.pendingApproval, isNull);
      expect(
        controller.state.sessions.first.status,
        Nip46SessionStatus.active,
      );
    });

    test('persists approved session', () async {
      await controller.importNostrconnectToken(
        'nostrconnect://a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1?secret=abc&relay=${Uri.encodeComponent("wss://r.example.com")}',
      );
      await controller.approveConnection();

      final stored = await sessionStore.listSessions();
      expect(stored.first.status, Nip46SessionStatus.active);
    });

    test('no-ops when nothing is pending', () async {
      // Should not throw.
      await controller.approveConnection();
      expect(controller.state.sessions, isEmpty);
    });
  });

  group('rejectConnection', () {
    test('removes session and clears pendingApproval', () async {
      await controller.importNostrconnectToken(
        'nostrconnect://a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1?secret=abc&relay=${Uri.encodeComponent("wss://r.example.com")}',
      );
      expect(controller.state.sessions, hasLength(1));

      await controller.rejectConnection();

      expect(controller.state.sessions, isEmpty);
      expect(controller.state.pendingApproval, isNull);
    });

    test('stops relay for the rejected session', () async {
      await controller.importNostrconnectToken(
        'nostrconnect://a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1?secret=abc&relay=${Uri.encodeComponent("wss://r.example.com")}',
      );
      final sessionId = controller.state.sessions.first.id;

      await controller.rejectConnection();

      expect(relayService.connectedSessions, isNot(contains(sessionId)));
    });
  });

  group('revokeSession', () {
    test('removes session from state and store', () async {
      await controller.initiateBunkerSession();
      final sessionId = controller.state.sessions.first.id;

      await controller.revokeSession(sessionId);

      expect(controller.state.sessions, isEmpty);
      expect(await sessionStore.listSessions(), isEmpty);
    });

    test('stops relay for revoked session', () async {
      await controller.initiateBunkerSession();
      final sessionId = controller.state.sessions.first.id;

      await controller.revokeSession(sessionId);

      expect(relayService.connectedSessions, isNot(contains(sessionId)));
    });
  });

  group('deduplication', () {
    test('duplicate inbound event IDs are ignored', () async {
      // Simulate two inbound events with the same ID.
      // Even if we can't decrypt them (vault locked), the dedup cache
      // ensures only one is processed.
      final fakeEvent = Nip46InboundRelayEvent(
        eventId: 'dup-event-1',
        senderPubkey: 'sender',
        recipientPubkey: 'recipient',
        encryptedContent: 'junk',
        relay: 'wss://relay.example.com',
        createdAt: 0,
      );

      relayService.simulateInbound(fakeEvent);
      relayService.simulateInbound(fakeEvent);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // No relay publishes from the controller (junk content fails decryption),
      // and importantly no exception thrown for the duplicate.
      expect(relayService.capturedPublishes, isEmpty);
    });
  });

  group('vault wipe', () {
    test('stops every relay session and forgets them', () async {
      await vaultController.createVault('1234');
      await controller.initiateBunkerSession();
      expect(controller.state.sessions, hasLength(1));
      expect(relayService.connectedSessions, hasLength(1));

      await vaultController.wipe();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.sessions, isEmpty);
      expect(controller.state.pendingApproval, isNull);
      expect(relayService.connectedSessions, isEmpty);
    });

    test('locking keeps sessions running', () async {
      await vaultController.createVault('1234');
      await controller.initiateBunkerSession();

      await vaultController.lock();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.sessions, hasLength(1));
      expect(relayService.connectedSessions, hasLength(1));
    });
  });

  group('protocol (#30)', () {
    const nostrCrypto = DartNostrCryptoService();
    // Throwaway client keys, generated for these tests only.
    const clientPrivkey =
        '7f3b2c1d0e9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c';
    const strangerPrivkey =
        '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b';
    final clientPubkey = nostrCrypto.derivePublicKey(clientPrivkey);
    final strangerPubkey = nostrCrypto.derivePublicKey(strangerPrivkey);
    var eventCounter = 0;

    /// Sends [method] from the key [fromPrivkey] to [session], as a relay would.
    Future<void> send(
      Nip46Session session,
      String method, {
      String? id,
      List<String> params = const [],
      String fromPrivkey = clientPrivkey,
    }) async {
      final content = nostrCrypto.nip44Encrypt(
        privateKeyHex: fromPrivkey,
        peerPubkeyHex: session.remoteSignerPubkey,
        plaintext: jsonEncode({
          'id': id ?? 'req-${eventCounter + 1}',
          'method': method,
          'params': params,
        }),
      );
      relayService.simulateInbound(
        Nip46InboundRelayEvent(
          eventId: 'event-${++eventCounter}',
          senderPubkey: nostrCrypto.derivePublicKey(fromPrivkey),
          recipientPubkey: session.remoteSignerPubkey,
          encryptedContent: content,
          relay: 'wss://relay.example.com',
          createdAt: 0,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    /// The decrypted responses published so far, oldest first.
    List<Map<String, Object?>> responses() => [
      for (final event in relayService.capturedPublishes)
        (jsonDecode(
                  nostrCrypto.nip44Decrypt(
                    privateKeyHex: clientPrivkey,
                    peerPubkeyHex: event['pubkey'] as String,
                    ciphertext: event['content'] as String,
                  ),
                )
                as Map)
            .cast<String, Object?>(),
    ];

    /// A bunker session that [clientPrivkey] connected to and the user
    /// approved, remembering [perms] (NIP-46 `perms`) for [timeframe].
    Future<Nip46Session> activeBunkerSession({
      String? perms,
      Nip55ApprovalTimeframe timeframe = Nip55ApprovalTimeframe.always,
    }) async {
      final token = await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;
      await send(
        session,
        'connect',
        id: 'connect-1',
        params: [session.remoteSignerPubkey, token.secret, ?perms],
      );
      await controller.approveConnection(timeframe: timeframe);
      relayService.capturedPublishes.clear();
      return controller.state.sessions.single;
    }

    test('a nostrconnect approval replies with the URI secret', () async {
      await controller.importNostrconnectToken(
        'nostrconnect://$clientPubkey?secret=s3cr3t'
        '&relay=${Uri.encodeComponent("wss://relay.example.com")}',
      );

      await controller.approveConnection();

      final reply = responses().single;
      expect(reply['result'], 's3cr3t');
      expect(reply['error'], isNull);
      expect(reply['id'], isNot('connect'));
      expect(reply['id'], hasLength(16));
    });

    test('a bunker approval replies ack to the connect request', () async {
      final token = await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;
      await send(
        session,
        'connect',
        id: 'connect-1',
        params: [session.remoteSignerPubkey, token.secret],
      );
      expect(controller.state.pendingApproval?.clientPubkey, clientPubkey);

      await controller.approveConnection();

      expect(responses().single, {
        'id': 'connect-1',
        'result': 'ack',
        'error': null,
      });
      expect(controller.state.sessions.single.pendingSecret, isNull);
    });

    test('a bunker connect without the secret is ignored', () async {
      await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;

      await send(session, 'connect', params: [session.remoteSignerPubkey]);

      // The session has no client yet, so there is no one to answer.
      expect(controller.state.pendingApproval, isNull);
      expect(controller.state.sessions.single.clientPubkey, isEmpty);
      expect(relayService.capturedPublishes, isEmpty);
    });

    test('another key cannot take over a connect awaiting approval', () async {
      final token = await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;
      await send(
        session,
        'connect',
        params: [session.remoteSignerPubkey, token.secret],
      );

      await send(
        session,
        'connect',
        params: [session.remoteSignerPubkey, token.secret],
        fromPrivkey: strangerPrivkey,
      );

      expect(controller.state.pendingApproval?.clientPubkey, clientPubkey);
      expect(relayService.capturedPublishes, isEmpty);
    });

    test('an approved client connecting again gets ack and keeps its grants',
        () async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity();
      final session = await activeBunkerSession(perms: 'nip44_encrypt');

      await send(
        session,
        'connect',
        id: 'reconnect-1',
        params: [session.remoteSignerPubkey],
      );

      expect(responses().single, {
        'id': 'reconnect-1',
        'result': 'ack',
        'error': null,
      });
      expect(controller.state.pendingApproval, isNull);
      final after = controller.state.sessions.single;
      expect(after.status, Nip46SessionStatus.active);
      expect(after.grants, hasLength(1));
    });

    test('events from a key other than the session client are dropped',
        () async {
      final session = await activeBunkerSession();

      await send(
        session,
        'connect',
        params: [session.remoteSignerPubkey],
        fromPrivkey: strangerPrivkey,
      );

      expect(relayService.capturedPublishes, isEmpty);
      expect(strangerPubkey, isNot(clientPubkey));
    });

    test('switch_relays replies null and keeps the relays', () async {
      await vaultController.createVault('1234');
      await vaultController.createIdentity();
      final session = await activeBunkerSession();

      await send(session, 'switch_relays', id: 'switch-1');

      expect(responses().single, {
        'id': 'switch-1',
        'result': 'null',
        'error': null,
      });
      expect(controller.state.sessions.single.relays, session.relays);
    });

    test('relays start from just before the session was last used', () async {
      await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;

      expect(
        relayService.sinceBySession[session.id],
        session.createdAt.subtract(DartNip46RelayService.sinceSkew),
      );
    });

    test('relay AUTH is signed with the session key', () async {
      await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;
      final signer = relayService.authSignerBySession[session.id]!;

      final auth = signer('wss://relay.example.com', 'challenge-1');

      expect(auth['kind'], 22242);
      expect(auth['pubkey'], session.remoteSignerPubkey);
      expect(auth['content'], '');
      expect(auth['tags'], [
        ['relay', 'wss://relay.example.com'],
        ['challenge', 'challenge-1'],
      ]);
    });

    // Requests that need review wait in a queue, and each gets one answer
    // (diogel-io/symudol#27). Uses the client helpers above.
    group('requests under review (#27)', () {
      Future<Nip46Session> unlockedSession() async {
        await vaultController.createVault('1234');
        await vaultController.createIdentity();
        return activeBunkerSession();
      }

      Future<void> sendNote(Nip46Session session, String id) => send(
        session,
        'sign_event',
        id: id,
        params: [
          jsonEncode({
            'kind': 1,
            'content': 'hello',
            'tags': <Object>[],
            'created_at': 1700000000,
          }),
        ],
      );

      Future<void> sendEncrypt(Nip46Session session, String id) => send(
        session,
        'nip44_encrypt',
        id: id,
        // A real key: encrypting to an invalid one fails.
        params: [strangerPubkey, 'secret text'],
      );

      String keyOf(String requestId) => controller.state.pendingMethodRequests
          .singleWhere((p) => p.request.id == requestId)
          .key;

      test('a sign_event waits for review and approve signs it', () async {
        final session = await unlockedSession();

        await sendNote(session, 'sign-1');

        expect(relayService.capturedPublishes, isEmpty);
        final pending = controller.state.pendingMethodRequests.single;
        expect(pending.request.id, 'sign-1');
        expect(
          pending.identityPubkey,
          vaultController.state.activeIdentity!.publicKey,
        );

        await controller.approveMethodRequest(pending.key);

        expect(controller.state.pendingMethodRequests, isEmpty);
        final response = responses().single;
        expect(response['id'], 'sign-1');
        expect(response['error'], isNull);
        final signed = (jsonDecode(response['result'] as String) as Map)
            .cast<String, Object?>();
        expect(signed['kind'], 1);
        expect(signed['content'], 'hello');
        expect(signed['pubkey'], pending.identityPubkey);
        expect(signed['sig'], isA<String>());
      });

      test('reject answers with an error', () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');

        await controller.rejectMethodRequest(keyOf('sign-1'));

        expect(controller.state.pendingMethodRequests, isEmpty);
        expect(responses().single, {
          'id': 'sign-1',
          'result': null,
          'error': 'User rejected the request',
        });
      });

      test('two concurrent requests both get answers', () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');
        await sendEncrypt(session, 'encrypt-1');

        expect(
          controller.state.pendingMethodRequests.map((p) => p.request.id),
          ['sign-1', 'encrypt-1'],
        );

        // The second first: answering by key leaves the other queued.
        await controller.approveMethodRequest(keyOf('encrypt-1'));
        expect(
          controller.state.pendingMethodRequests.single.request.id,
          'sign-1',
        );
        await controller.rejectMethodRequest(keyOf('sign-1'));

        final answers = {for (final r in responses()) r['id']: r};
        expect(answers.keys, unorderedEquals(['encrypt-1', 'sign-1']));
        expect(answers['encrypt-1']!['error'], isNull);
        expect(answers['encrypt-1']!['result'], isA<String>());
        expect(answers['sign-1']!['error'], 'User rejected the request');
      });

      test('each request times out on its own, from when it arrived', () async {
        await useRequestTimeout(const Duration(milliseconds: 400));
        final session = await unlockedSession();

        await sendNote(session, 'sign-1');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await sendEncrypt(session, 'encrypt-1');
        await Future<void>.delayed(const Duration(milliseconds: 250));

        // The first is past 400 ms, the second isn't.
        expect(
          controller.state.pendingMethodRequests.single.request.id,
          'encrypt-1',
        );
        expect(responses().single, {
          'id': 'sign-1',
          'result': null,
          'error': 'Request timed out',
        });

        await Future<void>.delayed(const Duration(milliseconds: 250));

        expect(controller.state.pendingMethodRequests, isEmpty);
        expect(responses().last, {
          'id': 'encrypt-1',
          'result': null,
          'error': 'Request timed out',
        });
      });

      test('approving a request that already timed out does nothing', () async {
        await useRequestTimeout(const Duration(milliseconds: 100));
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');
        final key = keyOf('sign-1');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(responses(), hasLength(1));

        await controller.approveMethodRequest(key);

        expect(responses().single['error'], 'Request timed out');
      });

      test('approving under another identity is refused', () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');
        final pending = controller.state.pendingMethodRequests.single;

        await vaultController.createIdentity();
        final other = vaultController.state.identities.firstWhere(
          (i) => i.localId != pending.identityLocalId,
        );
        await vaultController.setActiveIdentity(other.localId);

        await controller.approveMethodRequest(pending.key);

        expect(responses().single, {
          'id': 'sign-1',
          'result': null,
          'error': 'Active identity changed',
        });
      });

      test('a request beyond the per-session limit is refused at once',
          () async {
        final session = await unlockedSession();
        const limit = Nip46Controller.maxPendingRequestsPerSession;
        for (var i = 0; i < limit; i++) {
          await sendEncrypt(session, 'encrypt-$i');
        }
        expect(relayService.capturedPublishes, isEmpty);

        await sendEncrypt(session, 'one-too-many');

        expect(controller.state.pendingMethodRequests, hasLength(limit));
        expect(responses().single, {
          'id': 'one-too-many',
          'result': null,
          'error': 'Too many pending requests',
        });
      });

      test('a sign_event that can only fail is refused, not queued', () async {
        final session = await unlockedSession();

        await send(session, 'sign_event', id: 'no-json', params: ['not json']);
        await send(
          session,
          'sign_event',
          id: 'other-key',
          params: [
            jsonEncode({'pubkey': strangerPubkey, 'kind': 1, 'content': 'x'}),
          ],
        );

        await send(
          session,
          'sign_event',
          id: 'far-future',
          params: [
            jsonEncode({'kind': 1, 'created_at': 9000000000000000}),
          ],
        );

        // Beyond an int, so jsonDecode reads it as a double.
        await send(
          session,
          'sign_event',
          id: 'as-double',
          params: ['{"kind": 1, "created_at": 9223372036854775808}'],
        );

        expect(controller.state.pendingMethodRequests, isEmpty);
        expect({for (final r in responses()) r['id']: r['error']}, {
          'far-future': 'sign_event: invalid created_at',
          'as-double': 'sign_event: invalid created_at',
          'no-json': 'sign_event: invalid event JSON',
          'other-key':
              'sign_event: event pubkey does not match active identity',
        });
      });

      test('the same request sent again is queued once', () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');
        await sendNote(session, 'sign-1');

        expect(controller.state.pendingMethodRequests, hasLength(1));
        expect(relayService.capturedPublishes, isEmpty);
      });

      test('a wipe answers every queued request', () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');
        await sendEncrypt(session, 'encrypt-1');

        await vaultController.wipe();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(controller.state.pendingMethodRequests, isEmpty);
        expect(relayService.connectedSessions, isEmpty);
        expect(
          {for (final r in responses()) r['id']: r['error']},
          {
            'sign-1': 'The Symudol vault was erased',
            'encrypt-1': 'The Symudol vault was erased',
          },
        );
      });

      test('revoking a session answers and drops its queued requests',
          () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');

        await controller.revokeSession(session.id);

        expect(controller.state.pendingMethodRequests, isEmpty);
        expect(responses().single, {
          'id': 'sign-1',
          'result': null,
          'error': 'Session has been revoked.',
        });
      });

      test('a lock keeps the queue', () async {
        final session = await unlockedSession();
        await sendNote(session, 'sign-1');

        await vaultController.lock();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.pendingMethodRequests, hasLength(1));
        expect(relayService.capturedPublishes, isEmpty);
      });
    });

    // Remembered decisions: from the connect approval and from review,
    // matched by kind (diogel-io/symudol#28).
    group('remembered decisions (#28)', () {
      Future<void> unlock() async {
        await vaultController.createVault('1234');
        await vaultController.createIdentity();
      }

      Future<void> sendKind(Nip46Session session, String id, int kind) => send(
        session,
        'sign_event',
        id: id,
        params: [
          jsonEncode({'kind': kind, 'content': 'k$kind', 'tags': <Object>[]}),
        ],
      );

      Map<String, Object?> answer(String id) =>
          responses().lastWhere((r) => r['id'] == id);

      test('approved connect perms sign their kind without review', () async {
        await unlock();
        final session = await activeBunkerSession(
          perms: 'sign_event:1,nip44_encrypt',
        );
        expect(
          session.grants.map((g) => g.scope.wire),
          unorderedEquals(['sign_event:1', 'nip44_encrypt']),
        );
        expect(
          session.grants.map((g) => g.identityPubkey).toSet(),
          {vaultController.state.activeIdentity!.publicKey},
        );
        expect(session.requestedScopes, isEmpty);

        await sendKind(session, 'note', 1);
        await sendKind(session, 'reaction', 7);

        expect(answer('note')['error'], isNull);
        expect(answer('note')['result'], contains('"kind":1'));
        expect(
          controller.state.pendingMethodRequests.single.request.id,
          'reaction',
        );
      });

      test('approving the connect just once remembers nothing', () async {
        await unlock();
        final session = await activeBunkerSession(
          perms: 'sign_event:1',
          timeframe: Nip55ApprovalTimeframe.justOnce,
        );
        expect(session.grants, isEmpty);

        await sendKind(session, 'note', 1);

        expect(controller.state.pendingMethodRequests, hasLength(1));
      });

      test('a broad sign_event in perms is never remembered', () async {
        await unlock();
        final session = await activeBunkerSession(
          perms: 'sign_event,nip44_encrypt',
        );

        expect(session.grants.map((g) => g.scope.wire), ['nip44_encrypt']);
        await sendKind(session, 'note', 1);
        expect(controller.state.pendingMethodRequests, hasLength(1));
      });

      test('8 hours expires eight hours from approval', () async {
        await unlock();
        final before = DateTime.now();
        final session = await activeBunkerSession(
          perms: 'sign_event:1',
          timeframe: Nip55ApprovalTimeframe.eightHours,
        );

        final expiry = session.grants.single.expiresAt!;
        expect(
          expiry.difference(before).inSeconds,
          inInclusiveRange(8 * 3600, 8 * 3600 + 60),
        );
      });

      test("a nostrconnect URI's perms are offered and remembered", () async {
        await unlock();
        await controller.importNostrconnectToken(
          'nostrconnect://$clientPubkey?secret=s3cr3t'
          '&relay=${Uri.encodeComponent("wss://relay.example.com")}'
          '&perms=${Uri.encodeComponent("sign_event:1,nip04_decrypt")}',
        );
        expect(
          controller.state.pendingApproval!.requestedScopes.map((s) => s.wire),
          ['sign_event:1', 'nip04_decrypt'],
        );

        await controller.approveConnection(
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(
          controller.state.sessions.single.grants.map((g) => g.scope.wire),
          ['sign_event:1', 'nip04_decrypt'],
        );
      });

      test('a sign_event with no kind is refused, not queued', () async {
        await unlock();
        final session = await activeBunkerSession(perms: 'sign_event:1');

        await send(
          session,
          'sign_event',
          id: 'no-kind',
          params: [jsonEncode({'content': 'x', 'tags': <Object>[]})],
        );

        expect(controller.state.pendingMethodRequests, isEmpty);
        expect(answer('no-kind')['error'], 'sign_event: missing kind');
      });

      test('remembering an approval signs that kind next time', () async {
        await unlock();
        final session = await activeBunkerSession();
        await sendKind(session, 'first', 7);

        await controller.approveMethodRequest(
          controller.state.pendingMethodRequests.single.key,
          timeframe: Nip55ApprovalTimeframe.always,
        );
        await sendKind(session, 'second', 7);
        await sendKind(session, 'other', 1);

        expect(answer('first')['error'], isNull);
        expect(answer('second')['error'], isNull);
        expect(
          controller.state.pendingMethodRequests.single.request.id,
          'other',
        );
        final grant = controller.state.sessions.single.grants.single;
        expect(grant.scope.wire, 'sign_event:7');
        expect(
          grant.identityPubkey,
          vaultController.state.activeIdentity!.publicKey,
        );
      });

      test('a decision that cannot be stored still answers the client',
          () async {
        await unlock();
        final session = await activeBunkerSession();
        await sendKind(session, 'first', 7);
        // Only the save that remembers the decision fails.
        sessionStore.failNextSaves = 1;

        await controller.approveMethodRequest(
          controller.state.pendingMethodRequests.single.key,
          timeframe: Nip55ApprovalTimeframe.always,
        );

        expect(responses().where((r) => r['id'] == 'first'), hasLength(1));
        expect(answer('first')['error'], isNull);
        expect(controller.state.sessions.single.grants, isEmpty);
      });

      test('remembering a rejection refuses that kind next time', () async {
        await unlock();
        final session = await activeBunkerSession();
        await sendKind(session, 'first', 7);

        await controller.rejectMethodRequest(
          controller.state.pendingMethodRequests.single.key,
          timeframe: Nip55ApprovalTimeframe.always,
        );
        await sendKind(session, 'second', 7);

        expect(answer('second')['error'], 'Rejected by a remembered decision.');
        expect(controller.state.pendingMethodRequests, isEmpty);
      });

      test('a grant applies only under the identity it was made under',
          () async {
        await unlock();
        final session = await activeBunkerSession(perms: 'sign_event:1');
        final first = vaultController.state.activeIdentity!.localId;
        await vaultController.createIdentity();
        final other = vaultController.state.identities.firstWhere(
          (i) => i.localId != first,
        );
        await vaultController.setActiveIdentity(other.localId);

        await sendKind(session, 'note', 1);

        expect(controller.state.pendingMethodRequests, hasLength(1));
      });

      test('grants are stored with the session and go when it is revoked',
          () async {
        await unlock();
        final session = await activeBunkerSession(perms: 'sign_event:1');
        final stored = await sessionStore.listSessions();
        expect(stored.single.grants.single.scope.wire, 'sign_event:1');

        await controller.revokeSession(session.id);

        expect(await sessionStore.listSessions(), isEmpty);
      });
    });
  });
}
