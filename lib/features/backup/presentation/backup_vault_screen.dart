import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../settings/presentation/widgets/confirm_pin_dialog.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/presentation/vault_failure_messages.dart';
import '../application/backup_providers.dart';
import '../domain/vault_backup.dart';
import 'restore_backup_flow.dart';

/// Backs up every identity to a passphrase-encrypted file, and restores one
/// (diogel-io/symudol#25).
class BackupVaultScreen extends ConsumerStatefulWidget {
  const BackupVaultScreen({super.key});

  @override
  ConsumerState<BackupVaultScreen> createState() => _BackupVaultScreenState();
}

class _BackupVaultScreenState extends ConsumerState<BackupVaultScreen> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  bool _visible = false;
  bool _working = false;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _passphraseError {
    final text = _passphrase.text;
    if (text.isEmpty || text.length >= minBackupPassphraseLength) return null;
    return 'Use at least $minBackupPassphraseLength characters.';
  }

  String? get _confirmError {
    if (_confirm.text.isEmpty || _confirm.text == _passphrase.text) {
      return null;
    }
    return "The passphrases don't match.";
  }

  bool get _ready =>
      !_working &&
      _passphrase.text.length >= minBackupPassphraseLength &&
      _confirm.text == _passphrase.text;

  Future<void> _backUp() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const ConfirmPinDialog(
        title: 'Back up your vault',
        message: 'Enter your PIN to make the backup.',
        fieldKey: Key('backupPinField'),
      ),
    );
    if (pin == null || !mounted) return;

    setState(() => _working = true);
    final (file, failure) = await ref
        .read(vaultControllerProvider.notifier)
        .exportBackup(pin: pin, passphrase: _passphrase.text);
    if (!mounted) return;
    setState(() => _working = false);
    if (file == null) {
      _showMessage(
        failure == null
            ? "Couldn't make the backup. Try again."
            : vaultFailureMessage(failure),
      );
      return;
    }

    final bool shared;
    try {
      shared = await ref
          .read(backupFilesProvider)
          .share(file, vaultBackupFileName(DateTime.now()));
    } on PlatformException {
      if (mounted) _showMessage("Couldn't open the share sheet.");
      return;
    }
    if (!mounted) return;
    if (!shared) {
      _showMessage('The backup was not shared. Back up again to save it.');
      return;
    }
    _passphrase.clear();
    _confirm.clear();
    setState(() {});
    _showMessage(
      'Backup made. Keep the file and its passphrase somewhere safe, '
      'and apart.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup Vault')),
      body: ListView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Container(
            padding: const EdgeInsets.all(DiogelSpacing.space4),
            decoration: BoxDecoration(
              color: DiogelColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(DiogelRadius.large),
            ),
            child: const Text(
              'The backup holds every identity in this vault, encrypted with '
              'a passphrase you choose. Anyone with the file and the '
              "passphrase controls these identities. Symudol can't recover a "
              'forgotten passphrase. If you lose this phone or your PIN, the '
              'backup is the only way to get these identities back.',
            ),
          ),
          const SizedBox(height: DiogelSpacing.space6),
          Text('Make a backup', style: textTheme.titleMedium),
          const SizedBox(height: DiogelSpacing.space3),
          TextField(
            key: const Key('backupPassphraseField'),
            controller: _passphrase,
            obscureText: !_visible,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.visiblePassword,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Passphrase',
              helperText:
                  'Four or more random words are strong and easy to type.',
              helperMaxLines: 2,
              errorText: _passphraseError,
              suffixIcon: IconButton(
                tooltip: _visible ? 'Hide passphrase' : 'Show passphrase',
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          TextField(
            key: const Key('backupConfirmField'),
            controller: _confirm,
            obscureText: !_visible,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.visiblePassword,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Confirm passphrase',
              errorText: _confirmError,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          FilledButton.icon(
            onPressed: _ready ? _backUp : null,
            icon: _working
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup_outlined),
            label: Text(_working ? 'Encrypting…' : 'Back up and share'),
          ),
          const SizedBox(height: DiogelSpacing.space8),
          Text('Restore', style: textTheme.titleMedium),
          const SizedBox(height: DiogelSpacing.space2),
          Text(
            'Add the identities from a backup file to this vault. Identities '
            'already here are skipped.',
            style: textTheme.bodyMedium?.copyWith(
              color: DiogelColors.textSecondary,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space3),
          OutlinedButton.icon(
            onPressed: _working ? null : () => restoreFromBackup(context, ref),
            icon: const Icon(Icons.restore),
            label: const Text('Restore from a backup'),
          ),
        ],
      ),
    );
  }
}
