import 'dart:async';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:android_diogel/features/signing/domain/nostr_crypto_service.dart';
import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:android_diogel/features/vault/domain/vault_store.dart';
import 'package:dart_nostr/dart_nostr.dart';

class VaultServiceImpl implements VaultService {
  static const int defaultInactivityTimeoutMinutes = 5;
  static const int defaultBackgroundLockDelayMinutes = 5;
  static const int defaultApprovalSessionDurationMinutes = 0;
  static const Set<int> supportedInactivityTimeoutMinutes = {
    0,
    1,
    5,
    15,
    30,
    60,
  };
  static const Set<int> supportedBackgroundLockDelayMinutes = {
    -1,
    0,
    1,
    5,
    15,
    30,
    60,
  };
  static const Set<int> supportedApprovalSessionDurationMinutes = {0, 1, 5, 15};

  final VaultStore _store;
  final NostrCryptoService _cryptoService;
  VaultState _state = const NoVault();
  VaultIdentity? _activeIdentity;

  VaultServiceImpl(
    this._store, {
    NostrCryptoService cryptoService = const DartNostrCryptoService(),
  }) : _cryptoService = cryptoService;

  @override
  VaultState get state => _state;

  @override
  VaultIdentity? get activeIdentity => _activeIdentity;

  @override
  Future<void> init() async {
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      _state = const NoVault();
      _activeIdentity = null;
    } else {
      _state = const VaultLocked();
      _activeIdentity = null;
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

    _state = const VaultUnlocked();

    // Restore active identity from store
    final activeId = await _store.getActiveIdentityId();
    if (activeId != null) {
      final record = await _store.getIdentityRecord(activeId);
      _activeIdentity = record?.toVaultIdentity(isActive: true);
    }
  }

