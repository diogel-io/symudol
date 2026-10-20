import 'package:symudol/app/diogel_log.dart';
import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_failure.dart';
import 'package:symudol/features/vault/domain/vault_service.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

class VaultControllerState {
  final VaultState vaultState;
  final List<VaultIdentity> identities;
  final VaultIdentity? activeIdentity;
  final int inactivityTimeoutMinutes;
  final int backgroundLockDelayMinutes;
  final int approvalSessionDurationMinutes;

  /// Consecutive failed PIN attempts, read while locked (#16).
  final int failedUnlockAttempts;

  /// Failed PIN attempts that erase the vault, or `null` for never.
  final int? wipeAfterFailures;

  /// The lockout left when the state was read; [Duration.zero] for none.
  final Duration lockoutRemaining;
  final bool isLoading;
  final VaultFailure? failure;

  const VaultControllerState({
    required this.vaultState,
    this.identities = const [],
    this.activeIdentity,
    this.inactivityTimeoutMinutes = 5,
    this.backgroundLockDelayMinutes = 5,
    this.approvalSessionDurationMinutes = 0,
    this.failedUnlockAttempts = 0,
    this.wipeAfterFailures,
    this.lockoutRemaining = Duration.zero,
    this.isLoading = true,
    this.failure,
  });

