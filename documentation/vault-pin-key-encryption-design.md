# Vault PIN-Derived Key Encryption Design

## Current limitation

`VaultServiceImpl.createVault()` and `unlock()` do not use the PIN at all. `createVault` writes a hardcoded sentinel (`'vault_exists'`); `unlock` only checks that a sentinel exists. Any 6-digit PIN unlocks an existing vault, and identity private keys (`VaultIdentityRecord.secretPayload`) are stored as plaintext in `flutter_secure_storage`. The only protection today is whatever encryption the OS-level secure storage backend provides — the PIN is not load-bearing.

This is acceptable for the current prototype stage but must be addressed before the app can be considered a real signer, per the README's stated priority of defining the session/security model "before deep signer logic lands."

## Constraint: GrapheneOS as a primary target

Diogel targets GrapheneOS users, which raised the question of whether the app can rely on hardware-backed key storage (Android Keystore / StrongBox / secure element). GrapheneOS does not remove Android Keystore or StrongBox support — on Pixel hardware it actually hardens the Titan M2-backed StrongBox path. So `flutter_secure_storage`'s Keystore-backed encryption remains available and useful as defense-in-depth, but it cannot be the *only* protection, because:

- Keystore-backed decryption is gated by device unlock state, not by Diogel's own PIN.
- It gives no way to make the app's PIN actually mean something.
- Relying solely on it means a compromised/rooted device with an unlocked screen can read all private keys regardless of the Diogel PIN.

## Decision: build a PIN-derived key-encryption layer on top of platform storage

Rather than depending on the secure element as the sole protection, or trying to source one consistently across GrapheneOS/non-GrapheneOS devices, Diogel will implement its own key hierarchy in software using `pointycastle` (already a dependency, and confirmed to ship Argon2, scrypt, PBKDF2, and AES-GCM). Platform secure storage (`flutter_secure_storage`) remains in place underneath as an additional layer, but the PIN becomes the thing that actually gates key recovery.

### Key hierarchy

```
PIN ──Argon2id(salt, params)──► KEK ──AES-256-GCM wrap──► DEK ──AES-256-GCM──► each identity's secretPayload
```

- **DEK (data encryption key)**: random 256-bit AES key, generated once at vault creation. Encrypts each `VaultIdentityRecord.secretPayload` individually, each with its own random nonce.
- **KEK (key encryption key)**: derived from the PIN via Argon2id with a random per-vault salt. Wraps (encrypts) the DEK.
- The wrapped DEK and salt are stored via `flutter_secure_storage` as today — Keystore/StrongBox-backed where available, defense-in-depth rather than primary protection.

### Storage layout (vault version 2)

| Key | Contents |
|---|---|
| `vault_kdf_salt` | random 16 bytes, base64 |
| `vault_kdf_params` | JSON: `{algorithm: "argon2id", memory, iterations, parallelism}` |
| `vault_wrapped_dek` | base64(nonce ‖ ciphertext ‖ tag) |
| `vault_failed_attempts` / `vault_lockout_until` | brute-force tracking, stored unencrypted (these don't protect secrets, only throttle attempts) |
| `identity_<id>` | record stores `encryptedSecretPayload` (base64 nonce ‖ ciphertext ‖ tag) instead of plaintext `secretPayload`; record `version` bumped |

`vault_sentinel` is retired. Presence of `vault_wrapped_dek` is the new "vault exists" signal.

### Unlock flow

1. Read salt, KDF params, and wrapped DEK.
2. Derive KEK = Argon2id(pin, salt, params), run via `ConcurrencyUtils.runTask` (background isolate) since Argon2id is intentionally CPU/memory-heavy.
3. AES-GCM-decrypt the wrapped DEK using KEK. The GCM authentication tag check **is** the PIN check — failure means wrong PIN and surfaces as `InvalidPinException`.
4. Hold the DEK in memory only for the unlocked session (new field on `VaultServiceImpl`). On `lock()` / `expireSession()`, overwrite and drop the DEK bytes.
5. Identity secrets are decrypted on demand (in `_activeRecordFor` / `getActivePrivateKey`) using the in-memory DEK and are never persisted in decrypted form.

### Create-vault flow

1. Generate a random salt and a random DEK.
2. KEK = Argon2id(pin, salt, params); wrap the DEK with KEK.
3. Persist salt, KDF params, and wrapped DEK. Keep the DEK in memory (vault starts unlocked).

### Brute-force protection

- Argon2id's cost adds friction per attempt by design.
- `vault_failed_attempts` / `vault_lockout_until` are tracked outside the KEK and drive exponential backoff after repeated wrong PINs (e.g. 5 failures → 30s lockout, 10 → 5 min, ...).
- No automatic wipe-on-failure by default. Diogel is non-custodial — "forgot PIN" already means "lost keys" — so a destructive wipe-after-N-attempts policy, if offered at all, should be an explicit opt-in setting, not a default.

### No migration path needed

Diogel has not been released yet, so there is no installed base of v1 vaults to migrate. `vault_sentinel` and the plaintext `secretPayload` field can simply be replaced outright by the new layout — no upgrade step, version check, or compatibility shim is required. If this changes after release, a migration design should be written at that point.

### Code-level changes

- New `lib/features/vault/domain/vault_crypto_service.dart` (+ `pointycastle`-based implementation): `deriveKek(pin, salt, params)`, `wrapDek` / `unwrapDek`, `encrypt` / `decrypt(bytes, key)`.
- `VaultServiceImpl`: add in-memory `Uint8List? _dek`; `unlock` / `createVault` populate it; `lock` / `expireSession` zero it out; `_activeRecordFor` and `getActivePrivateKey` decrypt via `_dek`.
- `VaultIdentityRecord`: `secretPayload` → `encryptedSecretPayload`; bump record `version`.
- `VaultStore` / `SecureStorageVaultStore`: add the new key constants above.
- `InvalidPinException` becomes meaningful for the first time (currently defined but effectively unused).

## Open questions

1. **Argon2id parameters** — what memory/iteration/parallelism settings hit an acceptable unlock latency on low-end Android hardware? Needs benchmarking on real low-end devices rather than assuming desktop-oriented (OWASP) defaults.
2. **Lockout policy** — backoff-only, or also offer a configurable max-attempts wipe as an opt-in setting?

## Test strategy

- Unit-test `VaultCryptoService` (KEK derivation determinism for a given salt/params, wrap/unwrap round-trip, tamper detection via GCM tag failure on wrong PIN).
- Unit-test `VaultServiceImpl` unlock with correct/incorrect PIN, confirming `InvalidPinException` on bad PIN and that the in-memory DEK is cleared on lock/expire.
- Brute-force lockout timing tests using injectable clock (mirroring the `now` injection pattern already used in `Nip55Controller`).
