# Vault Hardening Implementation Pack

**Repo:** `android-diogel`  
**Branch reviewed:** `develop`  
**Baseline commit:** `cd1387a`  
**Created:** 2026-04-29  
**Purpose:** Fix the post-work-package issues found in the vault/account implementation before merge/release.

## Current Gate Status

- `flutter test`: passing at review time (`73` tests).
- `flutter analyze`: failing at review time (`47` analyzer issues).
- Repo state at review time: clean and aligned with `origin/develop`.

## Priority Order

1. Fix setup completion / post-PIN navigation failure.
2. Fix app/vault initialization race.
3. Align security copy with actual implementation, or implement real PIN verification/encryption if that is in scope.
4. Clear locked-state metadata intentionally.
5. Repair controller failure propagation and UI error handling.
6. Clean analyzer warnings and dependency declarations.

---

## WP0 — Fix Setup Completion / Post-PIN Navigation Failure

### Problem

In the emulator, entering the setup PIN twice can leave the user on the setup screen instead of navigating to the main/account screen.

This is a release-blocking first-run issue. The app either:

- fails to create/refresh the vault state and silently remains on setup, or
- creates the vault but the app shell does not react to the `VaultUnlocked` state transition reliably.

The current code makes this hard to diagnose because `SetupVaultScreen` expects exceptions, while `VaultController.createVault()` catches failures internally and stores them in controller state.

### Evidence

- `lib/features/vault/presentation/setup_vault_screen.dart`
  - `_onNumberPressed()` calls `_createVault()` after the sixth confirmation digit.
  - `_createVault()` only uses `try/catch`; it does not inspect `VaultControllerState.failure` after `createVault()`.
- `lib/features/vault/application/vault_controller.dart`
  - `createVault()` catches exceptions and sets `state.failure` instead of throwing.
  - `createVault()` should transition controller state to `VaultUnlocked` via `_refreshState()` on success.
- `lib/app/app.dart`
  - routing depends on `vaultStateProvider` switching from `NoVault` to `VaultUnlocked`.

### Implementation Approach

Treat setup completion as an explicit state-driven flow.

1. Add a focused regression test reproducing the emulator flow:
   - launch `DiogelApp`
   - enter six setup digits
   - enter the same six confirmation digits
   - expect `MainNavigationScreen` / `Accounts` screen
   - expect setup screen absent
2. In `SetupVaultScreen._createVault()`:
   - call `await controller.createVault(_pin)`
   - read `ref.read(vaultControllerProvider)` after the call
   - if `failure != null`, show mapped error and reset PIN fields
   - if `vaultState is VaultUnlocked`, do not manually navigate; allow app shell routing to switch screens
   - if neither success nor failure occurs, show a defensive error rather than staying silently stuck
3. Add a `ref.listen` in `SetupVaultScreen` or rely on the app shell after WP1 is fixed. Prefer app-shell routing, but a listener is acceptable if it only reacts to `VaultUnlocked` and does not duplicate navigation stacks.
4. Add temporary debug logging only if needed during diagnosis, then remove before final commit.

### Acceptance Criteria

- First-run setup on emulator advances to the main/account screen after matching PIN confirmation.
- Mismatched PIN still resets both PIN fields and shows the mismatch error.
- Secure-storage/create failure shows a visible user-safe error.
- No silent stuck state after the second PIN entry.
- Regression test covers the exact two-PIN setup flow.

### Tests

- Widget test: matching setup PIN twice routes to main/account screen.
- Widget test: mismatched setup PIN shows error and remains on setup.
- Widget test or unit test: controller failure during create is visible in setup UI.

---

## WP1 — Fix Vault Initialization Race

### Problem

`DiogelApp.build()` watches `vaultInitializationProvider` and immediately reads `vaultStateProvider`. `VaultController` initializes from the current `VaultService.state` before async service initialization is guaranteed to finish. There is no explicit refresh after `vaultInitializationProvider` completes.

**Observed risk:** an existing persisted vault can incorrectly render the setup flow instead of the unlock flow after app restart.

### Evidence

- `lib/app/app.dart`
  - `ref.watch(vaultInitializationProvider);`
  - `final vaultState = ref.watch(vaultStateProvider);`
- `lib/features/vault/application/vault_providers.dart`
  - `vaultInitializationProvider` calls `service.init()` separately from controller creation.
- `lib/features/vault/application/vault_controller.dart`
  - constructor snapshots `_vaultService.state`
  - `_init()` calls `_refreshState()` once only.

### Implementation Approach

Choose one of these and keep it consistent:

#### Recommended: move initialization ownership into controller/provider

- Remove the split responsibility between `vaultInitializationProvider` and `VaultController`.
- Add an explicit controller initialization path that calls service init and then refreshes controller state.
- Make initial controller state include `isLoading: true` until initialization completes.
- Expose a single provider the app can watch.

