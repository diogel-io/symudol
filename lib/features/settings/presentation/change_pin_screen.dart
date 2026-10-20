import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../unlock/presentation/pin_lockout_countdown.dart';
import '../../unlock/presentation/widgets/pin_button.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_failure.dart';
import '../../vault/domain/vault_state.dart';
import '../../vault/presentation/vault_failure_messages.dart';

enum _Step { current, newPin, confirm }

/// Settings → Change PIN (#21): the current PIN, then the new PIN twice.
///
/// Pops `true` once the PIN is changed. Closes itself if the vault locks or
/// is erased meanwhile, since the app then shows the unlock or setup screen.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  _Step _step = _Step.current;
  String _current = '';
  String _new = '';
  String _entry = '';
  String? _error;
  bool _working = false;

  late final PinLockoutCountdown _countdown = PinLockoutCountdown(
    onTick: () {
      if (mounted) setState(() {});
    },
    onEnd: () {
      if (mounted) setState(() => _error = null);
    },
  );

  @override
  void initState() {
    super.initState();
    _countdown.start(ref.read(vaultControllerProvider).lockoutRemaining);
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  bool get _padEnabled =>
      !_working && !(_step == _Step.current && _countdown.isActive);

  String get _title => switch (_step) {
    _Step.current => 'Enter your current PIN',
    _Step.newPin => 'Enter a new PIN',
    _Step.confirm => 'Confirm the new PIN',
  };

  void _onNumberPressed(String digit) {
    if (!_padEnabled || _entry.length >= 6) return;
    setState(() {
      _error = null;
      _entry += digit;
    });
    if (_entry.length == 6) _onEntryComplete();
  }

  void _onBackspace() {
    if (!_padEnabled || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _onEntryComplete() {
    switch (_step) {
      case _Step.current:
        setState(() {
          _current = _entry;
          _entry = '';
          _step = _Step.newPin;
        });
      case _Step.newPin:
        if (_entry == _current) {
          setState(() {
            _entry = '';
            _error = 'Choose a different PIN.';
          });
          return;
        }
        setState(() {
          _new = _entry;
          _entry = '';
          _step = _Step.confirm;
        });
      case _Step.confirm:
        if (_entry != _new) {
          setState(() {
            _entry = '';
            _new = '';
            _step = _Step.newPin;
            _error = 'The PINs do not match. Enter the new PIN again.';
          });
          return;
        }
        _change();
    }
  }

  Future<void> _change() async {
    setState(() => _working = true);
    final failure = await ref
        .read(vaultControllerProvider.notifier)
        .changePin(_current, _new);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    // A wrong current PIN (or a lockout) starts again from the current PIN.
    final state = ref.read(vaultControllerProvider);
    _countdown.start(state.lockoutRemaining);
    setState(() {
      _working = false;
      _current = '';
      _new = '';
      _entry = '';
      _step = _Step.current;
      _error = failure is InvalidPinFailure
          ? 'That is not your current PIN.'
          : vaultFailureMessage(failure);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VaultState>(vaultStateProvider, (previous, next) {
      if (next is! VaultUnlocked && mounted) Navigator.of(context).maybePop();
    });
    final controllerState = ref.watch(vaultControllerProvider);
    final lockedOut = _step == _Step.current && _countdown.isActive;
    final warning = _step == _Step.current
        ? wipeWarningMessage(
            failedAttempts: controllerState.failedUnlockAttempts,
            wipeAfterFailures: controllerState.wipeAfterFailures,
          )
        : null;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DiogelSpacing.space6),
          child: Column(
            children: [
              const SizedBox(height: DiogelSpacing.space8),
              Text(
                _title,
                key: const Key('changePinTitle'),
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: DiogelSpacing.space4),
              _PinDots(filled: _entry.length),
              if (lockedOut) ...[
                const SizedBox(height: DiogelSpacing.space4),
                Text(
                  lockoutMessage(_countdown.left),
                  key: const Key('changePinLockoutMessage'),
                  style: const TextStyle(color: DiogelColors.stateError),
                  textAlign: TextAlign.center,
                ),
                Text(
                  formatLockoutCountdown(_countdown.left),
                  style: textTheme.titleLarge,
                ),
              ] else if (_error != null) ...[
                const SizedBox(height: DiogelSpacing.space4),
                Text(
                  _error!,
                  key: const Key('changePinError'),
                  style: const TextStyle(color: DiogelColors.stateError),
                  textAlign: TextAlign.center,
                ),
              ],
              if (warning != null) ...[
                const SizedBox(height: DiogelSpacing.space2),
                Text(
                  warning,
                  style: textTheme.bodyMedium?.copyWith(
                    color: DiogelColors.stateWarning,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: DiogelSpacing.space8),
              if (_working) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: DiogelSpacing.space4),
                Text('Changing PIN…', style: textTheme.bodyMedium),
              ] else
                _keypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    final enabled = _padEnabled;
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: DiogelSpacing.space4,
      crossAxisSpacing: DiogelSpacing.space8,
      children: [
        for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
          PinButton(
            digit,
            onPressed: enabled ? () => _onNumberPressed(digit) : null,
          ),
        const SizedBox.shrink(),
        PinButton('0', onPressed: enabled ? () => _onNumberPressed('0') : null),
        PinButtonIcon(Icons.backspace, onPressed: enabled ? _onBackspace : null),
      ],
    );
  }
}

class _PinDots extends StatelessWidget {
  final int filled;

  const _PinDots({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('changePinDots-$filled'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space3),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? DiogelColors.actionPrimary : Colors.transparent,
            border: Border.all(
              color: isFilled
                  ? DiogelColors.actionPrimary
                  : DiogelColors.borderStrong,
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}
