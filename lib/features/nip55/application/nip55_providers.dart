import 'dart:typed_data';

import 'package:symudol/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/data/secure_storage_nip55_permission_store.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_store.dart';
import 'package:symudol/features/requests/application/request_providers.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'nip55_controller.dart';
import 'nip55_permission_controller.dart';

final nip55GatewayProvider = Provider<Nip55Gateway>((ref) {
  return Nip55MethodChannelGateway();
});

/// Fetches the launcher icon for a requesting Android app, keyed by package
/// name, so the signing request summary can show it instead of a generic
/// icon. Returns null if the package can't be resolved (e.g. browser flows).
final appIconProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  packageName,
) {
  return ref.watch(nip55GatewayProvider).getAppIcon(packageName);
});

final nip55NativeSyncProvider = Provider<Nip55NativeMirrorSync>((ref) {
  return Nip55NativeMirrorSync();
});

final nip55PermissionStoreProvider = Provider<Nip55PermissionStore>((ref) {
  return SecureStorageNip55PermissionStore(
    nativeSync: ref.watch(nip55NativeSyncProvider),
  );
});

final nip55PermissionControllerProvider =
    StateNotifierProvider<Nip55PermissionController, Nip55PermissionState>((
      ref,
    ) {
      final controller = Nip55PermissionController(
        store: ref.watch(nip55PermissionStoreProvider),
      );
      controller.load();
      return controller;
    });

final nip55ControllerProvider =
    StateNotifierProvider<Nip55Controller, Nip55State>((ref) {
      final gateway = ref.watch(nip55GatewayProvider);
      final vaultController = ref.watch(vaultControllerProvider.notifier);
      final vaultService = ref.watch(vaultServiceProvider);
      final requestController = ref.watch(requestControllerProvider.notifier);
      return Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        vaultService: vaultService,
        requestController: requestController,
        permissionStore: ref.watch(nip55PermissionStoreProvider),
        nativeSync: ref.watch(nip55NativeSyncProvider),
        // Read when a grant is stored, not watched: Trusted apps reloads
        // without rebuilding this controller (#99).
        onGrantsChanged: () =>
            ref.read(nip55PermissionControllerProvider.notifier).load(),
      );
    });

/// Whether a request is waiting on the Approval screen: a signing request
/// (pending or failed, see [activeRequestProvider]) or a NIP-55 public-key or
/// crypto request. The home shell brings the approval to the front when this
/// turns true (#121).
final hasPendingApprovalProvider = Provider<bool>((ref) {
  final nip55State = ref.watch(nip55ControllerProvider);
  return ref.watch(activeRequestProvider) != null ||
      nip55State.pendingPublicKeyRequest != null ||
      nip55State.pendingCryptoRequest != null;
});
