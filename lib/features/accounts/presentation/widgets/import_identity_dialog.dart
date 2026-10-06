import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symudol/features/vault/presentation/vault_failure_messages.dart';
import 'package:symudol/theme/tokens.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';

class ImportIdentityDialog extends ConsumerStatefulWidget {
  const ImportIdentityDialog({super.key});

  @override
  ConsumerState<ImportIdentityDialog> createState() => _ImportIdentityDialogState();
}

enum ImportStep { warning, input, confirming }

class _ImportIdentityDialogState extends ConsumerState<ImportIdentityDialog> {
  final _keyController = TextEditingController();
  final _nameController = TextEditingController();
  ImportStep _currentStep = ImportStep.warning;
  bool _isLoading = false;
  String? _error;
  bool _obscureKey = true;

  @override
  void dispose() {
    _keyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onContinueFromWarning() {
    setState(() {
      _currentStep = ImportStep.input;
    });
  }

  Future<void> _importIdentity() async {
    final keyInput = _keyController.text.trim();
    if (keyInput.isEmpty) {
      setState(() => _error = 'Private key is required');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    
    final controller = ref.read(vaultControllerProvider.notifier);
    await controller.importIdentity(
      keyInput,
      displayName: name.isEmpty ? null : name,
    );
    
    // The controller update is async, and it updates the state.
    // We should check the state for failures.
    final state = ref.read(vaultControllerProvider);
    
    if (state.failure != null) {
      if (mounted) {
        setState(() {
          _error = vaultFailureMessage(state.failure!);
          _isLoading = false;
        });
      }
      return;
    }

    _keyController.clear();
    _nameController.clear();

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_getTitle()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepContent(),
            if (_error != null) ...[
              const SizedBox(height: DiogelSpacing.space4),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: DiogelSpacing.space4),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      actions: _buildActions(),
    );
  }

  String _getTitle() {
    switch (_currentStep) {
      case ImportStep.warning:
        return 'Import Identity';
      case ImportStep.input:
        return 'Enter Private Key';
      case ImportStep.confirming:
        return 'Confirm Import';
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case ImportStep.warning:
        return Column(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: DiogelSpacing.space4),
            const Text(
              'WARNING: Importing a private key is a sensitive operation. '
              'Ensure you are in a private environment and your screen is not being shared or recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: DiogelSpacing.space4),
            const Text(
              'Your key will be stored locally using the device platform secure-storage backend. Symudol never syncs or uploads it.',
              textAlign: TextAlign.center,
            ),
          ],
        );

      case ImportStep.input:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your Nostr private key (nsec or hex format).'),
            const SizedBox(height: DiogelSpacing.space4),
            TextField(
              controller: _keyController,
              decoration: InputDecoration(
                labelText: 'Private Key',
                hintText: 'nsec1... or 64 hex characters',
                border: const OutlineInputBorder(),
                errorText: _error != null ? '' : null, // Highlight field on error
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              obscureText: _obscureKey,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !_isLoading,
              autofocus: true,
            ),
            const SizedBox(height: DiogelSpacing.space4),
            const Text('Optional: Give this identity a display name.'),
            const SizedBox(height: DiogelSpacing.space2),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g. My Main Account',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
          ],
        );
      
      case ImportStep.confirming:
        return const Column(
          children: [
            Text('Are you sure you want to import this identity?'),
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    if (_isLoading) return [];

    switch (_currentStep) {
      case ImportStep.warning:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _onContinueFromWarning,
            child: const Text('I Understand'),
          ),
        ];

      case ImportStep.input:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_keyController.text.trim().isEmpty) {
                setState(() => _error = 'Private key is required');
                return;
              }
              setState(() {
                _currentStep = ImportStep.confirming;
                _error = null;
              });
            },
            child: const Text('Continue'),
          ),
        ];

      case ImportStep.confirming:
        return [
          TextButton(
            onPressed: () => setState(() => _currentStep = ImportStep.input),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _importIdentity,
            child: const Text('Confirm & Import'),
          ),
        ];
    }
  }
}
