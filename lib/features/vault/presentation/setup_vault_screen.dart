import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/theme/tokens.dart';
import 'package:android_diogel/features/vault/presentation/vault_failure_messages.dart';
import '../../unlock/presentation/widgets/pin_button.dart';

class SetupVaultScreen extends ConsumerStatefulWidget {
  const SetupVaultScreen({super.key});

  @override
  ConsumerState<SetupVaultScreen> createState() => _SetupVaultScreenState();
}

class _SetupVaultScreenState extends ConsumerState<SetupVaultScreen> {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String? _error;

  void _onNumberPressed(String number) {
    setState(() {
      _error = null;
      if (!_isConfirming) {
        if (_pin.length < 6) {
          _pin += number;
          if (_pin.length == 6) {
            _isConfirming = true;
          }
        }
      } else {
        if (_confirmPin.length < 6) {
          _confirmPin += number;
          if (_confirmPin.length == 6) {
            _createVault();
          }
        }
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _error = null;
      if (_isConfirming) {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        } else {
          _isConfirming = false;
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      }
    });
  }

  Future<void> _createVault() async {
    if (_pin != _confirmPin) {
      setState(() {
        _error = 'PINs do not match. Try again.';
        _pin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
      return;
    }

    await ref.read(vaultControllerProvider.notifier).createVault(_pin);
    
    if (!mounted) return;

    final controllerState = ref.read(vaultControllerProvider);
    if (controllerState.failure != null) {
      setState(() {
        _error = vaultFailureMessage(controllerState.failure!);
        _pin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(vaultControllerProvider).isLoading;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(DiogelSpacing.space6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: DiogelSpacing.space12),
                const Icon(
                  Icons.security,
                  size: 64,
                  color: DiogelColors.actionPrimary,
                ),
                const SizedBox(height: DiogelSpacing.space6),
                Text(
                  'Welcome to Diogel',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: DiogelSpacing.space4),
                Text(
                  'Private keys are stored locally using the device platform secure-storage backend. Diogel never syncs or uploads them.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: DiogelColors.textSecondary,
                      ),
                ),
                const SizedBox(height: DiogelSpacing.space8),
                _buildInfoCard(),
                const SizedBox(height: DiogelSpacing.space12),
                Text(
                  _isConfirming ? 'Confirm your PIN' : 'Create a security PIN',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: DiogelSpacing.space4),
                _buildPinDots(),
                if (_error != null) ...[
                  const SizedBox(height: DiogelSpacing.space4),
                  Text(
                    _error!,
                    style: const TextStyle(color: DiogelColors.stateError),
                  ),
                ],
                const SizedBox(height: DiogelSpacing.space8),
                if (isLoading)
                  const CircularProgressIndicator()
                else
                  _buildKeypad(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainer,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Column(
        children: [
          _buildInfoItem(
            Icons.lock_outline,
            'Local Access PIN',
            'Create a local access PIN for this app session. Stronger PIN-derived vault encryption is planned for a later hardening milestone.',
          ),
          const SizedBox(height: DiogelSpacing.space3),
          _buildInfoItem(
            Icons.cloud_off,
            'No Cloud Sync',
            'Diogel does not upload your private keys to any server.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: DiogelColors.textSecondary),
        const SizedBox(width: DiogelSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DiogelColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinDots() {
    final length = _isConfirming ? _confirmPin.length : _pin.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space2),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? DiogelColors.actionPrimary : Colors.transparent,
            border: Border.all(
              color: isFilled ? DiogelColors.actionPrimary : DiogelColors.borderStrong,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: DiogelSpacing.space4,
      crossAxisSpacing: DiogelSpacing.space8,
      children: [
        ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map(
          (number) => PinButton(
            number,
            onPressed: () => _onNumberPressed(number),
          ),
        ),
        const SizedBox.shrink(),
        PinButton('0', onPressed: () => _onNumberPressed('0')),
        PinButtonIcon(Icons.backspace, onPressed: _onBackspace),
      ],
    );
  }
}
