import 'package:symudol/features/vault/domain/biometric_unlock_status.dart';
import 'package:symudol/features/identity/domain/vault_identity.dart';
import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';

/// Interface for the Vault service.
///
/// This service is responsible for managing the vault lifecycle and identities.
/// Implementation should be independent of any specific storage mechanism
/// like flutter_secure_storage.
abstract interface class VaultService {
  /// Returns the current state of the vault.
  VaultState get state;

  /// Returns the active identity summary, or null if none is active or vault is locked.
  VaultIdentity? get activeIdentity;

  /// Creates a new vault with the given [pin].
  ///
  /// Throws [VaultAlreadyExistsException] if a vault already exists.
  /// Throws [VaultStorageException] if there is an error during creation.
  Future<void> createVault(String pin);

  /// Unlocks the vault with the given [pin].
  ///
  /// Throws [VaultNotFoundException] if no vault exists.
  /// Throws [InvalidPinException] if the PIN is incorrect.
  /// Throws [VaultLockedOutException] while too many failed attempts lock
  /// unlocking out.
  /// Throws [VaultWipedException] if this failed attempt reached the limit
  /// set with [setWipeAfterFailures] and the vault was erased.
  Future<void> unlock(String pin);

  /// Locks the vault.
  Future<void> lock();

  /// Changes the PIN from [currentPin] to [newPin] (6 digits).
  ///
  /// [currentPin] is checked like an unlock: it is charged, honours the
  /// lockout, and counts towards the wipe-after-N limit.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [VaultStorageException] if [newPin] is not 6 digits or the new
  /// PIN could not be saved; the old PIN then still works.
  /// Throws [InvalidPinException], [VaultLockedOutException] or
  /// [VaultWipedException] as [unlock] does.
  Future<void> changePin(String currentPin, String newPin);

  /// The number of consecutive failed PIN attempts.
  Future<int> getFailedUnlockAttempts();

  /// How long until the next PIN attempt is allowed; [Duration.zero] when it
  /// is allowed now.
  Future<Duration> getLockoutRemaining();

  /// How many failed PIN attempts erase the vault, or `null` (the default)
  /// when they never do.
  Future<int?> getWipeAfterFailures();

  /// Sets how many failed PIN attempts erase the vault: 10, 15, 20, or
  /// `null` for never.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  Future<void> setWipeAfterFailures(int? attempts);

  /// Expires the session due to inactivity.
  Future<void> expireSession();

  /// Where biometric unlock stands: on or off, whether this phone can use it,
  /// and whether the PIN is needed first (#23).
  Future<BiometricUnlockStatus> getBiometricUnlockStatus();

  /// Turns biometric unlock on: checks [pin] like an unlock (charged,
  /// honours the lockout, counts towards the wipe-after-N limit), then wraps
  /// the DEK under a new biometric Keystore key, which shows the system
  /// prompt.
  ///
  /// Throws [VaultLockedException] if the vault is locked,
  /// [BiometricUnavailableException] if this phone cannot use it, the PIN
  /// errors [unlock] throws, or a biometric error from the prompt.
  Future<void> enableBiometricUnlock(String pin);

  /// Turns biometric unlock off: deletes the wrap and the key.
  Future<void> disableBiometricUnlock();

  /// Unlocks with a biometric instead of the PIN. Allowed during a PIN
  /// lockout; success clears the failed-PIN count and the lockout, as a
  /// correct PIN does.
  ///
  /// Throws [VaultNotFoundException] if no vault exists,
  /// [BiometricUnavailableException] if biometric unlock is off,
  /// [BiometricPinRequiredException] after a restart or 72 hours without a
  /// PIN check, [BiometricKeyInvalidatedException] (and turns it off) if the
  /// key can no longer be used, or another biometric error from the prompt.
  Future<void> unlockWithBiometric();

  /// Permanently erases the vault and everything tied to it: every identity
  /// and key, NIP-55 grants (including the native mirror), and NIP-46
  /// sessions. Afterwards [state] is [NoVault], or [VaultLocked] if the vault
  /// itself could not be erased.
  ///
  /// Works whether the vault is locked or unlocked, and is safe to repeat.
  ///
  /// Throws [VaultWipeIncompleteException] if any part could not be erased.
  /// Every part is still attempted.
  Future<void> wipe();

  /// Creates a new identity in the vault.
  ///
  /// [displayName] is an optional name for the identity.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [VaultStorageException] if there is an error during creation.
  Future<VaultIdentity> createIdentity({String? displayName});

  /// Imports an existing identity into the vault using its [keyInput] (nsec or hex).
  ///
  /// [displayName] is an optional name for the identity.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [VaultStorageException] if the key is invalid or a duplicate.
  Future<VaultIdentity> importIdentity(String keyInput, {String? displayName});

  /// Lists all identities stored in the vault.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  Future<List<VaultIdentity>> listIdentities();

  /// Sets the identity with [localId] as the active identity.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [IdentityNotFoundException] if the identity does not exist.
  Future<void> setActiveIdentity(String localId);

  /// Signs a typed Nostr event draft using the active vault identity.
  ///
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [IdentityNotFoundException] if the identity does not exist.
  /// Throws [IdentityMismatchException] if [identityLocalId] is not active.
  Future<SignedNostrEvent> signNostrEvent({
    required String identityLocalId,
    required NostrEventDraft draft,
  });

  Future<String> signMessage({
    required String identityLocalId,
    required String message,
  });

  Future<String> nip04Encrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String plaintext,
  });

  Future<String> nip04Decrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String ciphertext,
  });

  Future<String> nip44Encrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String plaintext,
  });

  Future<String> nip44Decrypt({
    required String identityLocalId,
    required String peerPubkeyHex,
    required String ciphertext,
  });

  Future<String> decryptZapEvent({
    required String identityLocalId,
    required Map<String, Object?> eventJson,
  });

  /// Gets the inactivity timeout in minutes.
  Future<int> getInactivityTimeout();

  /// Sets the inactivity timeout in minutes.
  Future<void> setInactivityTimeout(int minutes);

  /// Gets the background lock delay in minutes.
  Future<int> getBackgroundLockDelayMinutes();

  /// Sets the background lock delay in minutes.
  Future<void> setBackgroundLockDelayMinutes(int minutes);

  /// Initializes the service state from persistent storage.
  Future<void> init();

  /// Returns the hex private key of the active identity, or null if vault is locked.
  ///
  /// This is used by the NIP-55 native bridge to sync the key to the
  /// ContentProvider for native auto-approve.
  Future<String?> getActivePrivateKey();
}
