import 'dart:async';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';

class VaultServiceImpl implements VaultService {
  final VaultStore _store;
  VaultState _state = const NoVault();
  String? _sessionPin;

  VaultServiceImpl(this._store);

  @override
  VaultState get state => _state;

  /// Initializes the vault state by checking for an existing sentinel.
  Future<void> init() async {
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      _state = const NoVault();
    } else {
      _state = const VaultLocked();
    }
  }

  @override
  Future<void> createVault(String pin) async {
    final existingSentinel = await _store.getSentinel();
    if (existingSentinel != null) {
      throw const VaultAlreadyExistsException();
    }

    // In a real implementation, we might derive a key from the pin.
    // For now, we use the pin as a sentinel (placeholder).
    await _store.setSentinel('vault_exists');
    _sessionPin = pin;
    _state = const VaultUnlocked();
  }

  @override
  Future<void> unlock(String pin) async {
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      throw const VaultNotFoundException();
    }

    // Placeholder: In Task 3.1, we just compare with a hardcoded or stored value.
    // Since we don't have KEK derivation yet, we'll assume any PIN works for the placeholder
    // or we might want to store a hash. 
    // For this task, let's assume '1234' for simplicity or just transition to Unlocked.
    // The requirement says "unlock placeholder/session transition".
    
    _sessionPin = pin;
    _state = const VaultUnlocked();
  }

  @override
  Future<void> lock() async {
    _sessionPin = null;
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      _state = const NoVault();
    } else {
      _state = const VaultLocked();
    }
  }

  @override
  Future<VaultIdentity> createIdentity({String? displayName}) async {
    _checkUnlocked();
    // Implementation for later tasks
    throw UnimplementedError();
  }

  @override
  Future<VaultIdentity> importIdentity(String privateKey, {String? displayName}) async {
    _checkUnlocked();
    // Implementation for later tasks
    throw UnimplementedError();
  }

  @override
  Future<List<VaultIdentity>> listIdentities() async {
    _checkUnlocked();
    // Implementation for later tasks
    throw UnimplementedError();
  }

  @override
  Future<void> setActiveIdentity(String localId) async {
    _checkUnlocked();
    // Implementation for later tasks
    throw UnimplementedError();
  }

  void _checkUnlocked() {
    if (_state is! VaultUnlocked) {
      throw const VaultLockedException();
    }
  }
}
