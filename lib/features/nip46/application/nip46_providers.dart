import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/data/secure_storage_nip46_session_store.dart';
import 'package:symudol/features/nip46/domain/nip46_pending_method_request.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'nip46_controller.dart';

final nip46RelayServiceProvider = Provider<Nip46RelayService>((ref) {
  final service = DartNip46RelayService();
  ref.onDispose(service.dispose);
  return service;
});

final nip46SessionStoreProvider = Provider<Nip46SessionStore>((ref) {
  return SecureStorageNip46SessionStore();
});

final nip46CryptoProvider = Provider<DartNip46Crypto>((ref) {
  return const DartNip46Crypto(DartNostrCryptoService());
});

final nip46ControllerProvider =
    StateNotifierProvider<Nip46Controller, Nip46State>((ref) {
      final controller = Nip46Controller(
        sessionStore: ref.watch(nip46SessionStoreProvider),
        vaultService: ref.watch(vaultServiceProvider),
        vaultController: ref.watch(vaultControllerProvider.notifier),
        relayService: ref.watch(nip46RelayServiceProvider),
        crypto: ref.watch(nip46CryptoProvider),
      );
      final queue = ref.read(nip46ReviewQueueProvider.notifier);
      final removeListener = controller.addListener(
        (state) => queue.state = state.pendingMethodRequests,
        fireImmediately: false,
      );
      ref.onDispose(() {
        removeListener();
        queue.state = const [];
      });
      return controller;
    });

/// The NIP-46 requests waiting for review, oldest first, as the controller
/// last published them (diogel-io/symudol#27).
///
/// The home shell and the Approval screen watch this, never
/// [nip46ControllerProvider]: creating the controller opens its relays, which
/// must only happen once Remote Signer is used (#26). A request can only be
/// queued once the controller exists, so approving one can read it.
final nip46ReviewQueueProvider =
    StateProvider<List<Nip46PendingMethodRequest>>((ref) => const []);
