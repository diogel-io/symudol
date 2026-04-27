import 'package:flutter/material.dart';

import '../../../navigation/presentation/main_navigation_screen.dart';
import '../../../theme/tokens.dart';
import 'widgets/pin_button.dart';

class UnlockVaultScreen extends StatefulWidget {
  const UnlockVaultScreen({super.key});

  @override
  State<UnlockVaultScreen> createState() => _UnlockVaultScreenState();
}

class _UnlockVaultScreenState extends State<UnlockVaultScreen> {
  String _pin = '';

  void _navigateToMainNavigation() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
    );
  }

  void _onNumberPressed(String number) {
    if (_pin.length < 6) {
      setState(() {
        _pin += number;
      });
      if (_pin.length == 6) {
        _navigateToMainNavigation();
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.shield, color: DiogelColors.actionPrimary),
            const SizedBox(width: DiogelSpacing.space3),
            Text(
              'Android Diogel',
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
        child: Column(
          children: [
            const Spacer(),
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
                  child: const Icon(
                    Icons.shield,
                    size: 48,
                    color: DiogelColors.actionPrimary,
                  ),
                ),
                const SizedBox(height: DiogelSpacing.space6),
                Text(
                  'Unlock Vault',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: DiogelSpacing.space1),
                Text(
                  'Enter security PIN to continue',
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
                    color:
                        isFilled
                            ? DiogelColors.actionPrimary
                            : Colors.transparent,
                    border: Border.all(
                      color:
                          isFilled
                              ? DiogelColors.actionPrimary
                              : DiogelColors.borderStrong,
                      width: 2,
                    ),
                    boxShadow:
                        isFilled
                            ? [
                              BoxShadow(
                                color: DiogelColors.actionPrimary.withOpacity(
                                  0.4,
                                ),
                                blurRadius: 8,
                              ),
                            ]
                            : null,
                  ),
                );
              }),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DiogelSpacing.space8,
              ),
              child: GridView.count(
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
                  const PinButtonIcon(Icons.fingerprint, onPressed: _noop),
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
                      onPressed: _pin.length == 6 ? _navigateToMainNavigation : null,
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
    );
  }
}

void _noop() {}
