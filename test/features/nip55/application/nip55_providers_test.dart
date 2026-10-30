import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_approval_timeframe.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_nip55_permission_store.dart';
import '../../../fakes/fake_vault_store.dart';
import 'nip55_controller_test.dart' show FakeNip55Gateway;

class _QuietNativeSync extends Nip55NativeMirrorSync {
  @override
  Future<void> wipeNativeState() async {}

  @override
  Future<void> syncGrants(List<Nip55PermissionGrant> grants) async {}

  @override
  Future<void> setActiveIdentityPubkey(String? pubkey) async {}

  @override
  Future<void> setActiveKey({
    required String privateKey,
    required String publicKey,
    required String localId,
  }) async {}

  @override
  Future<void> clearActiveKey() async {}

  @override
  Future<void> setLockDeadline(Duration delay) async {}

  @override
  Future<void> clearLockDeadline() async {}
}

/// A grant remembered through the NIP-55 controller reaches the Trusted apps
/// list that was already loaded, through the real provider wiring
/// (diogel-io/symudol#99).
void main() {
  test('a remembered grant reloads the Trusted apps list', () async {
    final store = FakeVaultStore();
    final setup = VaultServiceImpl(store);
    await setup.createVault('123456');
    await setup.createIdentity(displayName: 'Alice');
    final permissions = FakeNip55PermissionStore();
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWithValue(store),
        nip55GatewayProvider.overrideWithValue(FakeNip55Gateway()),
        nip55PermissionStoreProvider.overrideWithValue(permissions),
        nip46SessionStoreProvider.overrideWithValue(FakeNip46SessionStore()),
        nip55NativeSyncProvider.overrideWithValue(_QuietNativeSync()),
      ],
    );
    addTearDown(container.dispose);
    final vault = container.read(vaultControllerProvider.notifier);
    await vault.initialize();
    await vault.unlock('123456');

    // Trusted apps was opened once, while nothing was remembered.
    container.listen(nip55PermissionControllerProvider, (_, _) {});
    await container.read(nip55PermissionControllerProvider.notifier).load();
    expect(container.read(nip55PermissionControllerProvider).grants, isEmpty);

    final nip55 = container.read(nip55ControllerProvider.notifier);
    await nip55.handleRawIntent({
      'requestToken': 'pk-token',
      'type': 'get_public_key',
      'callingPackage': 'com.example.app',
      'callerCertificateSha256': 'AA:BB',
    });
    await nip55.approvePublicKeyRequest(
      timeframe: Nip55ApprovalTimeframe.always,
    );

    expect(permissions.grants, hasLength(1));
    expect(
      container.read(nip55PermissionControllerProvider).grants,
      hasLength(1),
    );
  });
}
