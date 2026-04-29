import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_diogel/theme/tokens.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';

class CreateIdentityDialog extends ConsumerStatefulWidget {
  const CreateIdentityDialog({super.key});

  @override
  ConsumerState<CreateIdentityDialog> createState() => _CreateIdentityDialogState();
}

class _CreateIdentityDialogState extends ConsumerState<CreateIdentityDialog> {
  final _nameController = TextEditingController();
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createIdentity() async {
    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final name = _nameController.text.trim();
      await ref.read(vaultControllerProvider.notifier).createIdentity(
        displayName: name.isEmpty ? null : name,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Identity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter a display name for your new Nostr identity (optional).'),
          const SizedBox(height: DiogelSpacing.space4),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Display Name',
              hintText: 'e.g. satoshi_vision',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
              ),
              errorText: _error,
            ),
            enabled: !_isCreating,
            autofocus: true,
          ),
          if (_isCreating)
            const Padding(
              padding: EdgeInsets.only(top: DiogelSpacing.space4),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _createIdentity,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
