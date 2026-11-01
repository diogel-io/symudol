import 'package:flutter/material.dart';

import 'confirm_pin_dialog.dart';

/// Asks for the current PIN before biometric unlock is turned on (#23).
///
/// Pops the 6-digit PIN, or `null` if cancelled. The PIN is checked by the
/// vault like an unlock, so a wrong one counts towards the lockout.
class BiometricPinDialog extends StatelessWidget {
  const BiometricPinDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const ConfirmPinDialog(
      title: 'Turn on biometric unlock',
      message:
          'Enter your PIN, then confirm with your fingerprint or face. '
          'Symudol '
          'still asks for the PIN after a restart or every 72 hours.',
      fieldKey: Key('biometricPinField'),
    );
  }
}
