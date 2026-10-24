import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symudol/app/diogel_log.dart';

import '../../../../theme/tokens.dart';
import '../../../nip46/application/nip46_feature.dart';
import '../../../nip46/application/nip46_providers.dart';
import '../../../vault/application/vault_providers.dart';
import '../../../vault/presentation/vault_failure_messages.dart';

/// Asks for confirmation, then erases the vault (#20). The one wipe flow for
/// Settings → Wipe Vault and the unlock screen's Forgot PIN (#22).
///
/// Works locked or unlocked: the counts come from the stored identity and
/// session records, which hold no secrets. Afterwards the app shows setup,
/// and the NIP-55 controller answers any client waiting for an unlock
/// (#104).
Future<void> confirmAndWipeVault(BuildContext context, WidgetRef ref) async {
  // The counts only inform the confirmation: a store that can't be read
  // must still be erasable, so the dialog names what is lost without them.
  final identityCount = await _countOrNull(
    'identities',
    () async => (await ref.read(vaultStoreProvider).getIdentities()).length,
  );
  // A build that hides NIP-46 doesn't mention it, though the wipe still
  // clears any sessions an earlier build stored (#26).
  final showConnections = ref.read(nip46EnabledProvider);
  // Read from the store: the NIP-46 controller starts relays when created.
  final connectionCount = showConnections
      ? await _countOrNull(
          'NIP-46 sessions',
          () async =>
              (await ref.read(nip46SessionStoreProvider).listSessions()).length,
        )
      : null;
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => WipeVaultDialog(
      identityCount: identityCount,
      connectionCount: connectionCount,
      showConnections: showConnections,
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(vaultControllerProvider.notifier);
  Navigator.of(context).popUntil((route) => route.isFirst);
  // The app switches to setup once the vault is gone.
  final failure = await controller.wipe();
  if (failure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(vaultFailureMessage(failure))),
    );
  }
}

Future<int?> _countOrNull(String name, Future<int> Function() count) async {
  try {
    return await count();
  } catch (e, stack) {
    diogelLog(
      'confirmAndWipeVault: could not count $name',
      error: e,
      stackTrace: stack,
    );
    return null;
  }
}

/// Asks the user to confirm a vault wipe (#20). Names what is lost and only
/// enables the wipe once [confirmationWord] is typed.
///
/// Pops `true` when the user confirms.
class WipeVaultDialog extends StatefulWidget {
  static const String confirmationWord = 'WIPE';

  /// Null when the stored records could not be read: the dialog then names
  /// every identity and connection without a count.
  final int? identityCount;
  final int? connectionCount;

  /// False in builds that hide NIP-46: the dialog then leaves connections out.
  final bool showConnections;

  const WipeVaultDialog({
    super.key,
    required this.identityCount,
    required this.connectionCount,
    this.showConnections = true,
  });

  @override
  State<WipeVaultDialog> createState() => _WipeVaultDialogState();
}

class _WipeVaultDialogState extends State<WipeVaultDialog> {
  final _controller = TextEditingController();

  bool get _confirmed =>
      _controller.text.trim() == WipeVaultDialog.confirmationWord;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _plural(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final identityCount = widget.identityCount;
    final connectionCount = widget.connectionCount;
    final lost = [
      identityCount == null
          ? 'Every identity and its private key'
          : '${_plural(identityCount, 'identity', 'identities')} and '
                '${identityCount == 1 ? 'its private key' : 'their private keys'}',
      'Every Trusted app permission',
      if (widget.showConnections)
        connectionCount == null
            ? 'Every NIP-46 connection'
            : _plural(
                connectionCount,
                'NIP-46 connection',
                'NIP-46 connections',
              ),
    ];

    return AlertDialog(
      title: const Text('Wipe vault?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes from this phone:',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: DiogelSpacing.space2),
            for (final item in lost)
              Padding(
                padding: const EdgeInsets.only(bottom: DiogelSpacing.space1),
                child: Text('• $item', style: textTheme.bodyMedium),
              ),
            const SizedBox(height: DiogelSpacing.space2),
            Text(
              'It cannot be undone. Symudol keeps no copy, so any key you '
              'have not backed up elsewhere is gone for good.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: DiogelSpacing.space4),
            TextField(
              key: const Key('wipeVaultConfirmationField'),
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText:
                    'Type ${WipeVaultDialog.confirmationWord} to confirm',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: DiogelColors.stateError,
          ),
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Wipe vault'),
        ),
      ],
    );
  }
}