Suggested shape:

```dart
final vaultControllerProvider = StateNotifierProvider<VaultController, VaultControllerState>((ref) {
  final service = ref.watch(vaultServiceProvider);
  return VaultController(service)..initialize();
});
```

`VaultController.initialize()` should:

1. set loading true
2. call `VaultService.init()` where supported, or add `init()` to the `VaultService` interface
3. refresh state
4. set loading false
5. convert failures to `VaultFailure`

Then `DiogelApp` should render a loading/splash state while `state.isLoading` and no final vault state is ready.

### Acceptance Criteria

- Existing sentinel/store data renders `UnlockVaultScreen` after fresh app start.
- Empty store renders `SetupVaultScreen` after fresh app start.
- `vaultInitializationProvider` is either removed or no longer creates a race with controller state.
- No app build path can permanently show `NoVault` before persisted state is loaded.

### Tests

Add/adjust widget tests:

- Existing vault sentinel before `pumpWidget()` → expect unlock screen, not setup.
- Empty store before `pumpWidget()` → expect setup screen.
- Initialization failure → user sees safe error/loading state, not silent setup.

---

## WP2 — Align Security Claims With Implementation

### Problem

UI copy claims stronger security than currently implemented.

Current implementation:

- vault sentinel is a fixed string
- unlock accepts any PIN when sentinel exists
- `_sessionPin` is assigned but not used for verification or encryption
- private key payload is serialized into secure storage as JSON

Current UI claims include:

- PIN protects/encrypts keys
- AES-256
- hardware-backed vault / secure hardware element

That mismatch is risky because users will believe the PIN is cryptographically meaningful when it currently is not.

### Evidence

- `lib/features/vault/domain/vault_service_impl.dart`
  - `setSentinel('vault_exists')`
  - `unlock(String pin)` transitions to unlocked without verifying PIN
  - `_sessionPin` unused
- `lib/features/accounts/presentation/accounts_screen.dart`
  - claims AES-256 and secure hardware element
- `lib/features/accounts/presentation/widgets/import_identity_dialog.dart`
  - claims hardware-backed encrypted vault
- `lib/features/vault/presentation/setup_vault_screen.dart`
  - claims PIN encryption/protection

### Implementation Approach

For this pack, prefer truthful copy unless real crypto is being implemented now.

#### Option A — Recommended for this milestone: make copy truthful

Update UI copy to say:

- private keys are stored using the platform secure storage backend
- PIN/session handling is currently local app access control
- avoid claims of AES-256, hardware-backed vault, secure hardware element, or PIN-derived encryption unless implemented and verified

Example replacement copy:

> Private keys are stored locally using the device platform secure-storage backend. Diogel never syncs or uploads them.

For setup:

> Create a local access PIN for this app session. Stronger PIN-derived vault encryption is planned for a later hardening milestone.

Use this only if the product is comfortable showing that limitation.

#### Option B — Larger scope: implement real PIN verification and encryption

If implementing now, define and add:

- PIN KDF: Argon2id/scrypt/PBKDF2 with per-vault salt
- stored verifier, never raw PIN
- encryption key derived from PIN
- authenticated encryption for private key payloads
- migration story for existing plaintext `secretPayload`
- lock clears decrypted material
- tests for wrong PIN, migration, tampering, and duplicate import

Do **not** claim AES-256/hardware-backed unless the chosen library and platform path actually guarantee it.

### Acceptance Criteria

- UI copy does not overclaim implementation guarantees.
- `flutter analyze` has no new text/lint issues.
- Tests cover at least one copy-critical screen enough to catch regressions if assertions already exist.

---

## WP3 — Define Locked-State Metadata Policy

### Problem

`lock()` clears `_sessionPin` but keeps `_activeIdentity`. Controller also carries `activeIdentity` while locked. This does not expose private keys, but it leaves account metadata in memory/state after lock.

### Evidence

- `lib/features/vault/domain/vault_service_impl.dart`
  - `lock()` does not clear `_activeIdentity`
- `lib/features/vault/application/vault_controller.dart`
  - locked branch preserves `activeIdentity`

### Decision Needed

Pick one policy and document it in code/tests:

#### Recommended policy: locked means no account metadata in controller state

- `VaultServiceImpl.lock()` clears `_activeIdentity`.
- `VaultServiceImpl.expireSession()` clears `_activeIdentity`.
- `VaultController._refreshState()` sets `activeIdentity: null` and `identities: []` for `VaultLocked` and `SessionExpired`.
- Active identity ID remains persisted in store so it can be restored after successful unlock.

### Acceptance Criteria

- After lock/session expiry, controller state has:
  - empty identities
  - null active identity
  - no private or public account metadata in UI state
