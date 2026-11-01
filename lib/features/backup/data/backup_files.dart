import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/vault_backup.dart';

/// Where backup files go and come from (diogel-io/symudol#25).
abstract class BackupFiles {
  /// Offers [file] through the system share sheet as [fileName]. Returns
  /// false when the user dismissed the sheet without sharing.
  Future<bool> share(Uint8List file, String fileName);

  /// The file the user picks, or null when they cancel.
  Future<Uint8List?> pick();
}

/// [BackupFiles] through the share sheet and the system document picker, so
/// Symudol needs no storage permission.
class SystemBackupFiles implements BackupFiles {
  const SystemBackupFiles();

  @override
  Future<bool> share(Uint8List file, String fileName) async {
    // share_plus writes the (already encrypted) file to the app's private
    // cache for the share sheet, and replaces it at the next share.
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(file, name: fileName, mimeType: 'application/json'),
        ],
        fileNameOverrides: [fileName],
        subject: 'Symudol vault backup',
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  @override
  Future<Uint8List?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Symudol backup',
          extensions: ['json'],
          // Drives and messengers often send JSON as plain text or bytes.
          mimeTypes: [
            'application/json',
            'text/plain',
            'application/octet-stream',
          ],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxVaultBackupBytes) {
      throw const VaultBackupFormatException('This file is too large.');
    }
    return file.readAsBytes();
  }
}