  @override
  Future<void> lock() async {
    _activeIdentity = null;
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      _state = const NoVault();
    } else {
      _state = const VaultLocked();
    }
  }

  @override
  Future<void> expireSession() async {
    _activeIdentity = null;
    final sentinel = await _store.getSentinel();
    if (sentinel == null) {
      _state = const NoVault();
    } else {
      _state = const SessionExpired();
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
      throw const VaultStorageException(
        'Identity with this public key already exists',
      );
    }

    final now = DateTime.now();
    final localId =
        publicKey; // Using publicKey as localId for now, or could use UUID

    final record = VaultIdentityRecord(
      identityId: localId,
      publicKey: publicKey,
      secretPayload: privateKey,
      displayName: displayName,
      origin: IdentityOrigin.generated,
      createdAt: now,
    );

    await _store.saveIdentityRecord(record);

    final identity = record.toVaultIdentity(isActive: _activeIdentity == null);

    // Refresh identities from store if needed, but here we just need to update _activeIdentity if it's the first one
    if (_activeIdentity == null) {
      await setActiveIdentity(identity.localId);
    }

    return identity;
  }

  @override
  Future<VaultIdentity> importIdentity(
    String keyInput, {
    String? displayName,
  }) async {
    _checkUnlocked();

    final nostr = Nostr.instance;
    String hexPrivateKey;

    // Normalize input
    final trimmedInput = keyInput.trim();
    if (trimmedInput.startsWith('nsec1')) {
      try {
        hexPrivateKey = nostr.services.bech32.decodeNsecKeyToPrivateKey(
          trimmedInput,
        );
      } catch (e) {
        throw const VaultStorageException('Invalid nsec key format');
      }
    } else {
      // Assume hex
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmedInput)) {
        throw const VaultStorageException(
          'Invalid private key format: expected 64 hex characters',
        );
      }
      hexPrivateKey = trimmedInput.toLowerCase();
    }

    late final String publicKey;
    try {
      publicKey = nostr.services.keys
          .generateKeyPairFromExistingPrivateKey(hexPrivateKey)
          .public;
    } catch (e) {
      // This should ideally be caught by normalization, but as a safety measure:
      throw VaultStorageException('Failed to derive public key: $e');
    }

    // Duplicate check
    final existing = await _store.getIdentities();
    if (existing.any((i) => i.publicKey == publicKey)) {
      throw const VaultStorageException(
        'Identity with this public key already exists',
      );
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

    final identity = record.toVaultIdentity(isActive: _activeIdentity == null);

    if (_activeIdentity == null) {
      await setActiveIdentity(identity.localId);
    }

    return identity;
  }

  @override
  Future<List<VaultIdentity>> listIdentities() async {
    _checkUnlocked();
    final records = await _store.getIdentities();
    return records
        .map(
          (r) => r.toVaultIdentity(
            isActive: _activeIdentity?.localId == r.identityId,
          ),
        )
        .toList();
  }

  @override
  Future<void> setActiveIdentity(String localId) async {
    _checkUnlocked();
    final records = await _store.getIdentities();
    final record = records.firstWhere(
      (r) => r.identityId == localId,
      orElse: () => throw const IdentityNotFoundException(),
    );
    await _store.setActiveIdentityId(localId);
    _activeIdentity = record.toVaultIdentity(isActive: true);
  }

  @override
  Future<SignedNostrEvent> signNostrEvent({
    required String identityLocalId,
    required NostrEventDraft draft,
  }) async {
    _checkUnlocked();

    final record = await _store.getIdentityRecord(identityLocalId);
    if (record == null) {
      throw const IdentityNotFoundException();
    }

    if (_activeIdentity?.localId != identityLocalId) {
      throw const IdentityMismatchException();
    }

    final derivedPublicKey = _cryptoService.derivePublicKey(
      record.secretPayload,
    );
    if (derivedPublicKey != record.publicKey) {
      throw const VaultSigningException(
        'Stored identity key material is invalid',
      );
    }

    try {
      final signedEvent = _cryptoService.signEvent(
        privateKeyHex: record.secretPayload,
        draft: draft,
      );
      if (!_cryptoService.verifySignedEvent(signedEvent)) {
        throw const VaultSigningException('Signed event failed verification');
      }
      return signedEvent;
    } on VaultException {
      rethrow;
    } catch (_) {
      throw const VaultSigningException('Unable to sign event');
    }
  }

  @override
  Future<int> getInactivityTimeout() async {
    final timeout = await _store.getInactivityTimeout();
    return timeout ?? defaultInactivityTimeoutMinutes;
  }

  @override
  Future<void> setInactivityTimeout(int minutes) async {
    _validateSupportedMinutes(
      minutes,
      supportedInactivityTimeoutMinutes,
      'Unsupported inactivity timeout',
    );
    await _store.setInactivityTimeout(minutes);
  }

  @override
  Future<int> getBackgroundLockDelayMinutes() async {
    final delay = await _store.getBackgroundLockDelayMinutes();
    return delay ?? defaultBackgroundLockDelayMinutes;
  }

  @override
  Future<void> setBackgroundLockDelayMinutes(int minutes) async {
    _validateSupportedMinutes(
      minutes,
      supportedBackgroundLockDelayMinutes,
      'Unsupported background lock delay',
    );
    await _store.setBackgroundLockDelayMinutes(minutes);
  }

  @override
  Future<int> getApprovalSessionDurationMinutes() async {
    final duration = await _store.getApprovalSessionDurationMinutes();
    return duration ?? defaultApprovalSessionDurationMinutes;
  }

  @override
  Future<void> setApprovalSessionDurationMinutes(int minutes) async {
    _validateSupportedMinutes(
      minutes,
      supportedApprovalSessionDurationMinutes,
      'Unsupported approval session duration',
    );
    await _store.setApprovalSessionDurationMinutes(minutes);
  }

  void _validateSupportedMinutes(
    int minutes,
    Set<int> supportedValues,
    String message,
  ) {
    if (!supportedValues.contains(minutes)) {
      throw VaultStorageException('$message: $minutes minutes');
    }
  }

  void _checkUnlocked() {
    if (_state is! VaultUnlocked) {
      throw const VaultLockedException();
    }
  }
}