- After unlock, active identity is restored from persisted active identity ID.

### Tests

- Create vault + identity → lock → controller state clears identities and active identity.
- Unlock → active identity restored.
- Expire session → controller state clears identities and active identity.

---

## WP4 — Repair Failure Handling Between Controller and UI

### Problem

`SetupVaultScreen._createVault()` uses `try/catch`, but `VaultController.createVault()` catches exceptions internally and sets `state.failure` instead of throwing. That means setup failures may not show through the screen’s `_error` path.

### Evidence

- `lib/features/vault/presentation/setup_vault_screen.dart`
  - `_createVault()` expects exceptions
- `lib/features/vault/application/vault_controller.dart`
  - `createVault()` catches and stores `VaultFailure`

### Implementation Approach

Standardize on controller-state failures for UI.

- UI should call controller action.
- UI should read/watch `VaultControllerState.failure` after action.
- UI should map `VaultFailure` to display text.
- Avoid relying on exceptions crossing the controller boundary.

Recommended helper:

```dart
String vaultFailureMessage(VaultFailure failure) { ... }
```

Place it somewhere reusable, for example:

- `lib/features/vault/presentation/vault_failure_messages.dart`

Use the same mapper in:

- setup screen
- unlock screen
- import identity dialog
- account actions
- settings lock/update flows if relevant

### Acceptance Criteria

- Simulated store failure during create vault produces visible error text.
- Simulated invalid PIN / locked / duplicate / unsupported key failures produce visible messages where applicable.
- No UI screen expects controller methods to throw for known vault-domain failures.

### Tests

- Fake store throws on sentinel write → setup screen displays failure.
- Duplicate identity import → import dialog displays duplicate message and stays open.
- Locked mutation → account action displays locked/session failure where applicable.

---

## WP5 — Clean Analyzer and Dependency Issues

### Problem

`flutter analyze` currently fails. Some issues are trivial but block a clean quality gate.

### Known Issues

- unused `activeIdentity` in `AccountsScreen`
- unused `_navigateToMainNavigation` in `UnlockVaultScreen`
- unused `_sessionPin` in `VaultServiceImpl`
- direct import of `state_notifier` without declaring it as a direct dependency
- deprecated Riverpod/Flutter API usages reported by analyzer

### Implementation Approach

- Remove unused variables/methods where not needed.
- If direct `state_notifier` import is required, add `state_notifier` to `pubspec.yaml` dependencies.
- Prefer avoiding direct `state_notifier` import if Riverpod exports what is required.
- Replace deprecated APIs where straightforward.
- Run `flutter pub get` after dependency changes.

### Acceptance Criteria

- `flutter analyze` exits cleanly.
- `flutter test` remains passing.
- No new ignores are added unless justified in comments.

---

## WP6 — Test Reliability and Coverage Tightening

### Problem

The existing tests pass, but they did not catch the init race or controller/UI failure mismatch.

### Implementation Approach

Add focused regression tests for the actual failure modes rather than broad snapshot tests.

### Required Regression Tests

1. **App init with existing vault**
   - Given store sentinel exists before `DiogelApp` starts
   - Expect unlock screen
   - Expect setup screen absent

2. **App init with no vault**
   - Given empty store
   - Expect setup screen

3. **Lock clears metadata**
   - Given active identity exists
   - When lock/session expire
   - Expect controller state clears identity list and active identity

4. **Unlock restores active identity**
   - Given active identity persisted
   - When unlock succeeds
   - Expect active identity restored

5. **Setup failure visible**
   - Given store throws on create
   - When user creates vault
   - Expect visible error message

6. **Security-copy regression**
   - Avoid assertions requiring AES/hardware/PIN encryption copy unless real implementation exists.

---

## Recommended Commit Breakdown

1. `Fix vault initialization ownership and startup routing`
2. `Align vault security copy with current implementation`
3. `Clear locked vault identity metadata and restore after unlock`
4. `Surface controller failures in vault setup flow`
5. `Clean analyzer issues and dependency declarations`
6. `Add vault startup and lock-state regression tests`

---

## Final Verification Gate

Run from repo root:

```bash
flutter pub get
flutter analyze
flutter test
```

Expected result:

- analyze: clean
- test: all passing

If Flutter is not on PATH in the execution environment, use the local SDK path observed during review:

```bash
/root/develop/flutter/bin/flutter pub get
/root/develop/flutter/bin/flutter analyze
/root/develop/flutter/bin/flutter test
```

---

## Out of Scope Unless Explicitly Approved

- Full PIN-derived vault encryption
- Existing user-data migration
- Biometric unlock
- Hardware-backed key attestation claims
- Cloud backup/sync changes
- Public release copy beyond the vault/account screens touched above
