import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';

class VaultControllerState {
  final VaultState vaultState;
  final List<VaultIdentity> identities;
  final VaultIdentity? activeIdentity;
  final bool isLoading;

  const VaultControllerState({
    required this.vaultState,
    this.identities = const [],
    this.activeIdentity,
    this.isLoading = false,
  });

  VaultControllerState copyWith({
    VaultState? vaultState,
    List<VaultIdentity>? identities,
    VaultIdentity? activeIdentity,
    bool? isLoading,
  }) {
    return VaultControllerState(
      vaultState: vaultState ?? this.vaultState,
      identities: identities ?? this.identities,
      activeIdentity: activeIdentity ?? this.activeIdentity,
      isLoading: isLoading ?? this.isLoading,
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

    if (vaultState is VaultUnlocked) {
      identities = await _vaultService.listIdentities();
      activeIdentity = _vaultService.activeIdentity;
    } else if (vaultState is VaultLocked) {
      activeIdentity = _vaultService.activeIdentity;
    }

    state = state.copyWith(
      vaultState: vaultState,
      identities: identities,
      activeIdentity: activeIdentity,
    );
  }

  Future<void> createVault(String pin) async {
    state = state.copyWith(isLoading: true);
    try {
      await _vaultService.createVault(pin);
      await _refreshState();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> unlock(String pin) async {
    state = state.copyWith(isLoading: true);
    try {
      await _vaultService.unlock(pin);
      await _refreshState();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> lock() async {
    state = state.copyWith(isLoading: true);
    try {
      await _vaultService.lock();
      await _refreshState();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> createIdentity({String? displayName}) async {
    if (state.vaultState is! VaultUnlocked) return;
    
    state = state.copyWith(isLoading: true);
    try {
      await _vaultService.createIdentity(displayName: displayName);
      await _refreshState();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> importIdentity(String keyInput, {String? displayName}) async {
    if (state.vaultState is! VaultUnlocked) return;

    state = state.copyWith(isLoading: true);
    try {
      await _vaultService.importIdentity(keyInput, displayName: displayName);
      await _refreshState();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setActiveIdentity(String localId) async {
    if (state.vaultState is! VaultUnlocked) return;

    state = state.copyWith(isLoading: true);
    try {
      await _vaultService.setActiveIdentity(localId);
      await _refreshState();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}
