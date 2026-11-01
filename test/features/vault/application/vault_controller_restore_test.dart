import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_failure.dart';
import 'package:symudol/features/vault/domain/vault_service.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_vault_store.dart';

/// Saves one identity, then fails, as a storage error partway through a
/// restore would.
class _FailingPartwayService extends VaultServiceImpl {
  _FailingPartwayService() : super(FakeVaultStore());

  @override
  Future<BackupRestoreResult> restoreBackup(
    Uint8List file,
    String passphrase,
  ) async {
    await createIdentity(displayName: 'Saved before the failure');
    throw const VaultStorageException('write failed');
  }
}

/// A restore that fails partway through still shows what it saved
/// (diogel-io/symudol#25).
void main() {
  test('Accounts shows identities saved before a restore failed', () async {
    final service = _FailingPartwayService();
    await service.createVault('123456');
    final controller = VaultController(service);
    await controller.initialize();
    await controller.unlock('123456');
    expect(controller.state.identities, isEmpty);

    final (result, failure) = await controller.restoreBackup(
      Uint8List(0),
      'a long passphrase',
    );

    expect(result, isNull);
    expect(failure, isA<VaultFailure>());
    expect(controller.state.identities.map((i) => i.displayName), [
      'Saved before the failure',
    ]);
    expect(controller.state.isLoading, isFalse);
  });
}
