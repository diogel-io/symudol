import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_failure.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:state_notifier/state_notifier.dart';

class VaultControllerState {
  final VaultState vaultState;
  final List<VaultIdentity> identities;
  final VaultIdentity? activeIdentity;
  final int inactivityTimeoutMinutes;
  final bool isLoading;
  final VaultFailure? failure;

  const VaultControllerState({
    required this.vaultState,
    this.identities = const [],
    this.activeIdentity,
    this.inactivityTimeoutMinutes = 5,
    this.isLoading = false,
    this.failure,
  });

  VaultControllerState copyWith({
    VaultState? vaultState,
    List<VaultIdentity>? identities,
    VaultIdentity? activeIdentity,
    int? inactivityTimeoutMinutes,
    bool? isLoading,
    VaultFailure? failure,
    bool clearFailure = false,
  }) {
    return VaultControllerState(
      vaultState: vaultState ?? this.vaultState,
      identities: identities ?? this.identities,
      activeIdentity: activeIdentity ?? this.activeIdentity,
      inactivityTimeoutMinutes: inactivityTimeoutMinutes ?? this.inactivityTimeoutMinutes,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class VaultController extends StateNotifier<VaultControllerState> {
  final VaultService _vaultService;

  VaultController(this._vaultService)
      : super(VaultControllerState(vaultState: _vaultService.state)) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    // VaultService.init() is called by vaultInitializationProvider, 
    // but we ensure we have the latest state here.
    await _refreshState();
    state = state.copyWith(isLoading: false);
  }

  Future<void> _refreshState() async {
    final vaultState = _vaultService.state;
    List<VaultIdentity> identities = [];
    VaultIdentity? activeIdentity;
    int timeout = 5;

    if (vaultState is VaultUnlocked) {
      identities = await _vaultService.listIdentities();
      activeIdentity = _vaultService.activeIdentity;
      timeout = await _vaultService.getInactivityTimeout();
    } else if (vaultState is VaultLocked) {
      activeIdentity = _vaultService.activeIdentity;
      // In locked state we might not be able to get the timeout if it requires KEK, 
      // but getInactivityTimeout is just a simple read from store for now.
      timeout = await _vaultService.getInactivityTimeout();
    } else if (vaultState is NoVault) {
      // Ensure everything is cleared
      identities = [];
      activeIdentity = null;
    }

    state = state.copyWith(
      vaultState: vaultState,
      identities: identities,
      activeIdentity: activeIdentity,
      inactivityTimeoutMinutes: timeout,
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
    if (e is VaultStorageException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already exists')) {
        return const DuplicateIdentityFailure();
      }
      if (msg.contains('invalid') || msg.contains('format')) {
        return const UnsupportedKeyFormatFailure();
      }
      return SecureStorageFailure(e.message);
    }
    return SecureStorageFailure(e.toString());
  }
}
