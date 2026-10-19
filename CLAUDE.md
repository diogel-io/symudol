# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Symudol is a privacy-first Nostr signer and identity-security companion app, built with Flutter (Android as primary target). It implements NIP-55 (Android Signer Application) for clients on the same phone and NIP-46 (Nostr Remote Signing) for clients reached over relays, so other Nostr clients can request key operations (get_public_key, sign_event, NIP-04/NIP-44 encrypt/decrypt) without ever seeing the private key.

The core trust model: keep signing material on-device, make every approval explicit, support multiple identities, and avoid scope creep beyond a serious signer. Prefer small bounded changes over large rewrites — see `README.md` for full product framing.

## Commands

- `flutter pub get` — install dependencies
- `flutter analyze` — static analysis (uses `flutter_lints`, see `analysis_options.yaml`)
- `flutter test` — run all tests
- `flutter test test/features/<path>/<file>_test.dart` — run a single test file
- `flutter test --plain-name "<test name>"` — run a single test by name
- `flutter run` — run the app on a connected device/emulator
- `./fix_emulators.sh` — fixes stale Android emulator locks/snapshot issues (run if emulators fail to boot)
- `./nip55_device_check.sh` — installs Symudol and the NIP-55 test client (`tools/nip55-test-client/`) on a device and runs every scenario; semi-attended, clears Symudol's data (see `documentation/nip55-device-checks.md`)
- `flutter build apk --config-only && (cd android && ./gradlew testDebugUnitTest)` — run the JVM tests for the Android-native code (`android/gradlew` is generated, not committed)

Android-native (Kotlin) code under `android/app/src/main/kotlin/io/diogel/symudol/` is tested with Robolectric in `android/app/src/test/java/io/diogel/symudol/` (see `README.md`, "Testing NIP-55 without a device"). CI (`.github/workflows/ci.yml`) runs analyze, the Flutter tests and the Gradle tests in the pinned `ghcr.io/cirruslabs/flutter:3.44.0` image; to reproduce it locally:

```bash
podman run --rm -v "$PWD:/app:Z" -w /app ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'flutter pub get && flutter analyze && flutter test && flutter build apk --config-only && cd android && ./gradlew testDebugUnitTest --console=plain'
```

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

`DiogelApp` (`lib/app/app.dart`) owns two independent session timers, both set in Settings:
- **inactivity timeout** — after N minutes with no user interaction while foregrounded, calls `VaultController.expireSession()` (state `SessionExpired`); 0 disables it
- **background lock delay** — locks after the app is backgrounded for N minutes (0 = immediate, -1 = never while running); the same deadline is passed to native code with `setLockDeadline`

Both are skipped/deferred while a NIP-55 request is in flight (`nip55ControllerProvider.hasPendingExternalRequest`), since approval flows bounce the user out to another app and back. The deferral is bounded: a pending review times out after 5 minutes, the lock is scheduled once the request settles, and the native key gets its own lock deadline (see `documentation/nip55-contentprovider-mvp.md`, "How Long the Native Key Lives").

### Identities & signing (lib/features/identity/, lib/features/signing/)

`VaultIdentity` equality is based on `publicKey` (not `localId`) — two identity records with the same pubkey are considered the same identity regardless of origin (`generated` vs `imported`). `DartNostrCryptoService` (lib/features/signing/data/) wraps `dart_nostr` for key derivation, Schnorr signing, and NIP-04/NIP-44 crypto.

### Requests (lib/features/requests/)

`SigningRequest` models an in-flight request from a client app, including `RequestProvenance` / `RequestTrustStatus` (how the request arrived and how trustworthy that channel is). `RequestController` manages the lifecycle of the request shown in `ApprovalScreen` (the "Requests" tab of `MainNavigationScreen`). `RealSignerService` performs actual signing via the vault/crypto service; `FakeSignerService` exists for tests/dev.

### NIP-55 (lib/features/nip55/) — the most involved subsystem

This feature bridges Android-native IPC (intents + ContentProvider) to the Flutter signing/approval flow. Key pieces:

