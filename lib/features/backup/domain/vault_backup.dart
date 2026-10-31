import 'dart:convert';
import 'dart:typed_data';

import '../data/scrypt_kdf.dart';
import 'nip49.dart';

/// The `type` of a Symudol vault backup file (diogel-io/symudol#25).
const String vaultBackupType = 'symudol-vault-backup';

/// The format version this build writes and reads.
const int vaultBackupVersion = 1;

/// The largest backup file read.
const int maxVaultBackupBytes = 1024 * 1024;

/// The most identities a backup may hold.
const int maxVaultBackupIdentities = 100;

/// The shortest passphrase a new backup accepts.
const int minBackupPassphraseLength = 12;

/// A file that is not a Symudol vault backup this build can read.
class VaultBackupFormatException implements Exception {
  const VaultBackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'VaultBackupFormatException: $message';
}

/// One identity in a backup: its key as an `ncryptsec`, and the label and
/// creation time it had. The label is readable without the passphrase, a
/// decision recorded on diogel-io/symudol#25.
class VaultBackupEntry {
  const VaultBackupEntry({required this.ncryptsec, this.name, this.createdAt});

  final String ncryptsec;
  final String? name;
  final DateTime? createdAt;
}

/// A private key to back up, with its label and creation time.
class VaultBackupKey {
  const VaultBackupKey({
    required this.privateKeyHex,
    this.name,
    this.createdAt,
  });

  final String privateKeyHex;
  final String? name;
  final DateTime? createdAt;
}

/// A decrypted backup entry, ready to import.
class RestoredKey {
  const RestoredKey({required this.privateKeyHex, this.name, this.createdAt});

  final String privateKeyHex;
  final String? name;
  final DateTime? createdAt;
}

/// The backup file for [keys], each encrypted with [key]: one passphrase
/// derivation for the whole file, and its own nonce for each key.
Uint8List buildVaultBackup(
  List<VaultBackupKey> keys,
  Nip49Key key, {
  DateTime? now,
}) {
  if (keys.isEmpty) {
    throw const VaultBackupFormatException('There is nothing to back up.');
  }
  final json = {
    'type': vaultBackupType,
    'version': vaultBackupVersion,
    'created_at': _seconds(now ?? DateTime.now()),
    'identities': [
      for (final entry in keys)
        {
          'ncryptsec': nip49Encrypt(_bytes(entry.privateKeyHex), key),
          if (entry.name != null) 'name': entry.name,
          if (entry.createdAt != null) 'created_at': _seconds(entry.createdAt!),
        },
    ],
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

/// The entries of the backup [file]. Throws [VaultBackupFormatException].
List<VaultBackupEntry> parseVaultBackup(Uint8List file) {
  if (file.length > maxVaultBackupBytes) {
    throw const VaultBackupFormatException('This file is too large.');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(file));
  } catch (_) {
    throw const VaultBackupFormatException(
      'This file is not a Symudol backup.',
    );
  }
  if (json is! Map || json['type'] != vaultBackupType) {
    throw const VaultBackupFormatException(
      'This file is not a Symudol backup.',
    );
  }
  if (json['version'] != vaultBackupVersion) {
    throw const VaultBackupFormatException(
      'This backup was made by a newer Symudol. Update Symudol to restore it.',
    );
  }
  final identities = json['identities'];
  if (identities is! List ||
      identities.isEmpty ||
      identities.length > maxVaultBackupIdentities) {
    throw const VaultBackupFormatException('This backup has no identities.');
  }
  return [
    for (final item in identities)
      if (item is Map && item['ncryptsec'] is String)
        VaultBackupEntry(
          ncryptsec: item['ncryptsec'] as String,
          name: item['name'] is String ? item['name'] as String : null,
          createdAt: item['created_at'] is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  (item['created_at'] as int) * 1000,
                )
              : null,
        )
      else
        throw const VaultBackupFormatException('This backup is damaged.'),
  ];
}

/// Decrypts every entry of the backup [file] with [passphrase] before any is
/// imported, so a wrong passphrase restores nothing. Entries sharing a salt
/// share one derivation, through [deriver]. Throws [Nip49Exception] for a
/// wrong passphrase and [VaultBackupFormatException] for a file it can't
/// read.
Future<List<RestoredKey>> decryptVaultBackup(
  Uint8List file,
  String passphrase, {
  required Nip49KeyDeriver deriver,
}) async {
  final entries = parseVaultBackup(file);
  final keys = <String, Nip49Key>{};
  final restored = <RestoredKey>[];
  for (final entry in entries) {
    final Nip49Payload payload;
    try {
      payload = nip49Parse(entry.ncryptsec);
    } on Nip49Exception {
      throw const VaultBackupFormatException('This backup is damaged.');
    }
    if (payload.logN > maxNip49LogN) {
      throw const VaultBackupFormatException(
        'This backup asks for more memory than this phone can give it.',
      );
    }
    final id = '${payload.logN}:${base64.encode(payload.salt)}';
    final key = keys[id] ??= await deriver.derive(
      passphrase,
      logN: payload.logN,
      salt: payload.salt,
    );
    restored.add(
      RestoredKey(
        privateKeyHex: _hex(nip49DecryptWith(payload, key)),
        name: entry.name,
        createdAt: entry.createdAt,
      ),
    );
  }
  return restored;
}

/// The file name a backup made at [now] is shared under.
String vaultBackupFileName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'symudol-backup-${now.year}-${two(now.month)}-${two(now.day)}.json';
}

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
