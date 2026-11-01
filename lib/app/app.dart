import 'dart:async';
import 'diogel_log.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/unlock/presentation/unlock_vault_screen.dart';
import '../features/vault/presentation/setup_vault_screen.dart';
import '../features/navigation/presentation/main_navigation_screen.dart';
import '../features/nip55/application/nip55_controller.dart';
import '../features/nip55/application/nip55_providers.dart';
import '../features/nip46/application/nip46_providers.dart';
import '../features/vault/application/vault_providers.dart';
import '../features/vault/application/vault_controller.dart';
import '../features/vault/domain/vault_state.dart';
import 'system_picker.dart';
import '../theme/app_theme.dart';

class DiogelApp extends ConsumerStatefulWidget {
  const DiogelApp({super.key});

  @override
  ConsumerState<DiogelApp> createState() => DiogelAppState();
}

class DiogelAppState extends ConsumerState<DiogelApp>
    with WidgetsBindingObserver {
  /// The app's only navigator: screens pushed from Settings or Accounts, and
  /// dialogs, sit above `home` on it.
  final _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _inactivityTimer;
  Timer? _backgroundLockTimer;

  /// When the background lock is due. Android can freeze or delay Symudol
  /// in the background, so the timer may not have fired by the time it
  /// resumes; resuming checks this too (#128). Wall time, which keeps
  /// counting while the phone sleeps.
  DateTime? _backgroundLockDueAt;

  /// An overdue background lock is under way: the native deadline stays
  /// until the vault has locked (#128).
  bool _overdueLockPending = false;

  /// Locks at the usual delay plus [pickingLockGrace] while an image pick is
  /// still open (#43).
  Timer? _pickingGraceTimer;

  /// The background lock delay ran out while an image was being picked, so
  /// the lock applies as soon as the pick ends (#43).
  bool _lockDueAfterPick = false;

  /// When the lock was deferred for an image pick, so a pick that ends
  /// early can give the native key the rest of the usual delay (#43).
  DateTime? _pickDeferredAt;
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
    _pickingGraceTimer?.cancel();
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
        diogelLog('Resetting inactivity timer: $timeoutMinutes minutes');
        _inactivityTimer = Timer(Duration(minutes: timeoutMinutes), () {
          if (!mounted) return;
          diogelLog('Inactivity timer expired');
          ref.read(vaultControllerProvider.notifier).expireSession();
        });
      }
    }
  }

  void _scheduleBackgroundLock() {
    _backgroundLockTimer?.cancel();
    _backgroundLockDueAt = null;
    _pickingGraceTimer?.cancel();
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
      diogelLog('Deferring background lock while NIP-55 request is active');
      if (delayMinutes >= 0) {
        final nip55 = ref.read(nip55ControllerProvider.notifier);
        final expiresAt = nip55.pendingReviewExpiresAt;
        final reviewLeft = expiresAt == null
            ? nip55.reviewTimeout
            : expiresAt.difference(DateTime.now());
        final deadline =
            (reviewLeft.isNegative ? Duration.zero : reviewLeft) +
            Duration(minutes: delayMinutes);
        _backgroundLockDueAt = clock.now().add(deadline);
        unawaited(nativeSync.setLockDeadline(deadline));
      }
      return;
    }

    diogelLog('Scheduling background lock: $delayMinutes minutes');
    if (delayMinutes == -1) {
      return;
    }

    // The photo picker or camera the user opened from Edit profile sends
    // Symudol to the background; locking then would close Edit profile and
    // lose the edit (#43). The usual delay still runs from now: if it ends
    // during the pick, the lock applies when the pick ends. A pick still
    // open [pickingLockGrace] after the delay locks anyway, and the native
    // key gets that deadline.
    if (ref.read(systemPickerOpenProvider)) {
      final delay = Duration(minutes: delayMinutes);
      diogelLog('Deferring background lock while an image is picked');
      _lockDueAfterPick = false;
      _pickDeferredAt = clock.now();
      _backgroundLockDueAt = clock.now().add(delay + pickingLockGrace);
      unawaited(nativeSync.setLockDeadline(delay + pickingLockGrace));
      _backgroundLockTimer = Timer(delay, () {
        if (!mounted) return;
        if (ref.read(systemPickerOpenProvider)) {
          _lockDueAfterPick = true;
        } else {
          _lockInBackground(delayMinutes);
        }
      });
      _pickingGraceTimer = Timer(delay + pickingLockGrace, () {
        if (!mounted) return;
        diogelLog('Image pick outlasted the background lock');
        ref.read(vaultControllerProvider.notifier).expireSession();
      });
      return;
    }

    if (delayMinutes == 0) {
      diogelLog('Background lock delay is 0, locking immediately');
      ref.read(vaultControllerProvider.notifier).lock();
      return;
    }

    unawaited(nativeSync.setLockDeadline(Duration(minutes: delayMinutes)));
    _backgroundLockDueAt = clock.now().add(Duration(minutes: delayMinutes));
    _backgroundLockTimer = Timer(Duration(minutes: delayMinutes), () {
      if (!mounted) return;
      diogelLog('Background lock timer expired');
      ref.read(vaultControllerProvider.notifier).expireSession();
    });
  }

  /// How much longer than the background lock delay the vault stays
  /// unlocked while the user picks an image (#43).
  static const Duration pickingLockGrace = Duration(minutes: 5);

  /// Applies the background lock: a zero delay locks, a timed one expires
  /// the session, as when no pick deferred it.
  void _lockInBackground(int delayMinutes) {
    final vault = ref.read(vaultControllerProvider.notifier);
    if (delayMinutes == 0) {
      vault.lock();
    } else {
      vault.expireSession();
    }
  }

  /// Locks on resume if the background lock fell due while its timer did
  /// not fire (#128).
  ///
  /// The lock reaches the native key only after a few awaits, so the native
  /// key is cleared here first.
  void _applyOverdueBackgroundLock() {
    final dueAt = _backgroundLockDueAt;
    _backgroundLockDueAt = null;
    if (dueAt == null || clock.now().isBefore(dueAt)) return;
    final vaultControllerState = ref.read(vaultControllerProvider);
    if (vaultControllerState.vaultState is! VaultUnlocked) return;
    final delayMinutes = vaultControllerState.backgroundLockDelayMinutes;
    if (delayMinutes < 0) return;
    diogelLog('Background lock fell due while in the background');
    _overdueLockPending = true;
    unawaited(ref.read(nip55NativeSyncProvider).clearActiveKey());
    _lockInBackground(delayMinutes);
  }

  void _cancelLockTimers() {
    _inactivityTimer?.cancel();
    _backgroundLockTimer?.cancel();
    _backgroundLockDueAt = null;
    _overdueLockPending = false;
    _pickingGraceTimer?.cancel();
    _lockDueAfterPick = false;
  }

  void _handleVaultControllerChanged(
    VaultControllerState? previous,
    VaultControllerState next,
  ) {
    final previousWasUnlocked = previous?.vaultState is VaultUnlocked;
    final isUnlocked = next.vaultState is VaultUnlocked;

    // The vault was wiped (#20): Trusted apps must not show stale grants.
    if (next.vaultState is NoVault &&
        previous != null &&
        previous.vaultState is! NoVault) {
      ref.invalidate(nip55PermissionControllerProvider);
    }

    if (!isUnlocked) {
      _cancelLockTimers();
      // Swapping `home` only replaces the root route: anything pushed while
      // unlocked would stay above the unlock screen (#123). A lock overrides
      // PopScope (popUntil skips it), so unsaved edits are dropped.
      if (previousWasUnlocked) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
      return;
    }

    // Handle NIP-55 resume after unlock
    final nip55State = ref.read(nip55ControllerProvider);
    if (nip55State.isWaitingForUnlock) {
      diogelLog('Vault unlocked while NIP-55 request is pending. Resuming...');
      ref.read(nip55ControllerProvider.notifier).resumePendingAfterUnlock();
    }

    final timeoutChanged =
        previous != null &&
        previous.inactivityTimeoutMinutes != next.inactivityTimeoutMinutes;

    if (!previousWasUnlocked || timeoutChanged) {
      _resetInactivityTimer();
    }
  }

  /// An image pick ended while still in the background: the lock applies
  /// now if the delay already ran out, or when its timer ends (#43).
  void _handlePickingChanged(bool? previous, bool next) {
    if (!_inBackground || previous != true || next) return;
    _pickingGraceTimer?.cancel();
    final delayMinutes = ref
        .read(vaultControllerProvider)
        .backgroundLockDelayMinutes;
    if (_lockDueAfterPick) {
      _lockDueAfterPick = false;
      _lockInBackground(delayMinutes);
      return;
    }
    // The grace no longer applies: the native key, and a resume after a
    // freeze (#128), get only what is left of the usual delay, as the Dart
    // timer does.
    final since = _pickDeferredAt;
    if (since != null && delayMinutes >= 0) {
      _backgroundLockDueAt = since.add(Duration(minutes: delayMinutes));
    }
    if (since != null && delayMinutes > 0) {
      final left =
          Duration(minutes: delayMinutes) - clock.now().difference(since);
      unawaited(
        ref
            .read(nip55NativeSyncProvider)
            .setLockDeadline(left.isNegative ? Duration.zero : left),
      );
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
    diogelLog('App lifecycle state changed: $state');

    if (state == AppLifecycleState.detached) {
      diogelLog('App is detaching: locking the vault');
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
      // Leaving passes through hidden then paused, and coming back from
      // paused through hidden again: only the first starts the delay, or a
      // return would restart it just before resuming checks it (#128).
      if (_inBackground) return;
      _inBackground = true;
      _scheduleBackgroundLock();
    } else if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      _inBackground = false;
      _applyOverdueBackgroundLock();
      _backgroundLockTimer?.cancel();
      _pickingGraceTimer?.cancel();
      _lockDueAfterPick = false;
      // An overdue lock keeps the native deadline, which has passed or
      // soon will; the next unlock replaces it with the key.
      if (!_overdueLockPending) {
        unawaited(ref.read(nip55NativeSyncProvider).clearLockDeadline());
      }
      // A fingerprint may have been added in Android settings meanwhile, so
      // Settings and the unlock screen show what the phone can do now (#23).
      unawaited(
        ref.read(vaultControllerProvider.notifier).refreshBiometricUnlock(),
      );
      // Relays dropped while in the background reconnect now rather than
      // after their back-off (#30). Only if NIP-46 has started at all.
      if (state == AppLifecycleState.resumed &&
          ref.exists(nip46RelayServiceProvider)) {
        unawaited(ref.read(nip46RelayServiceProvider).reconnectAll());
      }
      // Force reset on resume regardless of throttle
      _lastInactivityReset = DateTime.fromMillisecondsSinceEpoch(0);
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    diogelLog('App build');
    ref.listen(vaultControllerProvider, _handleVaultControllerChanged);
    ref.listen(nip55ControllerProvider, _handleNip55Changed);
    ref.listen(systemPickerOpenProvider, _handlePickingChanged);

    final controllerState = ref.watch(vaultControllerProvider);
    final vaultState = controllerState.vaultState;
    final isLoading = controllerState.isLoading;

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: MaterialApp(
        navigatorKey: _navigatorKey,
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