- **Transport-side (Android/Kotlin)**: `android/app/src/main/kotlin/io/diogel/symudol/`
  - `MainActivity.kt` hosts the Flutter engine and receives a NIP-55 request from the bridge as a token only (`singleTop`)
  - `Nip55ContentProvider.kt` exposes content authorities (`io.diogel.symudol.GET_PUBLIC_KEY`, `SIGN_EVENT`, etc.) for warm/background calls when permission is already remembered
  - `Nip55BridgeActivity.kt` owns the `nostrsigner:` intent filter, attests the caller from Android (`callingPackage` and its certificate) and registers the request in `Nip55Handoff.kt` under an unguessable token; MainActivity receives only that token. `Nip55RequestRouter.kt` makes sure an answer only ever goes to the bridge that owns the request. `Nip55BridgeRegistry.kt`, `Nip55RequestCodec.kt`, `Nip55UriParser.kt` and `Nip55ProviderBridge.kt` (ContentProvider → Dart) handle tokens, result ownership and parsing. These rules are enforced by `Nip55BridgeActivityTest`, `Nip55HandoffTest` and `Nip55RequestRouterTest`.
  - One review at a time: while a request is being reviewed, `Nip55Controller.handleRawIntent` completes a second request if a remembered decision covers it, defers one that could still be completed automatically (`_shouldDeferClientAuthenticationRequest`), and otherwise rejects it through its own token, without touching the active request.
  - `Nip55PermissionMirror.kt` / `Nip55CryptoBridge.kt` / `Nip55NativeCrypto.kt` mirror permission/crypto state to native so the ContentProvider can answer NIP-04/NIP-44 encrypt/decrypt without waking the Flutter engine

- **Dart side**: `Nip55Controller` (application) consumes pending native intents on app start (`consumePendingNativeIntent`, called from `DiogelApp.initState`), maps incoming requests via `Nip55RequestMapper`, and resumes pending requests after vault unlock (`isWaitingForUnlock` / `resumePendingAfterUnlock`).
  - `Nip55PermissionController` + `Nip55PermissionStore` (`SecureStorageNip55PermissionStore`) manage per-app, per-scope "remembered" permission decisions, kept in sync with native via `Nip55NativeMirrorSync` (cross-scope grant matching — see commit history for `decrypt_zap_event` rememberable behavior).
  - `Nip55ApprovalPolicy` decides whether a request can be auto-approved (remembered permission) or needs manual review.
  - `Nip55ResponseBuilder` formats results back to the native layer; `Nip55IntentParser` / `Nip55PermissionParser` parse incoming intent extras and permission requests.

Native code must NOT sign — `sign_event` and `sign_message` go through `Nip55ProviderBridge` to Dart/`VaultService`, which verifies every signature (decision record: `documentation/nip55-native-crypto-decision.md`, diogel-io/symudol#12). Native handles transport metadata, request tokens, result ownership, and safe cancellation, plus NIP-04/NIP-44 ECDH for remembered encrypt/decrypt, which runs only while `Nip55NativeCrypto.selfTestPassed`. Background-launch restrictions (`BAL_BLOCK`) on Android 10+ are a known source of NIP-55 timeout issues; see `AGENTS.md` for the relevant Android IPC docs (intents, ContentProvider, package visibility, background activity launches).

### NIP-46 (lib/features/nip46/)

Remote signing over relays, entirely in Dart. A connection starts from a `bunker://` token Symudol generates or a `nostrconnect://` token a client offers (`Nip46TokenCodec`, `Nip46ConnectionQrSheet`); the user approves it in `Nip46ConnectApprovalScreen` and manages connections in `Nip46ConnectionsScreen` (from Settings).
- `Nip46Controller` handles each request from `DartNip46RelayService` (relay subscriptions; `DartNip46Crypto` decrypts requests and encrypts responses with NIP-44, or NIP-04 for older clients) and signs through `VaultService`.
- `Nip46ApprovalPolicy` decides between auto-approve and review per session and `Nip46PermissionScope`; `Nip46Session`s persist in `SecureStorageNip46SessionStore`.
- Methods: `Nip46Method` (connect, get_public_key, ping, sign_event, NIP-04/NIP-44 encrypt/decrypt, switch_relays, get_relays, logout, decrypt_zap_event).

Relevant NIPs: NIP-01 (basic protocol), NIP-04/NIP-44 (encryption), NIP-46 (remote signing, `lib/features/nip46/`), NIP-49 (key encryption), NIP-55 (Android signer — primary spec for the NIP-55 feature).

## Design docs

`documentation/` contains the decision records. Check them before changing NIP-55 transport or native-key behavior:
- `nip55-contentprovider-mvp.md` — what the ContentProvider answers in the background, and how long the native key lives
- `nip55-native-crypto-decision.md` — why native code does not sign (diogel-io/symudol#12)
- `backup-and-screen-capture-decision.md` — why nothing is backed up or transferred, and why the whole app blocks screen capture (diogel-io/symudol#15)
- `nip55-signer-discovery.md` — how clients discover Symudol as a signer
- `nip55-client-discovery-reference.md` — how known clients look for a signer
- `nip55-device-checks.md` — running the NIP-55 device checks with the test client
- `releasing.md` — the release PR, versions and build numbers, and how a release is cut

`nip55_device_check.sh` runs the NIP-55 checks on a device.