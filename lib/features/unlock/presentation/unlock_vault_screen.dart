import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:symudol/features/vault/presentation/vault_failure_messages.dart';
import '../../../theme/tokens.dart';
import 'widgets/pin_button.dart';

class UnlockVaultScreen extends ConsumerStatefulWidget {
  const UnlockVaultScreen({super.key});

  @override
  ConsumerState<UnlockVaultScreen> createState() => _UnlockVaultScreenState();
}

class _UnlockVaultScreenState extends ConsumerState<UnlockVaultScreen> {
  String _pin = '';

  Future<void> _unlockVault() async {
    final notifier = ref.read(vaultControllerProvider.notifier);
    await notifier.unlock(_pin);

    if (!mounted) return;

    final state = ref.read(vaultControllerProvider);
    if (state.failure != null) {
      setState(() {
        _pin = '';
      });
    }
  }

  void _onNumberPressed(String number) {
    if (_pin.length < 6) {
      setState(() {
        _pin += number;
      });
      if (_pin.length == 6) {
        _unlockVault();
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultStateProvider);
    final controllerState = ref.watch(vaultControllerProvider);
    final nip55State = ref.watch(nip55ControllerProvider);
    final failure = controllerState.failure;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/symudol.png',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: DiogelSpacing.space3),
            Text(
              'Symudol',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DiogelSpacing.space4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: DiogelColors.surfaceContainerHigh,
              child: const Icon(
                Icons.person,
                size: 20,
                color: DiogelColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: DiogelSpacing.space12),
              Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: DiogelColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(DiogelRadius.large),
                      border: Border.all(color: DiogelColors.borderSubtle),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(DiogelSpacing.space6),
                      child: Image.asset(
                        'assets/images/symudol.png',
                      ),
                    ),
                  ),
                  const SizedBox(height: DiogelSpacing.space6),
                  Text(
                    vaultState is SessionExpired
                        ? 'Session Expired'
                        : 'Unlock Vault',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (nip55State.isWaitingForUnlock) ...[
                    const SizedBox(height: DiogelSpacing.space3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DiogelSpacing.space6,
                      ),
                      child: Text(
                        'An external Android app is waiting for a NIP-55 signing decision. Unlock to review it, or cancel the request.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DiogelColors.stateWarning,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => ref
                          .read(nip55ControllerProvider.notifier)
                          .cancelPendingExternalRequest(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel external request'),
                    ),
                  ],
                  if (failure != null) ...[
                    const SizedBox(height: DiogelSpacing.space2),
                    Text(
                      vaultFailureMessage(failure),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: DiogelSpacing.space1),
                  Text(
                    vaultState is SessionExpired
                        ? 'Your session has timed out due to inactivity'
                        : 'Enter security PIN to continue',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DiogelColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DiogelSpacing.space12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: DiogelSpacing.space3,
                    ),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? DiogelColors.actionPrimary
                          : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? DiogelColors.actionPrimary
                            : DiogelColors.borderStrong,
                        width: 2,
                      ),
                      boxShadow: isFilled
                          ? [
                              BoxShadow(
                                color: DiogelColors.actionPrimary.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: DiogelSpacing.space12),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DiogelSpacing.space8,
                ),
                child: GridView.count(
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
                    const PinButtonIcon(Icons.fingerprint, onPressed: null),
                    PinButton('0', onPressed: () => _onNumberPressed('0')),
                    PinButtonIcon(Icons.backspace, onPressed: _onBackspace),
                  ],
                ),
              ),
              const SizedBox(height: DiogelSpacing.space8),
              Padding(
                padding: const EdgeInsets.all(DiogelSpacing.space4),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _pin.length == 6 ? _unlockVault : null,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Vault'),
                      ),
                    ),
                    TextButton(
                      onPressed: _noop,
                      child: const Text(
                        'Forgot PIN?',
                        style: TextStyle(color: DiogelColors.actionPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop() {}
