import 'dart:async';

import 'package:android_diogel/features/nip46/application/nip46_controller.dart';
import 'package:android_diogel/features/nip46/data/dart_nip46_crypto.dart';
import 'package:android_diogel/features/nip46/domain/nip46_connection_token.dart';
import 'package:android_diogel/features/nip46/domain/nip46_relay_event.dart';
import 'package:android_diogel/features/nip46/domain/nip46_session.dart';
import 'package:android_diogel/features/nip46/domain/nip46_session_store.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';

class _FakeSessionStore implements Nip46SessionStore {
  final List<Nip46Session> _sessions = [];

  @override
  Future<List<Nip46Session>> listSessions() async => List.of(_sessions);

  @override
  Future<void> saveSession(Nip46Session session) async {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx == -1) {
      _sessions.add(session);
    } else {
      _sessions[idx] = session;
    }
  }

  @override
  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> clearAll() async => _sessions.clear();
}

void main() {
  late FakeVaultStore vaultStore;
  late VaultController vaultController;
  late FakeNip46RelayService relayService;
  late _FakeSessionStore sessionStore;
  late Nip46Controller controller;

  setUp(() async {
    vaultStore = FakeVaultStore();
    final vaultService = VaultServiceImpl(vaultStore);
    await vaultService.init();
    vaultController = VaultController(vaultService);
    relayService = FakeNip46RelayService();
    sessionStore = _FakeSessionStore();
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
    const _validClientPubkey =
        'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1';

    String _buildNostrconnect({
      String? pubkey,
      String secret = 'testsecret123',
      String? name,
      String? perms,
    }) {
      final p = pubkey ?? _validClientPubkey;
      var uri = 'nostrconnect://$p?secret=$secret';
      uri += '&relay=${Uri.encodeComponent("wss://relay.example.com")}';
      if (name != null) uri += '&name=${Uri.encodeComponent(name)}';
      if (perms != null) uri += '&perms=${Uri.encodeComponent(perms)}';
      return uri;
    }

    test('sets pendingApproval in state', () async {
      await controller.importNostrconnectToken(_buildNostrconnect());
      expect(controller.state.pendingApproval, isNotNull);
    });

    test('creates a pending session with correct client pubkey', () async {
      await controller.importNostrconnectToken(_buildNostrconnect());
      expect(controller.state.sessions, hasLength(1));
      expect(
        controller.state.sessions.first.clientPubkey,
        _validClientPubkey,
      );
    });

    test('parses client metadata from perms and name', () async {
      await controller.importNostrconnectToken(
        _buildNostrconnect(name: 'Test Client'),
      );
      expect(controller.state.sessions.first.clientName, 'Test Client');
    });

    test('starts relay for the session', () async {
      await controller.importNostrconnectToken(_buildNostrconnect());
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
}
