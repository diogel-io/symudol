import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for the current PIN before a sensitive step: turning on biometric
/// unlock (#23) or making a backup (#25).
///
/// Pops the 6-digit PIN, or `null` if cancelled. The PIN is checked by the
/// vault like an unlock, so a wrong one counts towards the lockout.
class ConfirmPinDialog extends StatefulWidget {
  const ConfirmPinDialog({
    super.key,
    required this.title,
    required this.message,
    this.fieldKey,
  });

  final String title;
  final String message;

  /// The PIN field's key, for tests.
  final Key? fieldKey;

  @override
  State<ConfirmPinDialog> createState() => _ConfirmPinDialogState();
}

class _ConfirmPinDialogState extends State<ConfirmPinDialog> {
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
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            key: widget.fieldKey,
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
