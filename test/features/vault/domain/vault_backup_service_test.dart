import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/backup/data/scrypt_kdf.dart';
import 'package:symudol/features/backup/domain/nip49.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_vault_store.dart';

const _pin = '123456';
const _passphrase = 'correct horse battery staple';

/// Backing up every identity and restoring them on another vault
/// (diogel-io/symudol#25).
void main() {
  Future<VaultServiceImpl> newVault() async {
    final vault = VaultServiceImpl(
      FakeVaultStore(),
      keyDeriver: const DartNip49KeyDeriver(),
    );
    await vault.createVault(_pin);
    return vault;
  }

  test('a backup restores every identity on another vault', () async {
    final source = await newVault();
    final created = await source.createIdentity(displayName: 'Work');
    final imported = await source.importIdentity(
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
      displayName: 'Personal',
    );

    final file = await source.exportBackup(pin: _pin, passphrase: _passphrase);

    final target = await newVault();
    final result = await target.restoreBackup(file, _passphrase);

    expect(result.skipped, 0);
    expect(
      {
        for (final identity in result.restored)
          identity.publicKey: identity.displayName,
      },
      {created.publicKey: 'Work', imported.publicKey: 'Personal'},
    );
    expect(
      (await target.listIdentities()).map((identity) => identity.publicKey),
      unorderedEquals([created.publicKey, imported.publicKey]),
    );
    // The first restored identity becomes active on an empty vault.
    expect(
      (await target.listIdentities()).where((i) => i.isActive),
      hasLength(1),
    );
  });

  test('the file holds ncryptsec keys and no raw key', () async {
    final source = await newVault();
    await source.importIdentity(
      '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
    );

    final file = await source.exportBackup(pin: _pin, passphrase: _passphrase);

    final text = utf8.decode(file);
    expect(text, isNot(contains('3501454135014541')));
    final json = jsonDecode(text) as Map;
    expect(json['type'], 'symudol-vault-backup');
    final ncryptsec =
        (json['identities'] as List).single['ncryptsec'] as String;
    expect(nip49Parse(ncryptsec).logN, 16);
    // Any NIP-49 reader opens it with the passphrase.
    expect(
      nip49Decrypt(ncryptsec, _passphrase),
      Uint8List.fromList([
        for (var i = 0; i < 64; i += 2)
          int.parse(
            '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683'
                .substring(i, i + 2),
            radix: 16,
          ),
      ]),
    );
  });

  test('a wrong PIN is refused and charged', () async {
    final source = await newVault();
    await source.createIdentity();

    await expectLater(
      source.exportBackup(pin: '654321', passphrase: _passphrase),
      throwsA(isA<InvalidPinException>()),
    );
    expect(await source.getFailedUnlockAttempts(), 1);
  });

  test('a short passphrase is refused before the PIN is checked', () async {
    final source = await newVault();
    await source.createIdentity();

    await expectLater(
      source.exportBackup(pin: '654321', passphrase: 'too short'),
      throwsA(isA<VaultBackupException>()),
    );
    expect(await source.getFailedUnlockAttempts(), 0);
  });

  test('an empty vault has nothing to back up', () async {
    final source = await newVault();

    await expectLater(
      source.exportBackup(pin: _pin, passphrase: _passphrase),
      throwsA(isA<VaultBackupException>()),
    );
  });

  test('a wrong passphrase restores nothing', () async {
    final source = await newVault();
    await source.createIdentity();
    await source.createIdentity();
    final file = await source.exportBackup(pin: _pin, passphrase: _passphrase);

    final target = await newVault();
    await expectLater(
      target.restoreBackup(file, 'not the passphrase at all'),
      throwsA(isA<BackupPassphraseException>()),
    );
    expect(await target.listIdentities(), isEmpty);
  });

  test('identities already in the vault are skipped', () async {
    final source = await newVault();
    await source.createIdentity(displayName: 'One');
    await source.createIdentity(displayName: 'Two');
    final file = await source.exportBackup(pin: _pin, passphrase: _passphrase);

    final first = await source.restoreBackup(file, _passphrase);

    expect(first.restored, isEmpty);
    expect(first.skipped, 2);
    expect(await source.listIdentities(), hasLength(2));
  });

  test('a file that is not a backup is refused', () async {
    final target = await newVault();

    await expectLater(
      target.restoreBackup(
        Uint8List.fromList(utf8.encode('{"type":"other"}')),
        _passphrase,
      ),
      throwsA(isA<VaultBackupException>()),
    );
  });

  test('a locked vault neither backs up nor restores', () async {
    final source = await newVault();
    await source.createIdentity();
    final file = await source.exportBackup(pin: _pin, passphrase: _passphrase);
    await source.lock();

    await expectLater(
      source.exportBackup(pin: _pin, passphrase: _passphrase),
      throwsA(isA<VaultLockedException>()),
    );
    await expectLater(
      source.restoreBackup(file, _passphrase),
      throwsA(isA<VaultLockedException>()),
    );
  });

  test(
    'a key that cannot be derived is not called a wrong passphrase',
    () async {
      final source = await newVault();
      await source.createIdentity();
      final file = await source.exportBackup(
        pin: _pin,
        passphrase: _passphrase,
      );

      final target = VaultServiceImpl(
        FakeVaultStore(),
        keyDeriver: const _FailingDeriver(),
      );
      await target.createVault(_pin);

      await expectLater(
        target.restoreBackup(file, _passphrase),
        throwsA(
          isA<VaultBackupException>().having(
            (e) => e.message,
            'message',
            contains('needs more memory'),
          ),
        ),
      );
    },
  );

  test('an invalid key anywhere in the file imports nothing', () async {
    final key = nip49DeriveKey(_passphrase, logN: 4);
    final valid = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final file = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'type': 'symudol-vault-backup',
          'version': 1,
          'identities': [
            {'ncryptsec': nip49Encrypt(valid, key), 'name': 'Good'},
            // Zero is not a secp256k1 secret key.
            {'ncryptsec': nip49Encrypt(Uint8List(32), key), 'name': 'Bad'},
          ],
        }),
      ),
    );
    final target = await newVault();

    await expectLater(
      target.restoreBackup(file, _passphrase),
      throwsA(isA<VaultBackupException>()),
    );
    expect(await target.listIdentities(), isEmpty);
  });
}

/// Fails as the native scrypt does when the phone lacks the memory.
class _FailingDeriver implements Nip49KeyDeriver {
  const _FailingDeriver();

  @override
  Future<Nip49Key> derive(
    String passphrase, {
    int logN = nip49DefaultLogN,
    Uint8List? salt,
  }) async => throw const Nip49DerivationException('OUT_OF_MEMORY');
}
