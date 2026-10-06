import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';
import 'package:symudol/features/nip46/presentation/nip46_connections_screen.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';

class _FakeSessionStore implements Nip46SessionStore {
  final List<Nip46Session> _sessions;
  _FakeSessionStore([List<Nip46Session>? sessions])
    : _sessions = sessions ?? [];

  @override
  Future<List<Nip46Session>> listSessions() async => List.of(_sessions);

  @override
  Future<void> saveSession(Nip46Session session) async {}

  @override
  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> clearAll() async => _sessions.clear();
}

Nip46Controller _buildController({List<Nip46Session> sessions = const []}) {
  final vaultStore = FakeVaultStore();
  final vaultService = VaultServiceImpl(vaultStore);
  final vaultController = VaultController(vaultService);
  final relayService = FakeNip46RelayService();
  final crypto = DartNip46Crypto(const DartNostrCryptoService());
  return Nip46Controller(
    sessionStore: _FakeSessionStore(List.of(sessions)),
    vaultService: vaultService,
    vaultController: vaultController,
    relayService: relayService,
    crypto: crypto,
  );
}

Widget _buildSubject(Nip46Controller controller) {
  return ProviderScope(
    overrides: [
      nip46ControllerProvider.overrideWith((ref) => controller),
    ],
    child: const MaterialApp(
      home: Nip46ConnectionsScreen(),
    ),
  );
}

void main() {
  group('Nip46ConnectionsScreen', () {
    testWidgets('shows empty state when no sessions exist', (tester) async {
      await tester.pumpWidget(_buildSubject(_buildController()));
      await tester.pump();

      expect(find.text('No remote signer connections'), findsOneWidget);
      expect(find.text('New connection'), findsWidgets);
    });

    testWidgets('shows active session tile', (tester) async {
      final session = _session(clientName: 'Amethyst');
      await tester.pumpWidget(_buildSubject(_buildController(sessions: [session])));
      await tester.pumpAndSettle();

      expect(find.text('Amethyst'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);
    });

    testWidgets('appbar tooltip is New connection', (tester) async {
      await tester.pumpWidget(_buildSubject(_buildController()));
      await tester.pump();

      expect(find.byTooltip('New connection'), findsOneWidget);
    });

    testWidgets('screen title is Remote Signer (NIP-46)', (tester) async {
      await tester.pumpWidget(_buildSubject(_buildController()));
      await tester.pump();

      expect(find.text('Remote Signer (NIP-46)'), findsOneWidget);
    });
  });
}

Nip46Session _session({String? clientName}) {
  return Nip46Session(
    id: 'sess-1',
    clientPubkey:
        'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1',
    remoteSignerPubkey:
        'b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2',
    remoteSignerPrivkey: '0' * 64,
    relays: const ['wss://relay.example.com'],
    grantedScopes: const [],
    status: Nip46SessionStatus.active,
    createdAt: DateTime(2026),
    clientName: clientName,
  );
}
