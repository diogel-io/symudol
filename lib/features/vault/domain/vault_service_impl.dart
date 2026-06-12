import 'dart:async';
import 'dart:typed_data';
import 'package:android_diogel/app/utils/concurrency_utils.dart';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/requests/domain/nostr_event_draft.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';
import 'package:android_diogel/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:android_diogel/features/signing/domain/nostr_crypto_service.dart';
import 'package:android_diogel/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:android_diogel/features/vault/data/vault_identity_record.dart';
import 'package:android_diogel/features/vault/domain/vault_crypto_service.dart';
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

  /// Failed-unlock-attempt thresholds and the resulting lockout durations.
  ///
  /// Argon2id already adds per-attempt cost; this provides additional
  /// throttling on top of that. No automatic wipe is performed.
  static const Map<int, Duration> lockoutThresholds = {
    5: Duration(seconds: 30),
    10: Duration(minutes: 5),
  };

  final VaultStore _store;
  final NostrCryptoService _cryptoService;
  final VaultCryptoService _vaultCryptoService;
  final DateTime Function() _now;
  VaultState _state = const NoVault();
  VaultIdentity? _activeIdentity;
  Uint8List? _dek;

  VaultServiceImpl(
    this._store, {
    NostrCryptoService cryptoService = const DartNostrCryptoService(),
    VaultCryptoService? vaultCryptoService,
    DateTime Function()? now,
  }) : _cryptoService = cryptoService,
       _vaultCryptoService =
           vaultCryptoService ?? const PointyCastleVaultCryptoService(),
       _now = now ?? DateTime.now;

  @override
  VaultState get state => _state;

  @override
  VaultIdentity? get activeIdentity => _activeIdentity;

  @override
  Future<void> init() async {
    if (_state is VaultUnlocked) {
      return;
    }
    final wrappedDek = await _store.getWrappedDek();
    if (wrappedDek == null) {
      _state = const NoVault();
      _activeIdentity = null;
    } else {
      _state = const VaultLocked();
      _activeIdentity = null;
    }
  }

  @override
  Future<void> createVault(String pin) async {
    final existingWrappedDek = await _store.getWrappedDek();
    if (existingWrappedDek != null) {
      throw const VaultAlreadyExistsException();
    }

    final salt = _vaultCryptoService.generateSalt();
    final dek = _vaultCryptoService.generateDek();
    const params = VaultKdfParams.defaultParams;

    final kek = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.deriveKek(pin, salt, params),
    );
    final wrappedDek = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.wrapDek(dek, kek),
    );

    await _store.setKdfSalt(salt);
    await _store.setKdfParams(params);
    await _store.setWrappedDek(wrappedDek);
    await _store.setFailedUnlockAttempts(0);
    await _store.setLockoutUntil(null);

    _dek = dek;
    _state = const VaultUnlocked();
  }

  @override
  Future<void> unlock(String pin) async {
    final wrappedDek = await _store.getWrappedDek();
    if (wrappedDek == null) {
      throw const VaultNotFoundException();
    }

    final lockoutUntil = await _store.getLockoutUntil();
    if (lockoutUntil != null && _now().isBefore(lockoutUntil)) {
      throw VaultLockedOutException(lockoutUntil);
    }

    final salt = await _store.getKdfSalt();
    final params = await _store.getKdfParams();
    if (salt == null || params == null) {
      throw const VaultNotFoundException();
    }

    final kek = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.deriveKek(pin, salt, params),
    );

    Uint8List dek;
    try {
      dek = await ConcurrencyUtils.runTask(
        () => _vaultCryptoService.unwrapDek(wrappedDek, kek),
      );
    } on VaultCryptoTamperException {
      await _recordFailedUnlockAttempt();
      throw const InvalidPinException();
    }

    await _store.setFailedUnlockAttempts(0);
    await _store.setLockoutUntil(null);

    _dek = dek;
    _state = const VaultUnlocked();

    // Restore active identity from store
    final activeId = await _store.getActiveIdentityId();
    if (activeId != null) {
      final record = await _store.getIdentityRecord(activeId);
      _activeIdentity = record?.toVaultIdentity(isActive: true);
    }
  }

  Future<void> _recordFailedUnlockAttempt() async {
    final attempts = await _store.getFailedUnlockAttempts() + 1;
    await _store.setFailedUnlockAttempts(attempts);

    Duration? lockoutDuration;
    for (final entry in lockoutThresholds.entries) {
      if (attempts >= entry.key) {
        lockoutDuration = entry.value;
      }
    }
    if (lockoutDuration != null) {
      await _store.setLockoutUntil(_now().add(lockoutDuration));
    }
  }

  @override
  Future<void> lock() async {
    _activeIdentity = null;
    _clearDek();
    final wrappedDek = await _store.getWrappedDek();
    if (wrappedDek == null) {
      _state = const NoVault();
    } else {
      _state = const VaultLocked();
    }
  }

  @override
  Future<void> expireSession() async {
    _activeIdentity = null;
    _clearDek();
    final wrappedDek = await _store.getWrappedDek();
    if (wrappedDek == null) {
      _state = const NoVault();
    } else {
      _state = const SessionExpired();
    }
  }

  void _clearDek() {
    final dek = _dek;
    if (dek != null) {
      dek.fillRange(0, dek.length, 0);
    }
    _dek = null;
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

    final encryptedSecretPayload = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.encrypt(privateKey, _dekOrThrow()),
    );

    final record = VaultIdentityRecord(
      identityId: localId,
      publicKey: publicKey,
      encryptedSecretPayload: encryptedSecretPayload,
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
        hexPrivateKey = await ConcurrencyUtils.runTask(
          () => nostr.services.bech32.decodeNsecKeyToPrivateKey(trimmedInput),
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
      publicKey = await ConcurrencyUtils.runTask(
        () => nostr.services.keys
            .generateKeyPairFromExistingPrivateKey(hexPrivateKey)
            .public,
      );
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

    final encryptedSecretPayload = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.encrypt(hexPrivateKey, _dekOrThrow()),
    );

    final record = VaultIdentityRecord(
      identityId: localId,
      publicKey: publicKey,
      encryptedSecretPayload: encryptedSecretPayload,
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
    final privateKey = await _activePrivateKeyFor(identityLocalId);

    try {
      final signedEvent = await ConcurrencyUtils.runTask(
        () => _cryptoService.signEvent(
          privateKeyHex: privateKey,
          draft: draft,
        ),
      );
      if (!await ConcurrencyUtils.runTask(
        () => _cryptoService.verifySignedEvent(signedEvent),
      )) {
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
  Future<String> signMessage({
    required String identityLocalId,
    required String message,
  }) async {
    final privateKey = await _activePrivateKeyFor(identityLocalId);
    return _runCryptoOperation(
      () => ConcurrencyUtils.runTask(
        () => _cryptoService.signMessage(
          privateKeyHex: privateKey,
          message: message,
        ),
      ),
    );
  }

  @override
  Future<String> nip04Encrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String plaintext,
  }) async {
    final privateKey = await _activePrivateKeyFor(identityLocalId);
    return _runCryptoOperation(
      () => ConcurrencyUtils.runTask(
        () => _cryptoService.nip04Encrypt(
          privateKeyHex: privateKey,
          peerPubkeyHex: peerPubkeyHex,
          plaintext: plaintext,
        ),
      ),
    );
  }

  @override
  Future<String> nip04Decrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String ciphertext,
  }) async {
    final privateKey = await _activePrivateKeyFor(identityLocalId);
    return _runCryptoOperation(
      () => ConcurrencyUtils.runTask(
        () => _cryptoService.nip04Decrypt(
          privateKeyHex: privateKey,
          peerPubkeyHex: peerPubkeyHex,
          ciphertext: ciphertext,
        ),
      ),
    );
  }

  @override
  Future<String> nip44Encrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String plaintext,
  }) async {
    final privateKey = await _activePrivateKeyFor(identityLocalId);
    return _runCryptoOperation(
      () => ConcurrencyUtils.runTask(
        () => _cryptoService.nip44Encrypt(
          privateKeyHex: privateKey,
          peerPubkeyHex: peerPubkeyHex,
          plaintext: plaintext,
        ),
      ),
    );
  }

  @override
  Future<String> nip44Decrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String ciphertext,
  }) async {
    final privateKey = await _activePrivateKeyFor(identityLocalId);
    return _runCryptoOperation(
      () => ConcurrencyUtils.runTask(
        () => _cryptoService.nip44Decrypt(
          privateKeyHex: privateKey,
          peerPubkeyHex: peerPubkeyHex,
          ciphertext: ciphertext,
        ),
      ),
    );
  }

  @override
  Future<String> decryptZapEvent({
    required String identityLocalId,
    required Map<String, Object?> eventJson,
  }) async {
    final privateKey = await _activePrivateKeyFor(identityLocalId);
    return _runCryptoOperation(
      () => ConcurrencyUtils.runTask(
        () => _cryptoService.decryptZapEvent(
          privateKeyHex: privateKey,
          eventJson: eventJson,
        ),
      ),
    );
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

  Uint8List _dekOrThrow() {
    final dek = _dek;
    if (dek == null) {
      throw const VaultLockedException();
    }
    return dek;
  }

  @override
  Future<String?> getActivePrivateKey() async {
    if (state is! VaultUnlocked) return null;
    final identity = _activeIdentity;
    if (identity == null) return null;
    final record = await _store.getIdentityRecord(identity.localId);
    if (record == null) return null;
    return ConcurrencyUtils.runTask(
      () => _vaultCryptoService.decrypt(
        record.encryptedSecretPayload,
        _dekOrThrow(),
      ),
    );
  }

  Future<String> _activePrivateKeyFor(String identityLocalId) async {
    final record = await _activeRecordFor(identityLocalId);
    final privateKey = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.decrypt(
        record.encryptedSecretPayload,
        _dekOrThrow(),
      ),
    );

    final derivedPublicKey = await ConcurrencyUtils.runTask(
      () => _cryptoService.derivePublicKey(privateKey),
    );
    if (derivedPublicKey != record.publicKey) {
      throw const VaultSigningException(
        'Stored identity key material is invalid',
      );
    }
    return privateKey;
  }

  Future<VaultIdentityRecord> _activeRecordFor(String identityLocalId) async {
    _checkUnlocked();

    final record = await _store.getIdentityRecord(identityLocalId);
    if (record == null) {
      throw const IdentityNotFoundException();
    }

    if (_activeIdentity?.localId != identityLocalId) {
      throw const IdentityMismatchException();
    }

    return record;
  }

  Future<String> _runCryptoOperation(
    FutureOr<String> Function() operation,
  ) async {
    try {
      return await operation();
    } on VaultException {
      rethrow;
    } catch (_) {
      throw const VaultSigningException('Unable to complete NIP-55 operation');
    }
  }
}
