import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_pop.dart';
import '../../../app/system_picker.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_failure.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/presentation/vault_failure_messages.dart';
import '../application/backup_providers.dart';
import '../domain/vault_backup.dart';

/// Picks a backup file, asks for its passphrase and imports its identities
/// (diogel-io/symudol#25). Used from Settings, an empty Accounts screen and
/// the Forgot PIN flow.
Future<void> restoreFromBackup(BuildContext context, WidgetRef ref) async {
  final Uint8List? file;
  try {
    // The document picker sends Symudol to the background; the lock waits.
    file = await ref
        .read(systemPickerOpenProvider.notifier)
        .during(() => ref.read(backupFilesProvider).pick());
  } on VaultBackupFormatException catch (error) {
    if (context.mounted) _showError(context, error.message);
    return;
  } on PlatformException {
    if (context.mounted) _showError(context, "Couldn't open your files.");
    return;
  } catch (_) {
    if (context.mounted) _showError(context, "Couldn't read that file.");
    return;
  }
  if (file == null || !context.mounted) return;

  final passphrase = await showDialog<String>(
    context: context,
    builder: (_) => const _PassphraseDialog(),
  );
  if (passphrase == null || !context.mounted) return;

  // Started before the dialog is built: it changes the vault state.
  final restore = ref
      .read(vaultControllerProvider.notifier)
      .restoreBackup(file, passphrase);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RestoreDialog(restore: restore),
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for the passphrase the backup was made with.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _controller = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) popIfCurrent(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restore from a backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter the passphrase this backup was made with.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('restorePassphraseField'),
            controller: _controller,
            autofocus: true,
            obscureText: !_visible,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              suffixIcon: IconButton(
                tooltip: _visible ? 'Hide passphrase' : 'Show passphrase',
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.isEmpty ? null : _submit,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

/// Shows "Decrypting…" while the restore runs, then what it did.
class _RestoreDialog extends StatelessWidget {
  const _RestoreDialog({required this.restore});

  final Future<(BackupRestoreResult?, VaultFailure?)> restore;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: restore,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final (result, failure) = snapshot.data ?? (null, null);
        return AlertDialog(
          title: Text(
            !done
                ? 'Restoring…'
                : result == null
                ? "Couldn't restore"
                : 'Backup restored',
          ),
          content: !done
              ? const Row(
                  children: [
                    SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 16),
                    Expanded(child: Text('Decrypting the backup…')),
                  ],
                )
              : Text(
                  result != null
                      ? _summary(result)
                      : failure != null
                      ? vaultFailureMessage(failure)
                      : "Couldn't restore the backup. Try again.",
                ),
          actions: [
            if (done)
              FilledButton(
                onPressed: () => popIfCurrent(context),
                child: const Text('OK'),
              ),
          ],
        );
      },
    );
  }

  static String _summary(BackupRestoreResult result) {
    String identities(int count) =>
        count == 1 ? '1 identity' : '$count identities';
    final restored = result.restored.length;
    final skipped = result.skipped;
    if (restored == 0) {
      return 'Every identity in this backup is already here.';
    }
    final already = skipped == 0
        ? ''
        : skipped == 1
        ? ' 1 was already here.'
        : ' $skipped were already here.';
    return 'Restored ${identities(restored)}.$already';
  }
}