  VaultControllerState copyWith({
    VaultState? vaultState,
    List<VaultIdentity>? identities,
    VaultIdentity? activeIdentity,
    int? inactivityTimeoutMinutes,
    int? backgroundLockDelayMinutes,
    int? approvalSessionDurationMinutes,
    int? failedUnlockAttempts,
    int? wipeAfterFailures,
    bool clearWipeAfterFailures = false,
    Duration? lockoutRemaining,
    bool? isLoading,
    VaultFailure? failure,
    bool clearFailure = false,
    bool clearActiveIdentity = false,
  }) {
    return VaultControllerState(
      vaultState: vaultState ?? this.vaultState,
      identities: identities ?? this.identities,
      activeIdentity: clearActiveIdentity
          ? null
          : (activeIdentity ?? this.activeIdentity),
      inactivityTimeoutMinutes:
          inactivityTimeoutMinutes ?? this.inactivityTimeoutMinutes,
      backgroundLockDelayMinutes:
          backgroundLockDelayMinutes ?? this.backgroundLockDelayMinutes,
      approvalSessionDurationMinutes:
          approvalSessionDurationMinutes ?? this.approvalSessionDurationMinutes,
      failedUnlockAttempts: failedUnlockAttempts ?? this.failedUnlockAttempts,
      wipeAfterFailures: clearWipeAfterFailures
          ? null
          : (wipeAfterFailures ?? this.wipeAfterFailures),
      lockoutRemaining: lockoutRemaining ?? this.lockoutRemaining,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class VaultController extends StateNotifier<VaultControllerState> {
  final VaultService _vaultService;

  VaultController(this._vaultService)
    : super(
        const VaultControllerState(vaultState: NoVault(), isLoading: true),
      ) {
    initialize();
  }

  Future<void> initialize() async {
    diogelLog('VaultController: initializing. State: ${state.vaultState.runtimeType}');

    if (_vaultService.state is VaultUnlocked) {
      await _refreshState();
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      diogelLog('VaultController: calling _vaultService.init()');
      await _vaultService.init();
      diogelLog('VaultController: calling _refreshState()');
      await _refreshState();
      diogelLog('VaultController: initialized. State: ${state.vaultState.runtimeType}');
    } catch (e, stack) {
      diogelLog(
        'VaultController: initialization error',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _refreshState() async {
    final vaultState = _vaultService.state;
    List<VaultIdentity> identities = [];
    VaultIdentity? activeIdentity;
    int timeout = 5;
    int backgroundLockDelay = 5;
    int approvalSessionDuration = 0;
    int failedUnlockAttempts = 0;
    int? wipeAfterFailures;
    Duration lockoutRemaining = Duration.zero;

    if (vaultState is VaultUnlocked) {
      identities = await _vaultService.listIdentities();
      activeIdentity = _vaultService.activeIdentity;
      timeout = await _vaultService.getInactivityTimeout();
      backgroundLockDelay = await _vaultService.getBackgroundLockDelayMinutes();
      approvalSessionDuration = await _vaultService
          .getApprovalSessionDurationMinutes();
      wipeAfterFailures = await _vaultService.getWipeAfterFailures();
      // Change PIN checks the current PIN against the same count and
      // lockout as unlocking (#21).
      failedUnlockAttempts = await _vaultService.getFailedUnlockAttempts();
      lockoutRemaining = await _vaultService.getLockoutRemaining();
    } else if (vaultState is VaultLocked || vaultState is SessionExpired) {
      identities = [];
      activeIdentity = null;
      // In locked state we might not be able to get the timeout if it requires KEK,
      // but getInactivityTimeout is just a simple read from store for now.
      timeout = await _vaultService.getInactivityTimeout();
      backgroundLockDelay = await _vaultService.getBackgroundLockDelayMinutes();
      approvalSessionDuration = await _vaultService
          .getApprovalSessionDurationMinutes();
      // For the unlock screen's countdown and erase warning (#16).
      failedUnlockAttempts = await _vaultService.getFailedUnlockAttempts();
      wipeAfterFailures = await _vaultService.getWipeAfterFailures();
      lockoutRemaining = await _vaultService.getLockoutRemaining();
    } else if (vaultState is NoVault) {
      // Ensure everything is cleared
      identities = [];
      activeIdentity = null;
    }

    state = state.copyWith(
      vaultState: vaultState,
      identities: identities,
      activeIdentity: activeIdentity,
      clearActiveIdentity: activeIdentity == null,
      inactivityTimeoutMinutes: timeout,
      backgroundLockDelayMinutes: backgroundLockDelay,
      approvalSessionDurationMinutes: approvalSessionDuration,
      failedUnlockAttempts: failedUnlockAttempts,
      wipeAfterFailures: wipeAfterFailures,
      clearWipeAfterFailures: wipeAfterFailures == null,
      lockoutRemaining: lockoutRemaining,
    );
  }

  /// Re-reads the PIN lockout, for the unlock screen's countdown (#16).
  Future<void> refreshLockout() async {
    try {
      state = state.copyWith(
        lockoutRemaining: await _vaultService.getLockoutRemaining(),
      );
    } catch (e, stack) {
      diogelLog(
        'VaultController: could not read the lockout',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void clearFailure() {
    state = state.copyWith(clearFailure: true);
  }

  Future<void> setInactivityTimeout(int minutes) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.setInactivityTimeout(minutes);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setBackgroundLockDelayMinutes(int minutes) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.setBackgroundLockDelayMinutes(minutes);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setApprovalSessionDurationMinutes(int minutes) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.setApprovalSessionDurationMinutes(minutes);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Changes the PIN (#21). Returns the failure, if any, for the Change PIN
  /// screen; a wrong current PIN also updates the count and lockout here.
  Future<VaultFailure?> changePin(String currentPin, String newPin) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    VaultFailure? failure;
    try {
      await _vaultService.changePin(currentPin, newPin);
    } catch (e) {
      failure = _mapExceptionToFailure(e);
    }
    try {
      await _refreshState();
    } catch (e, stack) {
      diogelLog(
        'VaultController: refresh after a PIN change failed',
        error: e,
        stackTrace: stack,
      );
    }
    state = state.copyWith(isLoading: false, failure: failure);
    return failure;
  }

  Future<void> setWipeAfterFailures(int? attempts) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.setWipeAfterFailures(attempts);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> createVault(String pin) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.createVault(pin);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> unlock(String pin) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.unlock(pin);
      await _refreshState();
    } catch (e) {
      final failure = _mapExceptionToFailure(e);
      // The attempt count, lockout or (after an erase) the vault itself
      // changed with the failure.
      try {
        await _refreshState();
      } catch (refreshError, stack) {
        diogelLog(
          'VaultController: refresh after a failed unlock failed',
          error: refreshError,
          stackTrace: stack,
        );
      }
      state = state.copyWith(failure: failure);
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> lock() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.lock();
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> expireSession() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.expireSession();
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Erases the vault and everything tied to it, then returns to setup (#20).
  ///
  /// Returns the failure, if any, because the screen that asked has usually
  /// gone by the time the wipe ends.
  Future<VaultFailure?> wipe() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    VaultFailure? failure;
    try {
      await _vaultService.wipe();
    } catch (e) {
      failure = _mapExceptionToFailure(e);
      state = state.copyWith(failure: failure);
    } finally {
      await _refreshState();
      state = state.copyWith(isLoading: false);
    }
    return failure;
  }

  Future<void> createIdentity({String? displayName}) async {
    if (state.vaultState is! VaultUnlocked) {
      state = state.copyWith(failure: const VaultLockedFailure());
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.createIdentity(displayName: displayName);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> importIdentity(String keyInput, {String? displayName}) async {
    if (state.vaultState is! VaultUnlocked) {
      state = state.copyWith(failure: const VaultLockedFailure());
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.importIdentity(keyInput, displayName: displayName);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setActiveIdentity(String localId) async {
    if (state.vaultState is! VaultUnlocked) {
      state = state.copyWith(failure: const VaultLockedFailure());
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.setActiveIdentity(localId);
      await _refreshState();
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  VaultFailure _mapExceptionToFailure(Object e) {
    if (e is VaultLockedException) {
      return const VaultLockedFailure();
    }
    if (e is VaultNotFoundException) {
      return const VaultNotFoundFailure();
    }
    if (e is VaultAlreadyExistsException) {
      return const VaultAlreadyExistsFailure();
    }
    if (e is InvalidPinException) {
      return const InvalidPinFailure();
    }
    if (e is VaultLockedOutException) {
      return VaultLockedOutFailure(e.remaining);
    }
    if (e is VaultWipedException) {
      return const VaultWipedFailure();
    }
    if (e is VaultWipeIncompleteException) {
      return const VaultWipeIncompleteFailure();
    }
    if (e is IdentityNotFoundException) {
      return const IdentityNotFoundFailure();
    }
    if (e is VaultStorageException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already exists')) {
        return const DuplicateIdentityFailure();
      }
      if (msg.contains('invalid nsec')) {
        return const InvalidPrivateKeyFailure();
      }
      if (msg.contains('invalid') || msg.contains('format')) {
        return const UnsupportedKeyFormatFailure();
      }
      return SecureStorageFailure(e.message);
    }
    return SecureStorageFailure(e.toString());
  }
}
