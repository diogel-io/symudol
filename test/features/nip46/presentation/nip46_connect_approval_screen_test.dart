import 'package:symudol/features/nip46/application/nip46_controller.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/presentation/nip46_connect_approval_screen.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_vault_store.dart';
import '../data/fake_nip46_relay_service.dart';

Nip46Controller _buildController() {
  final vaultService = VaultServiceImpl(FakeVaultStore());
  return Nip46Controller(
    sessionStore: FakeNip46SessionStore([]),
    vaultService: vaultService,
    vaultController: VaultController(vaultService),
    relayService: FakeNip46RelayService(),
    crypto: DartNip46Crypto(const DartNostrCryptoService()),
  );
}

void main() {
  // Remote Signer can open this after the request has ended, for example
  // when it times out between the tap on Review request and the first build
  // (diogel-io/symudol#125).
  testWidgets('says a request that has ended has ended, and Close pops it', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nip46ControllerProvider.overrideWith((ref) => _buildController()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const Nip46ConnectApprovalScreen(),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('This connection request has ended.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Approve'), findsNothing);

    await tester.tap(find.byKey(const Key('nip46RequestEndedClose')));
    await tester.pumpAndSettle();

    expect(find.byType(Nip46ConnectApprovalScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
