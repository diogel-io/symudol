import 'package:android_diogel/features/vault/application/vault_controller.dart';
import 'package:android_diogel/features/vault/data/secure_storage_vault_store.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the vault storage backend.
/// 
/// In tests, this can be overridden with a fake or mock store.
final vaultStoreProvider = Provider<VaultStore>((ref) {
  return SecureStorageVaultStore();
});

/// Provider for the [VaultService] implementation.
final vaultServiceProvider = Provider<VaultService>((ref) {
  final store = ref.watch(vaultStoreProvider);
  return VaultServiceImpl(store);
});

/// Provider that handles Vault initialization.
final vaultInitializationProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(vaultServiceProvider);
  if (service is VaultServiceImpl) {
    await service.init();
  }
});

/// Provider for the [VaultController].
final vaultControllerProvider = StateNotifierProvider<VaultController, VaultControllerState>((ref) {
  final service = ref.watch(vaultServiceProvider);
  return VaultController(service);
});

/// Provider for the [VaultState].
/// 
/// This allows the UI to reactively rebuild when the vault state changes.
final vaultStateProvider = Provider<VaultState>((ref) {
  return ref.watch(vaultControllerProvider).vaultState;
});
