import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/backup/data/scrypt_kdf.dart';
import 'package:symudol/features/backup/domain/nip49.dart';
import 'package:symudol/features/backup/domain/vault_backup.dart';

const _key = '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';
const _other =
    '0101010101010101010101010101010101010101010101010101010101010101';

/// A cheap key, so the format tests stay fast.
Nip49Key _key4(String passphrase) => nip49DeriveKey(passphrase, logN: 4);

const _deriver = DartNip49KeyDeriver();

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// The Symudol vault backup file (diogel-io/symudol#25).
void main() {
  test('round trip keeps keys, names and times; one salt for all', () async {
    final created = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final file = buildVaultBackup([
      VaultBackupKey(privateKeyHex: _key, name: 'Work', createdAt: created),
      const VaultBackupKey(privateKeyHex: _other),
    ], _key4('a long passphrase'));

    final entries = parseVaultBackup(file);
    expect(entries.map((e) => e.name), ['Work', null]);
    expect(entries.first.createdAt, created);
    expect(
      nip49Parse(entries[0].ncryptsec).salt,
      nip49Parse(entries[1].ncryptsec).salt,
    );

    final keys = await decryptVaultBackup(
      file,
      'a long passphrase',
      deriver: _deriver,
    );
    expect(keys.map((k) => k.privateKeyHex), [_key, _other]);
  });

  test('a wrong passphrase is a NIP-49 failure', () async {
    final file = buildVaultBackup([
      const VaultBackupKey(privateKeyHex: _key),
    ], _key4('a long passphrase'));

    await expectLater(
      decryptVaultBackup(file, 'another passphrase', deriver: _deriver),
      throwsA(isA<Nip49Exception>()),
    );
  });

  test('refuses files that are not a readable backup', () {
    for (final file in [
      Uint8List.fromList([0xff, 0xfe]),
      _json({'type': 'other', 'version': 1, 'identities': []}),
      _json({'type': vaultBackupType, 'version': 2, 'identities': []}),
      _json({'type': vaultBackupType, 'version': 1, 'identities': []}),
      _json({
        'type': vaultBackupType,
        'version': 1,
        'identities': [
          {'name': 'no key'},
        ],
      }),
      _json({
        'type': vaultBackupType,
        'version': 1,
        'identities': List.filled(maxVaultBackupIdentities + 1, {
          'ncryptsec': 'x',
        }),
      }),
      Uint8List(maxVaultBackupBytes + 1),
    ]) {
      expect(
        () => parseVaultBackup(file),
        throwsA(isA<VaultBackupFormatException>()),
      );
    }
  });

  test(
    'a damaged ncryptsec is a format failure, not a wrong passphrase',
    () async {
      final file = _json({
        'type': vaultBackupType,
        'version': 1,
        'identities': [
          {'ncryptsec': 'ncryptsec1notvalid'},
        ],
      });

      await expectLater(
        decryptVaultBackup(file, 'a long passphrase', deriver: _deriver),
        throwsA(isA<VaultBackupFormatException>()),
      );
    },
  );

  test('refuses a cost above log_n 20 before deriving anything', () async {
    final key = Nip49Key(maxNip49LogN + 1, Uint8List(16), Uint8List(32));
    final file = _json({
      'type': vaultBackupType,
      'version': 1,
      'identities': [
        {'ncryptsec': nip49Encrypt(Uint8List(32)..[0] = 1, key)},
      ],
    });

    await expectLater(
      decryptVaultBackup(file, 'a long passphrase', deriver: _deriver),
      throwsA(isA<VaultBackupFormatException>()),
    );
  });

  test('says so when a backup has too many identities', () {
    expect(
      () => parseVaultBackup(
        _json({
          'type': vaultBackupType,
          'version': 1,
          'identities': List.filled(maxVaultBackupIdentities + 1, {
            'ncryptsec': 'x',
          }),
        }),
      ),
      throwsA(
        isA<VaultBackupFormatException>().having(
          (e) => e.message,
          'message',
          contains('more than $maxVaultBackupIdentities identities'),
        ),
      ),
    );
  });

  test('a creation time out of range is damage, not a crash', () {
    expect(
      () => parseVaultBackup(
        _json({
          'type': vaultBackupType,
          'version': 1,
          'identities': [
            {'ncryptsec': 'ncryptsec1x', 'created_at': 10000000000000},
          ],
        }),
      ),
      throwsA(
        isA<VaultBackupFormatException>().having(
          (e) => e.message,
          'message',
          'This backup is damaged.',
        ),
      ),
    );
  });

  test('names the file by date', () {
    expect(
      vaultBackupFileName(DateTime(2026, 3, 7)),
      'symudol-backup-2026-03-07.json',
    );
  });
}
