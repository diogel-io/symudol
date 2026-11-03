import 'dart:async';

import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/data/method_channel_nip46_background.dart';
import 'package:symudol/features/nip46/data/method_channel_nip46_links.dart';
import 'package:symudol/features/nip46/data/secure_storage_nip46_session_store.dart';
import 'package:symudol/features/nip46/domain/nip46_pending_method_request.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'nip46_controller.dart';
import 'nip46_link_handler.dart';

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

/// The Android foreground service and request notices (#29). A no-op where
/// nothing answers its channel.
final nip46BackgroundProvider = Provider<MethodChannelNip46Background>(
  (ref) => MethodChannelNip46Background(),
);

/// nostrconnect: links from other apps (#31). Never has a link where nothing
/// answers its channel.
final nip46LinksProvider = Provider<Nip46Links>(
  (ref) => MethodChannelNip46Links(),
);

final nip46ControllerProvider =
    StateNotifierProvider<Nip46Controller, Nip46State>((ref) {
      final background = ref.watch(nip46BackgroundProvider);
      final controller = Nip46Controller(
        sessionStore: ref.watch(nip46SessionStoreProvider),
        vaultService: ref.watch(vaultServiceProvider),
        vaultController: ref.watch(vaultControllerProvider.notifier),
        relayService: ref.watch(nip46RelayServiceProvider),
        crypto: ref.watch(nip46CryptoProvider),
        notifier: background,
      );
      // Stop on the service's notification turns the setting off: the user
      // no longer wants remote signing in the background.
      final stops = background.stopRequests.listen(
        (_) => controller.setRunInBackground(false),
      );
      ref.onDispose(stops.cancel);
      // The service stops once nothing needs it, such as when a client logs
      // out of the last session while Symudol is in the background.
      var wanted = controller.wantsBackgroundService;
      final removeServiceWatch = controller.addListener((_) {
        final now = controller.wantsBackgroundService;
        if (wanted && !now) unawaited(background.stop());
        wanted = now;
      }, fireImmediately: false);
      ref.onDispose(removeServiceWatch);
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
