import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/unlock/presentation/unlock_vault_screen.dart';
import '../features/vault/presentation/setup_vault_screen.dart';
import '../features/navigation/presentation/main_navigation_screen.dart';
import '../features/nip55/application/nip55_controller.dart';
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
  bool _inBackground = false;

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

    final delayMinutes = vaultControllerState.backgroundLockDelayMinutes;
    final nativeSync = ref.read(nip55NativeSyncProvider);

    // A NIP-55 approval flow intentionally bounces between another app,
    // Symudol's bridge Activity, and Flutter. Treat that as active work, not
    // ordinary backgrounding, otherwise an "immediate" background-lock setting
    // can lock the vault halfway through a signing request. The deferral is
    // bounded: a review times out, and once the request settles the lock is
    // scheduled again (_handleNip55Changed). The native key gets a deadline
    // covering both, in case the engine goes before then (#9).
    if (ref.read(nip55ControllerProvider).hasPendingExternalRequest) {
      if (kDebugMode) {
        dev.log('Deferring background lock while NIP-55 request is active');
      }
      if (delayMinutes >= 0) {
        final nip55 = ref.read(nip55ControllerProvider.notifier);
        final expiresAt = nip55.pendingReviewExpiresAt;
        final reviewLeft = expiresAt == null
            ? nip55.reviewTimeout
            : expiresAt.difference(DateTime.now());
        unawaited(
          nativeSync.setLockDeadline(
            (reviewLeft.isNegative ? Duration.zero : reviewLeft) +
                Duration(minutes: delayMinutes),
          ),
        );
      }
      return;
    }

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

    unawaited(nativeSync.setLockDeadline(Duration(minutes: delayMinutes)));
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

  /// A NIP-55 request settled (or its review timed out) while in the
  /// background: the deferred background lock applies now.
  void _handleNip55Changed(Nip55State? previous, Nip55State next) {
    if (_inBackground &&
        previous?.hasPendingExternalRequest == true &&
        !next.hasPendingExternalRequest) {
      _scheduleBackgroundLock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      dev.log('App lifecycle state changed: $state');
    }

    if (state == AppLifecycleState.detached) {
      if (kDebugMode) {
        dev.log('App is detaching: locking the vault');
      }
      _cancelLockTimers();
      // Without the engine nothing would lock later; locking also clears the
      // native key. MainActivity.onDestroy clears it too, as the guarantee (#9).
      if (ref.read(vaultControllerProvider).vaultState is VaultUnlocked) {
        ref.read(vaultControllerProvider.notifier).lock();
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _inBackground = true;
      _scheduleBackgroundLock();
    } else if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      _inBackground = false;
      _backgroundLockTimer?.cancel();
      unawaited(ref.read(nip55NativeSyncProvider).clearLockDeadline());
      // Force reset on resume regardless of throttle
      _lastInactivityReset = DateTime.fromMillisecondsSinceEpoch(0);
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    dev.log('DiogelApp build', name: 'Diogel');
    ref.listen(vaultControllerProvider, _handleVaultControllerChanged);
    ref.listen(nip55ControllerProvider, _handleNip55Changed);

    final controllerState = ref.watch(vaultControllerProvider);
    final vaultState = controllerState.vaultState;
    final isLoading = controllerState.isLoading;

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: MaterialApp(
        title: 'Symudol',
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
