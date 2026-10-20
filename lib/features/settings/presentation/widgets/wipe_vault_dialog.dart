import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

/// Asks the user to confirm a vault wipe (#20). Names what is lost and only
/// enables the wipe once [confirmationWord] is typed.
///
/// Pops `true` when the user confirms.
class WipeVaultDialog extends StatefulWidget {
  static const String confirmationWord = 'WIPE';

  final int identityCount;
  final int connectionCount;

  const WipeVaultDialog({
    super.key,
    required this.identityCount,
    required this.connectionCount,
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
    final lost = [
      '${_plural(widget.identityCount, 'identity', 'identities')} and '
          '${widget.identityCount == 1 ? 'its private key' : 'their private keys'}',
      'Every Trusted app permission',
      _plural(widget.connectionCount, 'NIP-46 connection', 'NIP-46 connections'),
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
