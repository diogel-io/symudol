import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for the current PIN before biometric unlock is turned on (#23).
///
/// Pops the 6-digit PIN, or `null` if cancelled. The PIN is checked by the
/// vault like an unlock, so a wrong one counts towards the lockout.
class BiometricPinDialog extends StatefulWidget {
  const BiometricPinDialog({super.key});

  @override
  State<BiometricPinDialog> createState() => _BiometricPinDialogState();
}

class _BiometricPinDialogState extends State<BiometricPinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _complete => _controller.text.length == 6;

  void _submit() {
    if (_complete) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Turn on biometric unlock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your PIN, then confirm with your fingerprint. Symudol '
            'still asks for the PIN after a restart or every 72 hours.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('biometricPinField'),
            controller: _controller,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enableInteractiveSelection: false,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              counterText: '',
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
          onPressed: _complete ? _submit : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
