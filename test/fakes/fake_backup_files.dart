import 'dart:typed_data';

import 'package:symudol/features/backup/data/backup_files.dart';

/// Records what was shared, and returns [picked] when a file is picked
/// (diogel-io/symudol#25).
class FakeBackupFiles implements BackupFiles {
  FakeBackupFiles({this.picked});

  /// What [pick] returns; null as when the user cancels.
  Uint8List? picked;

  /// How many times [pick] was called.
  int picks = 0;

  final List<({Uint8List file, String fileName})> shared = [];

  /// What [share] reports: false as when the user dismisses the sheet.
  bool completesShare = true;

  @override
  Future<bool> share(Uint8List file, String fileName) async {
    shared.add((file: file, fileName: fileName));
    return completesShare;
  }

  @override
  Future<Uint8List?> pick() async {
    picks++;
    return picked;
  }
}
