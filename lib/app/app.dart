import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/unlock/presentation/unlock_vault_screen.dart';
import '../features/vault/presentation/setup_vault_screen.dart';
import '../features/navigation/presentation/main_navigation_screen.dart';
import '../features/nip55/application/nip55_providers.dart';
import '../features/vault/application/vault_providers.dart';
import '../features/vault/application/vault_controller.dart';
import '../features/vault/domain/vault_state.dart';
import '../theme/app_theme.dart';

class DiogelApp extends ConsumerStatefulWidget {
  const DiogelApp({super.key});

  @override
  ConsumerState<DiogelApp> createState() => DiogelAppState();
}

class DiogelAppState extends ConsumerState<DiogelApp>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  Timer? _backgroundLockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nip55ControllerProvider.notifier).consumePendingNativeIntent();
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _backgroundLockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @visibleForTesting
  void resetInactivityTimerThrottled() {
    _lastInactivityReset = DateTime.fromMillisecondsSinceEpoch(0);
    _resetInactivityTimer();
  }

  DateTime _lastInactivityReset = DateTime.fromMillisecondsSinceEpoch(0);

  void _resetInactivityTimer() {
    final now = DateTime.now();
    if (now.difference(_lastInactivityReset) < const Duration(seconds: 5)) {
      return;
    }
    _lastInactivityReset = now;

    _inactivityTimer?.cancel();
    final vaultControllerState = ref.read(vaultControllerProvider);
    if (vaultControllerState.vaultState is VaultUnlocked) {
      final timeoutMinutes = vaultControllerState.inactivityTimeoutMinutes;
      if (timeoutMinutes > 0) {
        if (kDebugMode) {
          dev.log('Resetting inactivity timer: $timeoutMinutes minutes');
        }
        _inactivityTimer = Timer(Duration(minutes: timeoutMinutes), () {
          if (!mounted) return;
          if (kDebugMode) {
            dev.log('Inactivity timer expired');
          }
          ref.read(vaultControllerProvider.notifier).expireSession();
        });
      }
    }
  }

  void _scheduleBackgroundLock() {
    _backgroundLockTimer?.cancel();
    _inactivityTimer?.cancel();

    final vaultControllerState = ref.read(vaultControllerProvider);
    if (vaultControllerState.vaultState is! VaultUnlocked) {
      return;
    }

    // A NIP-55 approval flow intentionally bounces between another app,
    // Diogel's bridge Activity, and Flutter. Treat that as active work, not
    // ordinary backgrounding, otherwise an "immediate" background-lock setting
    // can lock the vault halfway through a signing request.
    if (ref.read(nip55ControllerProvider).hasPendingExternalRequest) {
      if (kDebugMode) {
        dev.log('Skipping background lock while NIP-55 request is active');
      }
      return;
    }

    final delayMinutes = vaultControllerState.backgroundLockDelayMinutes;
    if (kDebugMode) {
      dev.log('Scheduling background lock: $delayMinutes minutes');
    }
    if (delayMinutes == -1) {
      return;
    }

    if (delayMinutes == 0) {
      if (kDebugMode) {
        dev.log('Background lock delay is 0, locking immediately');
      }
      ref.read(vaultControllerProvider.notifier).lock();
      return;
    }

    _backgroundLockTimer = Timer(Duration(minutes: delayMinutes), () {
      if (!mounted) return;
      if (kDebugMode) {
        dev.log('Background lock timer expired');
      }
      ref.read(vaultControllerProvider.notifier).expireSession();
    });
  }

  void _cancelLockTimers() {
    _inactivityTimer?.cancel();
    _backgroundLockTimer?.cancel();
  }

  void _handleVaultControllerChanged(
    VaultControllerState? previous,
    VaultControllerState next,
  ) {
    final previousWasUnlocked = previous?.vaultState is VaultUnlocked;
    final isUnlocked = next.vaultState is VaultUnlocked;

    if (!isUnlocked) {
      _cancelLockTimers();
      return;
    }

    // Handle NIP-55 resume after unlock
    final nip55State = ref.read(nip55ControllerProvider);
    if (nip55State.isWaitingForUnlock) {
      if (kDebugMode) {
        dev.log('Vault unlocked while NIP-55 request is pending. Resuming...');
      }
      ref.read(nip55ControllerProvider.notifier).resumePendingAfterUnlock();
    }

    final timeoutChanged =
        previous != null &&
        previous.inactivityTimeoutMinutes != next.inactivityTimeoutMinutes;

    if (!previousWasUnlocked || timeoutChanged) {
      _resetInactivityTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      dev.log('App lifecycle state changed: $state');
    }

    if (state == AppLifecycleState.detached) {
      if (kDebugMode) {
        dev.log('App is detaching, cleaning up timers');
      }
      _cancelLockTimers();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _scheduleBackgroundLock();
    } else if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      _backgroundLockTimer?.cancel();
      // Force reset on resume regardless of throttle
      _lastInactivityReset = DateTime.fromMillisecondsSinceEpoch(0);
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    dev.log('DiogelApp build', name: 'Diogel');
    ref.listen(vaultControllerProvider, _handleVaultControllerChanged);

    final controllerState = ref.watch(vaultControllerProvider);
    final vaultState = controllerState.vaultState;
    final isLoading = controllerState.isLoading;

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: MaterialApp(
        title: 'Android Diogel',
        theme: DiogelTheme.darkTheme,
        home: isLoading && vaultState is NoVault
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _getHome(vaultState),
      ),
    );
  }

  Widget _getHome(VaultState state) {
    return switch (state) {
      NoVault() => const SetupVaultScreen(),
      VaultLocked() || SessionExpired() => const UnlockVaultScreen(),
      VaultUnlocked() => const MainNavigationScreen(),
    };
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const DiogelApp();
  }
}
