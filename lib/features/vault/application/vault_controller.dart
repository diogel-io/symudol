import 'dart:typed_data';

import 'package:symudol/app/diogel_log.dart';
import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/vault/domain/biometric_unlock_status.dart';
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

  /// Consecutive failed PIN attempts, read while locked (#16).
  final int failedUnlockAttempts;

  /// Failed PIN attempts that erase the vault, or `null` for never.
  final int? wipeAfterFailures;

  /// The lockout left when the state was read; [Duration.zero] for none.
  final Duration lockoutRemaining;

  /// Where biometric unlock stands (#23).
  final BiometricUnlockStatus biometricUnlock;
  final bool isLoading;
  final VaultFailure? failure;

  const VaultControllerState({
    required this.vaultState,
    this.identities = const [],
    this.activeIdentity,
    this.inactivityTimeoutMinutes = 5,
    this.backgroundLockDelayMinutes = 5,
    this.failedUnlockAttempts = 0,
    this.wipeAfterFailures,
    this.lockoutRemaining = Duration.zero,
    this.biometricUnlock = BiometricUnlockStatus.off,
    this.isLoading = true,
    this.failure,
  });

  VaultControllerState copyWith({
    VaultState? vaultState,
    List<VaultIdentity>? identities,
    VaultIdentity? activeIdentity,
    int? inactivityTimeoutMinutes,
    int? backgroundLockDelayMinutes,
    int? failedUnlockAttempts,
    int? wipeAfterFailures,
    bool clearWipeAfterFailures = false,
    Duration? lockoutRemaining,
    BiometricUnlockStatus? biometricUnlock,
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
      failedUnlockAttempts: failedUnlockAttempts ?? this.failedUnlockAttempts,
      wipeAfterFailures: clearWipeAfterFailures
          ? null
          : (wipeAfterFailures ?? this.wipeAfterFailures),
      lockoutRemaining: lockoutRemaining ?? this.lockoutRemaining,
      biometricUnlock: biometricUnlock ?? this.biometricUnlock,
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

  /// Re-reads the vault into [state]. The biometric status is read only when
  /// the vault state changes or [readBiometric] says it may have (#108): a
  /// settings or identity change leaves it alone, and the resume and
  /// Settings re-reads go through [refreshBiometricUnlock].
  Future<void> _refreshState({bool readBiometric = false}) async {
    final vaultState = _vaultService.state;
    final vaultStateChanged =
        vaultState.runtimeType != state.vaultState.runtimeType;
    List<VaultIdentity> identities = [];
    VaultIdentity? activeIdentity;
    int timeout = 5;
    int backgroundLockDelay = 5;
    int failedUnlockAttempts = 0;
    int? wipeAfterFailures;
    Duration lockoutRemaining = Duration.zero;

    if (vaultState is VaultUnlocked) {
      identities = await _vaultService.listIdentities();
      activeIdentity = _vaultService.activeIdentity;
      timeout = await _vaultService.getInactivityTimeout();
      backgroundLockDelay = await _vaultService.getBackgroundLockDelayMinutes();
      wipeAfterFailures = await _vaultService.getWipeAfterFailures();
      // The count and lockout are read on demand (refreshLockout) while
      // unlocked: only Change PIN needs them (#21).
      failedUnlockAttempts = state.failedUnlockAttempts;
      lockoutRemaining = state.lockoutRemaining;
    } else if (vaultState is VaultLocked || vaultState is SessionExpired) {
      identities = [];
      activeIdentity = null;
      // In locked state we might not be able to get the timeout if it requires KEK,
      // but getInactivityTimeout is just a simple read from store for now.
      timeout = await _vaultService.getInactivityTimeout();
      backgroundLockDelay = await _vaultService.getBackgroundLockDelayMinutes();
      // For the unlock screen's countdown and erase warning (#16).
      failedUnlockAttempts = await _vaultService.getFailedUnlockAttempts();
      wipeAfterFailures = await _vaultService.getWipeAfterFailures();
      lockoutRemaining = await _vaultService.getLockoutRemaining();
    } else if (vaultState is NoVault) {
      // Ensure everything is cleared
      identities = [];
      activeIdentity = null;
    }

    var biometricUnlock = state.biometricUnlock;
    VaultFailure? turnedOff;
    if (vaultState is NoVault) {
      biometricUnlock = BiometricUnlockStatus.off;
    } else if (readBiometric || vaultStateChanged) {
      try {
        biometricUnlock = await _vaultService.getBiometricUnlockStatus();
        turnedOff = _turnedOffFailure(biometricUnlock, vaultState);
      } catch (e, stack) {
        biometricUnlock = BiometricUnlockStatus.off;
        diogelLog(
          'VaultController: could not read biometric unlock',
          error: e,
          stackTrace: stack,
        );
      }
    }

    state = state.copyWith(
      vaultState: vaultState,
      identities: identities,
      biometricUnlock: biometricUnlock,
      failure: turnedOff,
      activeIdentity: activeIdentity,
      clearActiveIdentity: activeIdentity == null,
      inactivityTimeoutMinutes: timeout,
      backgroundLockDelayMinutes: backgroundLockDelay,
      failedUnlockAttempts: failedUnlockAttempts,
      wipeAfterFailures: wipeAfterFailures,
      clearWipeAfterFailures: wipeAfterFailures == null,
      lockoutRemaining: lockoutRemaining,
    );
  }

  /// Re-reads the PIN lockout and failed-attempt count, for the unlock and
  /// Change PIN screens' countdown and erase warning (#16, #21).
  Future<void> refreshLockout() async {
    try {
      state = state.copyWith(
        lockoutRemaining: await _vaultService.getLockoutRemaining(),
        failedUnlockAttempts: await _vaultService.getFailedUnlockAttempts(),
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

  /// Changes the PIN (#21). Returns the failure, if any, for the Change PIN
  /// screen, which is the only one that shows it; the shared state only
  /// keeps an erase, for the setup screen. A wrong current PIN also updates
  /// the count and lockout here.
  Future<VaultFailure?> changePin(String currentPin, String newPin) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    VaultFailure? failure;
    try {
      await _vaultService.changePin(currentPin, newPin);
    } catch (e) {
      failure = _mapExceptionToFailure(e);
    }
    try {
      await _refreshState(readBiometric: true);
    } catch (e, stack) {
      diogelLog(
        'VaultController: refresh after a PIN change failed',
        error: e,
        stackTrace: stack,
      );
    }
    if (state.vaultState is VaultUnlocked) await refreshLockout();
    state = state.copyWith(
      isLoading: false,
      failure: failure is VaultWipedFailure ? failure : null,
    );
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

  /// Unlocks with a biometric (#23). Returns the failure, or `null` on
  /// success or when the user cancelled the prompt.
  Future<VaultFailure?> unlockWithBiometric() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    VaultFailure? failure;
    try {
      await _vaultService.unlockWithBiometric();
    } on BiometricCancelledException {
      // Back to the PIN pad, with nothing to report.
    } catch (e) {
      failure = _mapExceptionToFailure(e);
    }
    try {
      await _refreshState(readBiometric: true);
    } catch (e, stack) {
      diogelLog(
        'VaultController: refresh after a biometric unlock failed',
        error: e,
        stackTrace: stack,
      );
    }
    state = state.copyWith(isLoading: false, failure: failure);
    return failure;
  }

  /// Turns biometric unlock on with the current [pin] (#23). Returns the
  /// failure, or `null` on success or when the user cancelled the prompt.
  Future<VaultFailure?> enableBiometricUnlock(String pin) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    VaultFailure? failure;
    try {
      await _vaultService.enableBiometricUnlock(pin);
    } on BiometricCancelledException {
      // Left off, with nothing to report.
    } catch (e) {
      failure = _mapExceptionToFailure(e);
    }
    try {
      await _refreshState(readBiometric: true);
    } catch (e, stack) {
      diogelLog(
        'VaultController: refresh after turning on biometric unlock failed',
        error: e,
        stackTrace: stack,
      );
    }
    if (state.vaultState is VaultUnlocked) await refreshLockout();
    state = state.copyWith(
      isLoading: false,
      failure: failure is VaultWipedFailure ? failure : null,
    );
    return failure;
  }

  /// Turns biometric unlock off (#23).
  Future<void> disableBiometricUnlock() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.disableBiometricUnlock();
      await _refreshState(readBiometric: true);
    } catch (e) {
      state = state.copyWith(failure: _mapExceptionToFailure(e));
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Re-reads whether biometric unlock can be offered, for example when the
  /// app comes back after the user enrolled a fingerprint (#23).
  Future<void> refreshBiometricUnlock() async {
    if (state.vaultState is NoVault) return;
    try {
      final biometricUnlock = await _vaultService.getBiometricUnlockStatus();
      state = state.copyWith(
        biometricUnlock: biometricUnlock,
        failure: _turnedOffFailure(biometricUnlock, state.vaultState),
      );
    } catch (e, stack) {
      diogelLog(
        'VaultController: could not read biometric unlock',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Tells the unlock screen why biometric unlock is gone when a status
  /// read just turned it off; Settings shows it as off.
  VaultFailure? _turnedOffFailure(
    BiometricUnlockStatus status,
    VaultState vaultState,
  ) => status.turnedOff && vaultState is! VaultUnlocked
      ? const BiometricKeyInvalidatedFailure()
      : null;

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

  /// A backup file of every identity, encrypted with [passphrase], after
  /// [pin] is checked like a PIN change (#25). Returns the file, or the
  /// failure; a wipe after too many PIN attempts is also recorded in the
  /// state, as for a PIN change.
  Future<(Uint8List?, VaultFailure?)> exportBackup({
    required String pin,
    required String passphrase,
  }) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    Uint8List? file;
    VaultFailure? failure;
    try {
      file = await _vaultService.exportBackup(pin: pin, passphrase: passphrase);
    } catch (e) {
      failure = _mapExceptionToFailure(e);
    }
    try {
      await _refreshState();
    } catch (e, stack) {
      diogelLog(
        'VaultController: refresh after a backup failed',
        error: e,
        stackTrace: stack,
      );
    }
    if (state.vaultState is VaultUnlocked) await refreshLockout();
    state = state.copyWith(
      isLoading: false,
      failure: failure is VaultWipedFailure ? failure : null,
    );
    return (file, failure);
  }

  /// Imports the identities in the backup [file] (#25).
  Future<(BackupRestoreResult?, VaultFailure?)> restoreBackup(
    Uint8List file,
    String passphrase,
  ) async {
    if (state.vaultState is! VaultUnlocked) {
      return (null, const VaultLockedFailure());
    }
    state = state.copyWith(isLoading: true, clearFailure: true);
    (BackupRestoreResult?, VaultFailure?) outcome;
    try {
      outcome = (await _vaultService.restoreBackup(file, passphrase), null);
    } catch (e) {
      outcome = (null, _mapExceptionToFailure(e));
    }
    // Refreshed either way: a restore that fails partway through may already
    // have saved some identities.
    try {
      await _refreshState();
    } catch (e, stack) {
      diogelLog(
        'VaultController: refresh after a restore failed',
        error: e,
        stackTrace: stack,
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
    return outcome;
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
    if (e is BiometricUnavailableException) {
      return const BiometricUnavailableFailure();
    }
    if (e is BiometricPinRequiredException) {
      return const BiometricPinRequiredFailure();
    }
    if (e is BiometricLockedOutException) {
      return const BiometricLockedOutFailure();
    }
    if (e is BiometricKeyInvalidatedException) {
      return const BiometricKeyInvalidatedFailure();
    }
    if (e is BiometricFailedException) {
      return BiometricFailure(e.message);
    }
    if (e is BackupPassphraseException) {
      return const BackupPassphraseFailure();
    }
    if (e is VaultBackupException) {
      return VaultBackupFailure(e.message);
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
