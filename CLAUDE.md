# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Android Diogel is a privacy-first Nostr signer and identity-security companion app, built with Flutter (Android as primary target). It implements NIP-55 (Android Signer Application) so other Nostr clients can request key operations (get_public_key, sign_event, NIP-04/NIP-44 encrypt/decrypt) without ever seeing the private key.

The core trust model: keep signing material on-device, make every approval explicit, support multiple identities, and avoid scope creep beyond a serious signer. Prefer small bounded changes over large rewrites — see `README.md` for full product framing.

## Commands

- `flutter pub get` — install dependencies
- `flutter analyze` — static analysis (uses `flutter_lints`, see `analysis_options.yaml`)
- `flutter test` — run all tests
- `flutter test test/features/<path>/<file>_test.dart` — run a single test file
- `flutter test --plain-name "<test name>"` — run a single test by name
- `flutter run` — run the app on a connected device/emulator
- `./fix_emulators.sh` — fixes stale Android emulator locks/snapshot issues (run if emulators fail to boot)

For Android-native (Kotlin) changes under `android/app/src/main/kotlin/io/diogel/symudol/`, build/verify via Gradle (`android/gradlew`) or by running the Flutter app on an Android target — there are no separate Dart tests for native code paths.

## Architecture

### Feature-first layered structure

Code lives under `lib/features/<feature>/`, each split into:
- `domain/` — entities, value objects, interfaces (pure Dart, no Flutter/IO deps)
- `application/` — Riverpod `StateNotifier`/controllers and provider wiring (`*_providers.dart`)
- `data/` — concrete implementations (secure storage, method channels, gateways)
- `presentation/` — screens and widgets

Providers are composed in `<feature>/application/*_providers.dart` and wired together in `lib/app/app.dart` (`DiogelApp`). Tests mirror this structure under `test/features/...`, using fakes in `test/fakes/` (e.g. `FakeVaultStore`) instead of mocking platform channels.

### Vault (lib/features/vault/)

The vault holds identities and is the gate for everything else. `VaultState` is a sealed-ish union: `NoVault`, `VaultLocked`, `SessionExpired`, `VaultUnlocked`. `VaultController` drives transitions; `VaultServiceImpl` + `SecureStorageVaultStore` (backed by `flutter_secure_storage`) persist identities and PIN-derived material.

`DiogelApp` (`lib/app/app.dart`) owns two independent session timers, documented in `documentation/vault-session-policy.md`:
- **inactivity timeout** — locks after no user interaction while foregrounded
- **background lock delay** — locks after the app is backgrounded for N minutes (0 = immediate, -1 = never while running)

Both are skipped/deferred while a NIP-55 request is in flight (`nip55ControllerProvider.hasPendingExternalRequest`), since approval flows bounce the user out to another app and back. The deferral is bounded: a pending review times out after 5 minutes, the lock is scheduled once the request settles, and the native key gets its own lock deadline (see `documentation/nip55-contentprovider-mvp.md`, "How Long the Native Key Lives").

### Identities & signing (lib/features/identity/, lib/features/signing/)

`VaultIdentity` equality is based on `publicKey` (not `localId`) — two identity records with the same pubkey are considered the same identity regardless of origin (`generated` vs `imported`). `DartNostrCryptoService` (lib/features/signing/data/) wraps `dart_nostr` for key derivation, Schnorr signing, and NIP-04/NIP-44 crypto.

### Requests (lib/features/requests/)

`SigningRequest` models an in-flight request from a client app, including `RequestProvenance` / `RequestTrustStatus` (how the request arrived and how trustworthy that channel is). `RequestController` manages the queue/lifecycle of requests shown in `RequestsScreen`. `RealSignerService` performs actual signing via the vault/crypto service; `FakeSignerService` exists for tests/dev.

### NIP-55 (lib/features/nip55/) — the most involved subsystem

This feature bridges Android-native IPC (intents + ContentProvider) to the Flutter signing/approval flow. Key pieces:

- **Transport-side (Android/Kotlin)**: `android/app/src/main/kotlin/io/diogel/symudol/`
  - `MainActivity.kt` receives `nostrsigner:` intents (`singleTop`)
  - `Nip55ContentProvider.kt` exposes content authorities (`io.diogel.symudol.GET_PUBLIC_KEY`, `SIGN_EVENT`, etc.) for warm/background calls when permission is already remembered
  - `Nip55BridgeActivity.kt`, `Nip55ProviderBridge.kt`, `Nip55BridgeRegistry.kt`, `Nip55RequestCodec.kt`, `Nip55UriParser.kt` handle request token assignment, result ownership, and parsing — see `documentation/nip55-bridge-activity-design.md` for the concurrency model (strict single-flight; a second concurrent caller must be rejected by its own bridge instance without touching the active request)
  - `Nip55PermissionMirror.kt` / `Nip55CryptoBridge.kt` / `Nip55NativeCrypto.kt` mirror permission/crypto state to native so the ContentProvider can answer without waking the Flutter engine

- **Dart side**: `Nip55Controller` (application) consumes pending native intents on app start (`consumePendingNativeIntent`, called from `DiogelApp.initState`), maps incoming requests via `Nip55RequestMapper`, and resumes pending requests after vault unlock (`isWaitingForUnlock` / `resumePendingAfterUnlock`).
  - `Nip55PermissionController` + `Nip55PermissionStore` (`SecureStorageNip55PermissionStore`) manage per-app, per-scope "remembered" permission decisions, kept in sync with native via `Nip55NativeMirrorSync` (cross-scope grant matching — see commit history for `decrypt_zap_event` rememberable behavior).
  - `Nip55ApprovalPolicy` decides whether a request can be auto-approved (remembered permission) or needs manual review.
  - `Nip55ResponseBuilder` formats results back to the native layer; `Nip55IntentParser` / `Nip55PermissionParser` parse incoming intent extras and permission requests.

Native code must NOT perform signing or private-key access — that stays in Dart/`VaultService`. Native handles transport metadata, request tokens, result ownership, and safe cancellation only. Background-launch restrictions (`BAL_BLOCK`) on Android 10+ are a known source of NIP-55 timeout issues; see `AGENTS.md` for the relevant Android IPC docs (intents, ContentProvider, package visibility, background activity launches).

Relevant NIPs: NIP-01 (basic protocol), NIP-04/NIP-44 (encryption), NIP-46 (remote signing, not used here), NIP-49 (key encryption), NIP-55 (Android signer — primary spec for this feature).

## Design docs

`documentation/` contains decision records that are the source of truth for in-progress design questions (NIP-55 bridge activity design, batch/single-flight decisions, content provider MVP, manual verification steps, vault session policy). Check these before changing session-timer or NIP-55 transport behavior.