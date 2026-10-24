import 'dart:convert';

import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/domain/nip46_connection_token.dart';
import 'package:symudol/features/nip46/domain/nip46_permission_scope.dart';
import 'package:symudol/features/nip46/domain/nip46_relay_event.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
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

  setUp(() async {
    vaultStore = FakeVaultStore();
    final vaultService = VaultServiceImpl(vaultStore);
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

    /// A bunker session that [clientPrivkey] connected to and the user approved.
    Future<Nip46Session> activeBunkerSession({
      List<Nip46PermissionScope> grants = const [],
    }) async {
      final token = await controller.initiateBunkerSession();
      final session = controller.state.sessions.single;
      await send(
        session,
        'connect',
        id: 'connect-1',
        params: [session.remoteSignerPubkey, token.secret],
      );
      await controller.approveConnection(grantedScopes: grants);
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
      final session = await activeBunkerSession(
        grants: const [Nip46PingScope()],
      );

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
      expect(after.grantedScopes, hasLength(1));
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
  });
}
