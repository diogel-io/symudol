import 'package:android_diogel/features/vault/data/secure_storage_vault_store.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_service_impl.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';

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

/// A notifier that exposes the [VaultState] from [VaultService].
class VaultStateNotifier extends StateNotifier<VaultState> {
  final VaultService _vaultService;

  VaultStateNotifier(this._vaultService) : super(_vaultService.state);

  // We should ideally have the VaultService notify us of state changes.
  // Since VaultService currently doesn't have a stream, we might need to 
  // wrap its methods or add a listener mechanism.
  
  // For the purpose of Task 4.1, we'll keep it simple.
  void updateState() {
    state = _vaultService.state;
  }
}

/// Provider for the [VaultState].
/// 
/// This allows the UI to reactively rebuild when the vault state changes.
/// NOTE: To make this truly reactive, VaultService should probably 
/// expose a stream or use a ChangeNotifier/StateNotifier internally.
final vaultStateProvider = Provider<VaultState>((ref) {
  final service = ref.watch(vaultServiceProvider);
  return service.state;
});
