import 'dart:async';
import 'dart:typed_data';
import 'package:symudol/app/diogel_log.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_store.dart';
import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/signing/domain/nostr_crypto_service.dart';
import 'package:symudol/features/vault/data/platform_biometric_vault.dart';
import 'package:symudol/features/vault/data/platform_monotonic_clock.dart';
import 'package:symudol/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:symudol/features/vault/data/vault_identity_record.dart';
import 'package:symudol/features/vault/domain/biometric_unlock_status.dart';
import 'package:symudol/features/vault/domain/biometric_vault.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/monotonic_clock.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_key_envelope.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:symudol/features/vault/domain/vault_service.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:symudol/features/vault/domain/vault_store.dart';
import 'package:dart_nostr/dart_nostr.dart';

/// The last unlock attempt queued on each service (#16).
///
/// Kept outside [VaultServiceImpl]: work handed to [ConcurrencyUtils.runTask]
/// copies the service into another isolate, and a [Future] cannot be copied.
final Expando<Future<void>> _unlockQueues = Expando('vault unlock queue');

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

  /// Failed-attempt counts that can erase the vault; `null` (the default)
  /// never erases it (#16).
  static const Set<int> supportedWipeAfterFailures = {10, 15, 20};

  static final RegExp _pinPattern = RegExp(r'^\d{6}$');

  /// The longest lockout a run of failed PINs earns.
  static const Duration maxLockout = Duration(hours: 24);

  /// How long biometric unlock works after the last PIN check (#23). A
  /// restart also asks for the PIN.
  static const Duration biometricPinInterval = Duration(hours: 72);

  /// Marks the key envelope storage format (#16).
  static const String storeVersion = '2';

  /// The lockout earned by [attempts] consecutive failed PINs (#16).
  ///
  /// Attempts 1-4 are free. Then 5: 30 s, 6: 1 min, 7: 5 min, 8: 15 min,
  /// 9: 1 h, and from 10 the lockout doubles from 2 h, up to [maxLockout].
  static Duration lockoutFor(int attempts) {
    switch (attempts) {
      case < 5:
        return Duration.zero;
      case 5:
        return const Duration(seconds: 30);
      case 6:
        return const Duration(minutes: 1);
      case 7:
        return const Duration(minutes: 5);
      case 8:
        return const Duration(minutes: 15);
      case 9:
        return const Duration(hours: 1);
    }
    final doublings = attempts - 10;
    // 2 h doubled four times is past the cap; stop before the shift overflows.
    if (doublings >= 4) return maxLockout;
    final lockout = Duration(hours: 2 << doublings);
    return lockout > maxLockout ? maxLockout : lockout;
  }

  final VaultStore _store;
  final NostrCryptoService _cryptoService;
  final VaultCryptoService _vaultCryptoService;
  final MonotonicClock _clock;
  final BiometricVault _biometricVault;
  final Nip55PermissionStore? _nip55PermissionStore;
  final Nip46SessionStore? _nip46SessionStore;
  final Future<void> Function()? _wipeNativeState;
  VaultState _state = const NoVault();
  VaultIdentity? _activeIdentity;
  Uint8List? _dek;

  VaultServiceImpl(
    this._store, {
    NostrCryptoService cryptoService = const DartNostrCryptoService(),
    VaultCryptoService? vaultCryptoService,
    MonotonicClock clock = const PlatformMonotonicClock(),
    BiometricVault biometricVault = const PlatformBiometricVault(),
    Nip55PermissionStore? nip55PermissionStore,
    Nip46SessionStore? nip46SessionStore,
    Future<void> Function()? wipeNativeState,
  }) : _cryptoService = cryptoService,
       _vaultCryptoService =
           vaultCryptoService ?? const PointyCastleVaultCryptoService(),
       _clock = clock,
       _biometricVault = biometricVault,
       _nip55PermissionStore = nip55PermissionStore,
       _nip46SessionStore = nip46SessionStore,
       _wipeNativeState = wipeNativeState;

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
      // With no vault nothing else may remain. This also finishes a wipe that
      // was interrupted after the vault keys went (#20). It runs alongside
      // start-up rather than holding it: it is cleanup, and finishes long
      // before a new vault can be set up.
      unawaited(
        _clearLinkedData().then((failed) {
          if (failed.isNotEmpty) {
            diogelLog('VaultService: init could not clear ${failed.join(', ')}');
          }
        }),
      );
    } else {
      _state = const VaultLocked();
      _activeIdentity = null;
    }
  }

  @override
  Future<void> wipe() async {
    // Signing stops at once, whatever happens to storage below.
    _activeIdentity = null;
    _clearDek();
    _state = const NoVault();

    final failed = <String>[];
    // The vault keys go first: a wipe cut short leaves no vault, and init()
    // finishes the rest on the next launch. deleteAll() also removes the
    // stored grants and sessions; the steps below clear their caches, the
    // native mirror and anything stored elsewhere.
    await _attemptWipeStep('vault', _store.clearAll, failed);
    failed.addAll(await _clearLinkedData());

    try {
      if (await _store.getWrappedDek() != null) {
        _state = const VaultLocked();
      }
    } catch (e) {
      diogelLog('VaultService: could not read the vault after wiping', error: e);
      // Unknown: assume a vault the wipe could not delete is still there.
      if (failed.contains('vault')) _state = const VaultLocked();
    }

    if (failed.isNotEmpty) {
      throw VaultWipeIncompleteException(failed);
    }
  }

  /// Clears everything tied to the vault outside it, attempting every step.
  /// Returns the steps that failed.
  Future<List<String>> _clearLinkedData() async {
    final failed = <String>[];
    final wipeNativeState = _wipeNativeState;
    final nip46SessionStore = _nip46SessionStore;
    final nip55PermissionStore = _nip55PermissionStore;
    if (wipeNativeState != null) {
      await _attemptWipeStep('native NIP-55 state', wipeNativeState, failed);
    }
    await _attemptWipeStep(
      'biometric key',
      _biometricVault.deleteKey,
      failed,
    );
    if (nip46SessionStore != null) {
      await _attemptWipeStep(
        'NIP-46 sessions',
        nip46SessionStore.clearAll,
        failed,
      );
    }
    if (nip55PermissionStore != null) {
      await _attemptWipeStep(
        'NIP-55 grants',
        nip55PermissionStore.clearAll,
        failed,
      );
    }
    return failed;
  }

  Future<void> _attemptWipeStep(
    String name,
    Future<void> Function() step,
    List<String> failed,
  ) async {
    try {
      await step();
    } catch (e, stack) {
      diogelLog(
        'VaultService: wipe step failed: $name',
        error: e,
        stackTrace: stack,
      );
      failed.add(name);
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

    await _store.setKeyEnvelope(
      VaultKeyEnvelope(salt: salt, params: params, wrappedDek: wrappedDek),
    );
    await _store.setVersion(storeVersion);
    await _store.setFailedUnlockAttempts(0);
    await _store.setLockout(null);
    await _store.setPinVerifiedAt(await _clock.now());

    _dek = dek;
    _state = const VaultUnlocked();
  }

  /// Unlock attempts run one at a time, so a wrong PIN that erases the vault
  /// cannot be overtaken by a second attempt still checking its PIN.
  @override
  Future<void> unlock(String pin) => _queued(() => _unlock(pin));

  /// Runs [task] after every PIN check already queued on this service:
  /// unlocks and PIN changes never overlap (#16, #21).
  Future<T> _queued<T>(Future<T> Function() task) {
    final previous = _unlockQueues[this] ?? Future<void>.value();
    final attempt = previous.then((_) => task());
    _unlockQueues[this] = attempt.then<void>((_) {}, onError: (_) {});
    return attempt;
  }

  Future<void> _unlock(String pin) async {
    final (:envelope, :dek) = await _checkPin(pin);
    await _upgradeKeyEnvelope(pin, envelope, dek);
    await _openWith(dek);
  }

  /// Opens the vault with [dek], from the PIN or a biometric.
  Future<void> _openWith(Uint8List dek) async {
    _dek = dek;
    _state = const VaultUnlocked();

    // Restore active identity from store
    final activeId = await _store.getActiveIdentityId();
    if (activeId != null) {
      final record = await _store.getIdentityRecord(activeId);
      _activeIdentity = record?.toVaultIdentity(isActive: true);
    }
  }

  /// Checks [pin] against the stored key envelope and returns it with the
  /// unwrapped DEK. Every PIN check, whether to unlock or to change the PIN,
  /// goes through here, so all of them share one count, lockout and wipe.
  ///
  /// Throws [VaultNotFoundException], [VaultLockedOutException],
  /// [InvalidPinException] or, at the wipe-after-N limit,
  /// [VaultWipedException].
  Future<({VaultKeyEnvelope envelope, Uint8List dek})> _checkPin(
    String pin,
  ) async {
    final envelope = await _store.getKeyEnvelope();
    if (envelope == null) {
      throw const VaultNotFoundException();
    }

    final now = await _clock.now();
    final remaining = await _lockoutRemainingAt(now);
    if (remaining > Duration.zero) {
      throw VaultLockedOutException(remaining);
    }

    // The attempt is charged, and the lockout it would earn set, before the
    // PIN is checked: killing the app during the check does not save a guess.
    // A correct PIN clears both below.
    final attempts = await _store.getFailedUnlockAttempts() + 1;
    await _store.setFailedUnlockAttempts(attempts);
    final lockout = lockoutFor(attempts);
    await _store.setLockout(
      lockout > Duration.zero ? VaultLockout.startingAt(now, lockout) : null,
    );

    final kek = await ConcurrencyUtils.runTask(
      () => _vaultCryptoService.deriveKek(pin, envelope.salt, envelope.params),
    );

    Uint8List dek;
    try {
      dek = await ConcurrencyUtils.runTask(
        () => _vaultCryptoService.unwrapDek(envelope.wrappedDek, kek),
      );
    } on VaultCryptoTamperException {
      await _wipeIfTooManyFailures(attempts);
      throw const InvalidPinException();
    }

    await _store.setFailedUnlockAttempts(0);
    await _store.setLockout(null);
    // Biometric unlock works for 72 hours from here, on this boot (#23).
    await _store.setPinVerifiedAt(now);
    return (envelope: envelope, dek: dek);
  }

  @override
  Future<BiometricUnlockStatus> getBiometricUnlockStatus() async {
    final enabled = await _store.getBiometricWrap() != null;
    BiometricAvailability availability;
    try {
      availability = await _biometricVault.availability();
    } catch (e, stack) {
      diogelLog(
        'VaultService: could not read biometric availability',
        error: e,
        stackTrace: stack,
      );
      availability = BiometricAvailability.unavailable;
    }
    return BiometricUnlockStatus(
      enabled: enabled,
      availability: availability,
      pinRequired: enabled && await _biometricNeedsPin(),
    );
  }

  /// Whether the PIN must be entered before a biometric unlock: on a new
  /// boot, if the clock went back, or [biometricPinInterval] after the last
  /// PIN check.
  Future<bool> _biometricNeedsPin() async {
    final verifiedAt = await _store.getPinVerifiedAt();
    if (verifiedAt == null) return true;
    final now = await _clock.now();
    if (now.bootCount != verifiedAt.bootCount) return true;
    final sinceMs = now.elapsedMs - verifiedAt.elapsedMs;
    return sinceMs < 0 || sinceMs >= biometricPinInterval.inMilliseconds;
  }

  @override
  Future<void> enableBiometricUnlock(String pin) async {
    _checkUnlocked();
    if (await _biometricVault.availability() !=
        BiometricAvailability.available) {
      throw const BiometricUnavailableException();
    }
    await _queued(() async {
      final (envelope: _, :dek) = await _checkPin(pin);
      try {
        final wrap = await _biometricVault.wrap(dek);
        try {
          await _store.setBiometricWrap(wrap);
        } catch (e, stack) {
          diogelLog(
            'VaultService: could not save the biometric wrap',
            error: e,
            stackTrace: stack,
          );
          await _deleteBiometricKey();
          throw const VaultStorageException(
            'Could not turn on biometric unlock',
          );
        }
      } finally {
        // A copy from the envelope; the session keeps its own.
        dek.fillRange(0, dek.length, 0);
      }
    });
  }

  @override
  Future<void> disableBiometricUnlock() async {
    await _store.setBiometricWrap(null);
    await _deleteBiometricKey();
  }

  Future<void> _deleteBiometricKey() async {
    try {
      await _biometricVault.deleteKey();
    } catch (e, stack) {
      // The wrap is gone, so a key left behind opens nothing.
      diogelLog(
        'VaultService: could not delete the biometric key',
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> unlockWithBiometric() => _queued(() async {
    if (await _store.getKeyEnvelope() == null) {
      throw const VaultNotFoundException();
    }
    final wrap = await _store.getBiometricWrap();
    if (wrap == null) throw const BiometricUnavailableException();
    if (await _biometricNeedsPin()) {
      throw const BiometricPinRequiredException();
    }

    final Uint8List dek;
    try {
      dek = await _biometricVault.unwrap(wrap);
    } on BiometricKeyInvalidatedException {
      // A fingerprint was added, or the screen lock removed: the key is gone
      // for good, and the PIN still works.
      await disableBiometricUnlock();
      rethrow;
    }

    // The owner is proven: the PIN guesses before this are forgiven, as a
    // correct PIN would forgive them (#23).
    await _store.setFailedUnlockAttempts(0);
    await _store.setLockout(null);
    await _openWith(dek);
  });

  /// Changing the PIN re-wraps the same DEK, so identities, NIP-55 grants and
  /// NIP-46 sessions are untouched. The new envelope is one write: an
  /// interrupted change leaves the old PIN working (#21).
  @override
  Future<void> changePin(String currentPin, String newPin) async {
    _checkUnlocked();
    if (!_pinPattern.hasMatch(newPin)) {
      throw const VaultStorageException('The new PIN must be 6 digits');
    }
    await _queued(() async {
      // The DEK comes from the envelope, not the session, so a lock during
      // the check does not stop the change.
      final (envelope: _, :dek) = await _checkPin(currentPin);
      final salt = _vaultCryptoService.generateSalt();
      const params = VaultKdfParams.defaultParams;
      final kek = await ConcurrencyUtils.runTask(
        () => _vaultCryptoService.deriveKek(newPin, salt, params),
      );
      final wrappedDek = await ConcurrencyUtils.runTask(
        () => _vaultCryptoService.wrapDek(dek, kek),
      );
      try {
        await _store.setKeyEnvelope(
          VaultKeyEnvelope(salt: salt, params: params, wrappedDek: wrappedDek),
        );
      } catch (e, stack) {
        diogelLog(
          'VaultService: could not save the new PIN',
          error: e,
          stackTrace: stack,
        );
        throw const VaultStorageException('Could not save the new PIN');
      }
      await _store.setVersion(storeVersion);
    });
  }

  @override
  Future<int> getFailedUnlockAttempts() => _store.getFailedUnlockAttempts();

  @override
  Future<Duration> getLockoutRemaining() async {
    if (await _store.getWrappedDek() == null) return Duration.zero;
    return _lockoutRemainingAt(await _clock.now());
  }

  /// The lockout left at [now], after moving a pre-#16 wall-clock lockout
  /// onto the monotonic clock.
  Future<Duration> _lockoutRemainingAt(MonotonicInstant now) async {
    await _migrateLegacyLockout(now);
    final lockout = await _store.getLockout();
    if (lockout == null) return Duration.zero;
    final remaining = lockout.remainingAt(now);
    if (!lockout.isComparableWith(now)) {
      // A reboot: what was served cannot be measured, so the lockout starts
      // again, timed from now on this boot's clock.
      await _store.setLockout(VaultLockout.startingAt(now, remaining));
    }
    return remaining;
  }

  Future<void> _migrateLegacyLockout(MonotonicInstant now) async {
    final until = await _store.getLegacyLockoutUntil();
    if (until == null) return;
    final left = until.difference(DateTime.now());
    if (left > Duration.zero) {
      await _store.setLockout(
        VaultLockout.startingAt(now, left > maxLockout ? maxLockout : left),
      );
    }
    await _store.deleteLegacyLockoutUntil();
  }

  /// Erases the vault once [attempts] failed PINs reach the user's limit.
  Future<void> _wipeIfTooManyFailures(int attempts) async {
    final limit = await _store.getWipeAfterFailures();
    if (limit == null || attempts < limit) return;
    diogelLog('VaultService: $attempts failed PIN attempts, erasing the vault');
    try {
      await wipe();
    } on VaultWipeIncompleteException catch (e) {
      // With the vault keys gone the keys are unrecoverable, which is the
      // point; init() finishes the rest on the next launch.
      if (_state is! NoVault) rethrow;
      diogelLog('VaultService: wipe after failed PINs left ${e.failedSteps}');
    }
    throw const VaultWipedException();
  }

  /// After a successful unlock: moves a pre-#16 vault onto the single
  /// envelope, and re-wraps the same DEK under [VaultKdfParams.defaultParams]
  /// if the stored parameters are weaker.
  ///
  /// The new envelope is one write, so a failure leaves the old one working;
  /// it is retried on the next unlock.
  Future<void> _upgradeKeyEnvelope(
    String pin,
    VaultKeyEnvelope envelope,
    Uint8List dek,
  ) async {
    try {
      const params = VaultKdfParams.defaultParams;
      if (envelope.params.isWeakerThan(params)) {
        final salt = _vaultCryptoService.generateSalt();
        final kek = await ConcurrencyUtils.runTask(
          () => _vaultCryptoService.deriveKek(pin, salt, params),
        );
        final wrappedDek = await ConcurrencyUtils.runTask(
          () => _vaultCryptoService.wrapDek(dek, kek),
        );
        await _store.setKeyEnvelope(
          VaultKeyEnvelope(salt: salt, params: params, wrappedDek: wrappedDek),
        );
        diogelLog('VaultService: upgraded the KDF to $params');
      } else if (await _store.getVersion() != storeVersion) {
        await _store.setKeyEnvelope(envelope);
      } else {
        return;
      }
      await _store.setVersion(storeVersion);
    } catch (e, stack) {
      diogelLog(
        'VaultService: could not upgrade the key envelope',
        error: e,
        stackTrace: stack,
      );
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

  @override
  Future<int?> getWipeAfterFailures() => _store.getWipeAfterFailures();

  @override
  Future<void> setWipeAfterFailures(int? attempts) async {
    _checkUnlocked();
    if (attempts != null && !supportedWipeAfterFailures.contains(attempts)) {
      throw VaultStorageException(
        'Unsupported wipe after failed attempts: $attempts',
      );
    }
    await _store.setWipeAfterFailures(attempts);
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
