import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

/// Explains that a forgotten PIN can't be recovered (#22).
///
/// Pops `true` when the user chooses to erase the vault and start again.
/// Restoring from a backup joins it once backups exist (#25).
class ForgotPinDialog extends StatelessWidget {
  const ForgotPinDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot your PIN?'),
      content: const Text(
        "Symudol can't recover or reset your PIN. Your keys are encrypted "
        'with it, and Symudol keeps no copy. To use Symudol again, erase this '
        "vault and set it up from scratch. Any key you haven't backed up "
        'elsewhere will be lost.',
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
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Erase and start again'),
        ),
      ],
    );
  }
}
