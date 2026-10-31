import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_files.dart';

/// Where backup files are shared to and picked from (diogel-io/symudol#25).
final backupFilesProvider = Provider<BackupFiles>((ref) {
  return const SystemBackupFiles();
});

/// Set when the user chose "Restore from a backup" in the Forgot PIN dialog:
/// once a new vault is set up, Accounts opens the restore (#22, #25).
final restoreAfterSetupProvider =
    NotifierProvider<RestoreAfterSetupNotifier, bool>(
      RestoreAfterSetupNotifier.new,
    );

class RestoreAfterSetupNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  /// Clears the request; true when there was one.
  bool take() {
    final requested = state;
    state = false;
    return requested;
  }
}
