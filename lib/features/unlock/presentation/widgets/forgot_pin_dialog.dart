import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

/// What the user chose in the Forgot PIN dialog.
enum ForgotPinChoice {
  /// Erase the vault and set it up again.
  erase,

  /// Erase the vault, set it up again, then restore a backup (#25).
  restore,
}

/// Explains that a forgotten PIN can't be recovered (#22).
///
/// Pops a [ForgotPinChoice], or null when cancelled.
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
        'elsewhere will be lost. If you have a Symudol backup, you can '
        'restore it after setting a new PIN.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ForgotPinChoice.restore),
          child: const Text('Restore from a backup'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: DiogelColors.stateError,
          ),
          onPressed: () => Navigator.of(context).pop(ForgotPinChoice.erase),
          child: const Text('Erase and start again'),
        ),
      ],
    );
  }
}
