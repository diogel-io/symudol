import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_failure.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:symudol/features/vault/presentation/vault_failure_messages.dart';
import '../../../theme/tokens.dart';
import 'pin_lockout_countdown.dart';
import '../../settings/presentation/widgets/wipe_vault_dialog.dart';
import 'widgets/forgot_pin_dialog.dart';
import 'widgets/pin_button.dart';

class UnlockVaultScreen extends ConsumerStatefulWidget {
  const UnlockVaultScreen({super.key});

  @override
  ConsumerState<UnlockVaultScreen> createState() => _UnlockVaultScreenState();
}

class _UnlockVaultScreenState extends ConsumerState<UnlockVaultScreen>
    with WidgetsBindingObserver {
  String _pin = '';

  // Biometric unlock prompts once by itself when the screen opens (#23).
  bool _biometricPrompted = false;
  bool _biometricInProgress = false;

  // The PIN lockout countdown (#16).
  late final PinLockoutCountdown _countdown = PinLockoutCountdown(
    onTick: () {
      if (mounted) setState(() {});
    },
    onEnd: () {
      if (!mounted) return;
      if (ref.read(vaultControllerProvider).failure is VaultLockedOutFailure) {
        ref.read(vaultControllerProvider.notifier).clearFailure();
      }
    },
  );

  Duration get _lockoutLeft => _countdown.left;

  bool get _isLockedOut => _countdown.isActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLockout(ref.read(vaultControllerProvider).lockoutRemaining);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptOnce());
  }

  /// Shows the biometric prompt once, while Symudol is in front: a prompt
  /// started in the background is cancelled by Android.
  void _promptOnce() {
    if (!mounted || _biometricPrompted) return;
    if (!ref.read(vaultControllerProvider).biometricUnlock.canUnlock) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _biometricPrompted = true;
    _unlockWithBiometric();
  }

  Future<void> _unlockWithBiometric() async {
    if (_biometricInProgress) return;
    _biometricInProgress = true;
    try {
      await ref.read(vaultControllerProvider.notifier).unlockWithBiometric();
    } finally {
      _biometricInProgress = false;
    }
    if (!mounted) return;
    // A biometric unlock clears the PIN lockout (#23).
    setState(() {
      _pin = '';
      _startLockout(ref.read(vaultControllerProvider).lockoutRemaining);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdown.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Stopwatch stops while the phone sleeps; the service's clock does
    // not, so take the time left from it again.
    if (state == AppLifecycleState.resumed && _isLockedOut) {
      ref.read(vaultControllerProvider.notifier).refreshLockout();
    }
    if (state == AppLifecycleState.resumed) {
      // Re-read before prompting: a fingerprint may have been added meanwhile.
      ref
          .read(vaultControllerProvider.notifier)
          .refreshBiometricUnlock()
          .then((_) => _promptOnce());
    }
  }

  void _startLockout(Duration remaining) => _countdown.start(remaining);

  Future<void> _unlockVault() async {
    if (_isLockedOut) return;
    final notifier = ref.read(vaultControllerProvider.notifier);
    await notifier.unlock(_pin);

    if (!mounted) return;

    final state = ref.read(vaultControllerProvider);
    if (state.failure != null) {
      setState(() {
        _pin = '';
        _startLockout(state.lockoutRemaining);
      });
    }
  }

  void _onNumberPressed(String number) {
    if (_isLockedOut) return;
    if (_pin.length < 6) {
      setState(() {
        _pin += number;
      });
      if (_pin.length == 6) {
        _unlockVault();
      }
    }
  }

  Future<void> _forgotPin() async {
    final erase = await showDialog<bool>(
      context: context,
      builder: (_) => const ForgotPinDialog(),
    );
    if (erase != true || !mounted) return;
    await confirmAndWipeVault(context, ref);
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
    // The lockout can also arrive after this screen opened, once the vault
    // state has been read.
    ref.listen<VaultControllerState>(vaultControllerProvider, (previous, next) {
      if (previous?.lockoutRemaining != next.lockoutRemaining) {
        setState(() => _startLockout(next.lockoutRemaining));
      }
    });
    final lockedOut = _isLockedOut;
    final biometric = controllerState.biometricUnlock;
    final wipeWarning = wipeWarningMessage(
      failedAttempts: controllerState.failedUnlockAttempts,
      wipeAfterFailures: controllerState.wipeAfterFailures,
    );

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
                  if (lockedOut) ...[
                    const SizedBox(height: DiogelSpacing.space2),
                    Text(
                      lockoutMessage(_lockoutLeft),
                      key: const Key('unlockLockoutMessage'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      formatLockoutCountdown(_lockoutLeft),
                      key: const Key('unlockLockoutCountdown'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ] else if (failure != null) ...[
                    const SizedBox(height: DiogelSpacing.space2),
                    Text(
                      vaultFailureMessage(failure),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (biometric.enabledButUnavailable && failure == null) ...[
                    const SizedBox(height: DiogelSpacing.space2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DiogelSpacing.space6,
                      ),
                      child: Text(
                        biometricUnavailableMessage,
                        key: const Key('unlockBiometricUnavailable'),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: DiogelColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else if (biometric.enabled &&
                      biometric.pinRequired &&
                      failure == null) ...[
                    const SizedBox(height: DiogelSpacing.space2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DiogelSpacing.space6,
                      ),
                      child: Text(
                        biometricPinRequiredMessage,
                        key: const Key('unlockBiometricPinRequired'),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: DiogelColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (wipeWarning != null) ...[
                    const SizedBox(height: DiogelSpacing.space2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DiogelSpacing.space6,
                      ),
                      child: Text(
                        wipeWarning,
                        key: const Key('unlockWipeWarning'),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: DiogelColors.stateWarning),
                        textAlign: TextAlign.center,
                      ),
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
                        onPressed: lockedOut
                            ? null
                            : () => _onNumberPressed(number),
                      ),
                    ),
                    // Also during a PIN lockout: a fingerprint proves the
                    // owner (#23).
                    PinButtonIcon(
                      Icons.fingerprint,
                      key: const Key('biometricUnlockButton'),
                      semanticLabel: 'Unlock with fingerprint',
                      onPressed:
                          biometric.canUnlock && !controllerState.isLoading
                          ? _unlockWithBiometric
                          : null,
                    ),
                    PinButton(
                      '0',
                      onPressed: lockedOut ? null : () => _onNumberPressed('0'),
                    ),
                    PinButtonIcon(
                      Icons.backspace,
                      onPressed: lockedOut ? null : _onBackspace,
                    ),
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
                        onPressed: _pin.length == 6 && !lockedOut
                            ? _unlockVault
                            : null,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Vault'),
                      ),
                    ),
                    // Also during a lockout: someone who can't remember the
                    // PIN may well be locked out (#22).
                    TextButton(
                      key: const Key('forgotPinButton'),
                      onPressed: _forgotPin,
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

