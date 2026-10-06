import 'package:symudol/features/nip46/data/dart_nip46_crypto.dart';
import 'package:symudol/features/nip46/data/dart_nip46_relay_service.dart';
import 'package:symudol/features/nip46/data/secure_storage_nip46_session_store.dart';
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
      return Nip46Controller(
        sessionStore: ref.watch(nip46SessionStoreProvider),
        vaultService: ref.watch(vaultServiceProvider),
        vaultController: ref.watch(vaultControllerProvider.notifier),
        relayService: ref.watch(nip46RelayServiceProvider),
        crypto: ref.watch(nip46CryptoProvider),
      );
    });
