import 'dart:async';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';
import 'package:dart_nostr/dart_nostr.dart';

class VaultServiceImpl implements VaultService {
  final VaultStore _store;
  VaultState _state = const NoVault();
  String? _sessionPin;
  VaultIdentity? _activeIdentity;

  VaultServiceImpl(this._store);

  @override
  VaultState get state => _state;

  @override
  VaultIdentity? get activeIdentity => _activeIdentity;

  /// Initializes the vault state by checking for an existing sentinel.
  Future<void> init() async {
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      _state = const NoVault();
    } else {
      _state = const VaultLocked();
      final activeId = await _store.getActiveIdentityId();
      if (activeId != null) {
        final record = await _store.getIdentityRecord(activeId);
        _activeIdentity = record?.toVaultIdentity();
      }
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

    final nostr = Nostr.instance;
    final keyPair = nostr.services.keys.generateKeyPair();
    final privateKey = keyPair.private;
    final publicKey = keyPair.public;

    // Duplicate check
    final existing = await _store.getIdentities();
    if (existing.any((i) => i.publicKey == publicKey)) {
      // Practically unlikely, but handled
      throw const VaultStorageException('Identity with this public key already exists');
    }

    final now = DateTime.now();
    final localId = publicKey; // Using publicKey as localId for now, or could use UUID

    final record = VaultIdentityRecord(
      identityId: localId,
      publicKey: publicKey,
      secretPayload: privateKey,
      displayName: displayName,
      origin: IdentityOrigin.generated,
      createdAt: now,
    );

    await _store.saveIdentityRecord(record);

    final identity = record.toVaultIdentity();
    
    // Refresh identities from store if needed, but here we just need to update _activeIdentity if it's the first one
    if (_activeIdentity == null) {
      await setActiveIdentity(identity.localId);
    }

    return identity;
  }

  @override
  Future<VaultIdentity> importIdentity(String keyInput, {String? displayName}) async {
    _checkUnlocked();

    final nostr = Nostr.instance;
    String hexPrivateKey;
    
    // Normalize input
    final trimmedInput = keyInput.trim();
    if (trimmedInput.startsWith('nsec1')) {
      try {
        hexPrivateKey = nostr.services.bech32.decodeNsecKeyToPrivateKey(trimmedInput);
      } catch (e) {
        throw const VaultStorageException('Invalid nsec key format');
      }
    } else {
      // Assume hex
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmedInput)) {
        throw const VaultStorageException('Invalid private key format: expected 64 hex characters');
      }
      hexPrivateKey = trimmedInput.toLowerCase();
    }

    late final String publicKey;
    try {
      publicKey = nostr.services.keys.generateKeyPairFromExistingPrivateKey(hexPrivateKey).public;
    } catch (e) {
      // This should ideally be caught by normalization, but as a safety measure:
      throw VaultStorageException('Failed to derive public key: $e');
    }

    // Duplicate check
    final existing = await _store.getIdentities();
    if (existing.any((i) => i.publicKey == publicKey)) {
      throw const VaultStorageException('Identity with this public key already exists');
    }

    final now = DateTime.now();
    final localId = publicKey;

    final record = VaultIdentityRecord(
      identityId: localId,
      publicKey: publicKey,
      secretPayload: hexPrivateKey,
      displayName: displayName,
      origin: IdentityOrigin.imported,
      createdAt: now,
    );

    await _store.saveIdentityRecord(record);

    final identity = record.toVaultIdentity();

    if (_activeIdentity == null) {
      await setActiveIdentity(identity.localId);
    }

    return identity;
  }

  @override
  Future<List<VaultIdentity>> listIdentities() async {
    _checkUnlocked();
    return await _store.getIdentities();
  }

  @override
  Future<void> setActiveIdentity(String localId) async {
    _checkUnlocked();
    final identities = await _store.getIdentities();
    final identity = identities.firstWhere(
      (i) => i.localId == localId,
      orElse: () => throw const IdentityNotFoundException(),
    );
    await _store.setActiveIdentityId(localId);
    _activeIdentity = identity;
  }

  void _checkUnlocked() {
    if (_state is! VaultUnlocked) {
      throw const VaultLockedException();
    }
  }
}
