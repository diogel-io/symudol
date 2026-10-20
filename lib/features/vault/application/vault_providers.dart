import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/data/secure_storage_vault_store.dart';
import 'package:symudol/features/vault/domain/vault_service.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:symudol/features/vault/domain/vault_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Provider for the vault storage backend.
/// 
/// In tests, this can be overridden with a fake or mock store.
final vaultStoreProvider = Provider<VaultStore>((ref) {
  // If we're running tests, we might want to ensure a clean state or use a mock.
  // SecureStorageVaultStore uses FlutterSecureStorage which has a web/linux mock automatically 
  // if not overridden, but in unit tests we often need to be careful.
  return SecureStorageVaultStore();
});

/// Provider for the [VaultService] implementation.
///
/// It gets the NIP-55 and NIP-46 stores so a wipe can erase them too (#20).
/// None of those providers depends on the vault.
final vaultServiceProvider = Provider<VaultService>((ref) {
  final store = ref.watch(vaultStoreProvider);
  final nativeSync = ref.watch(nip55NativeSyncProvider);
  return VaultServiceImpl(
    store,
    nip55PermissionStore: ref.watch(nip55PermissionStoreProvider),
    nip46SessionStore: ref.watch(nip46SessionStoreProvider),
    wipeNativeState: nativeSync.wipeNativeState,
  );
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
