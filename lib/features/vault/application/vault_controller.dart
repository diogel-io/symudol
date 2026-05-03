import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_failure.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:state_notifier/state_notifier.dart';

class VaultControllerState {
  final VaultState vaultState;
  final List<VaultIdentity> identities;
  final VaultIdentity? activeIdentity;
  final int inactivityTimeoutMinutes;
  final int backgroundLockDelayMinutes;
  final int approvalSessionDurationMinutes;
  final bool isLoading;
  final VaultFailure? failure;

  const VaultControllerState({
    required this.vaultState,
    this.identities = const [],
    this.activeIdentity,
    this.inactivityTimeoutMinutes = 5,
    this.backgroundLockDelayMinutes = 5,
    this.approvalSessionDurationMinutes = 0,
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
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      await _vaultService.init();
      await _refreshState();
    } catch (e) {
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

    if (vaultState is VaultUnlocked) {
      identities = await _vaultService.listIdentities();
      activeIdentity = _vaultService.activeIdentity;
      timeout = await _vaultService.getInactivityTimeout();
      backgroundLockDelay = await _vaultService.getBackgroundLockDelayMinutes();
      approvalSessionDuration = await _vaultService
          .getApprovalSessionDurationMinutes();
    } else if (vaultState is VaultLocked || vaultState is SessionExpired) {
      identities = [];
      activeIdentity = null;
      // In locked state we might not be able to get the timeout if it requires KEK,
      // but getInactivityTimeout is just a simple read from store for now.
      timeout = await _vaultService.getInactivityTimeout();
      backgroundLockDelay = await _vaultService.getBackgroundLockDelayMinutes();
      approvalSessionDuration = await _vaultService
          .getApprovalSessionDurationMinutes();
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
    );
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
      state = state.copyWith(failure: _mapExceptionToFailure(e));
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
