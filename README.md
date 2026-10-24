# Symudol

Symudol is a privacy-first Android signer and identity-security companion for Nostr, part of the Diogel suite.

Its purpose is simple: keep private keys on the phone, make signing requests understandable, and let users approve or reject actions with confidence.

## Application intent

Symudol exists to reduce private-key exposure.

The application is built around a strict trust model:

- sensitive signing material stays on the device;
- signing and decryption requests are shown clearly before approval;
- users can manage Nostr identities without handing raw private keys to every client;
- client trust and request provenance should be explicit, not guessed;
- convenience must not silently weaken key safety.

Symudol is not intended to be a full Nostr social client, a generic crypto wallet, or a bloated all-purpose app. It is intended to be a focused mobile signer that does a small number of security-critical jobs well.

## What Symudol supports

Clients reach Symudol in two ways. Either way, the client never sees the private key.

### NIP-55: clients on the same phone

[NIP-55](https://github.com/nostr-protocol/nips/blob/master/55.md) is the Android signer protocol
used by clients such as Amethyst and Primal.

- **`nostrsigner:` intents.** The client opens Symudol, the user reviews the request, and
  Symudol returns the result. Methods: `get_public_key`, `sign_event`, `sign_message`,
  `nip04_encrypt`, `nip04_decrypt`, `nip44_encrypt`, `nip44_decrypt` and `decrypt_zap_event`.
- **Background ContentProvider.** If the user chose to remember a decision for that app and the
  vault is unlocked, the client gets its answer in the background without Symudol opening.
  Otherwise the provider returns nothing and the client falls back to an intent.

Decision records:
[ContentProvider scope](documentation/nip55-contentprovider-mvp.md),
[why native code does not sign](documentation/nip55-native-crypto-decision.md),
[signer discovery](documentation/nip55-signer-discovery.md) and the
[client discovery reference](documentation/nip55-client-discovery-reference.md).

### NIP-46: remote clients over relays

[NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) lets a client on another
device ask Symudol to sign over Nostr relays. To connect, give the client a `bunker://` token
from Symudol, or paste the `nostrconnect://` URI the client shows. Connections are approved, listed
and revoked under **Settings → Remote Signer (NIP-46)**. A request that the connection's
remembered permissions don't cover waits for the user's review.

## Requirements

Install and configure:

- Flutter SDK
- Android SDK
- Android Studio or command-line Android tooling
- an Android emulator or physical Android device

Verify the local toolchain with:

```bash
flutter doctor
```

Resolve any Android/Flutter issues reported by `flutter doctor` before running the application.

## Install dependencies

From the repository root:

```bash
flutter pub get
```

## Run the application

List available devices:

```bash
flutter devices
```

Run on the selected emulator or connected Android device:

```bash
flutter run
```

Run a release build locally:

```bash
flutter run --release
```

## Test the application

Run static analysis:

```bash
flutter analyze
```

Run the Flutter test suite:

```bash
flutter test
```

Run both checks together:

```bash
flutter analyze && flutter test
```

### Testing NIP-55 without a device

The Android side of NIP-55 (the `nostrsigner:` bridge activity, request routing and the
background ContentProvider) is tested on the JVM with
[Robolectric](https://robolectric.org/), so its security behaviour is checked in CI with no
emulator or client app:

```bash
flutter build apk --config-only   # generates android/gradlew, which is not committed
cd android && ./gradlew testDebugUnitTest
```

- `Nip55BridgeActivityTest`: the caller is the one Android reports, whatever the intent's extras
  say; MainActivity receives only a token; URL-parameter (browser) requests; rate limiting.
- `Nip55RequestRouterTest`: MainActivity takes a request only from the bridge handoff, and
  answers only that bridge.
- `Nip55ContentProviderTest`: what the provider answers in the background, for which caller and
  which remembered decision, including a request for another account (`current_user`) and an
  event without an integer `kind`. Signing is never native: it is passed to Dart, which verifies
  every signature (`documentation/nip55-native-crypto-decision.md`).

A NIP-55 security change adds its attack case here, and checks it fails on the code before the
fix. The fake caller is a package installed with `shadowOf(packageManager).installPackage(...)`
(give it a `SigningInfo` as well as `signatures`), called with `setCallingPackage(...)`.

### Testing NIP-55 on a device

What the JVM can't show, such as a separate app's caller identity, is checked on a device or
emulator with a small test client (`tools/nip55-test-client/`). One command installs Symudol and
the client and runs every scenario, with a pass/fail summary:

```bash
./nip55_device_check.sh
```

It clears Symudol's data first and pauses when a scenario needs an approval in Symudol. See
`documentation/nip55-device-checks.md`.

## Releases

Releases are cut by merging the release-please release PR, `chore(release): <version>`. Write
Conventional Commits (`feat:`, `fix:`, `feat!:`), because they set the next version and the
changelog. See `documentation/releasing.md`.

## Build Android artifacts

Build a debug APK:

```bash
flutter build apk --debug
```

Build a release APK:

```bash
flutter build apk --release
```

Build a release Android App Bundle:

```bash
flutter build appbundle --release
```

Release builds require a correctly configured Android signing setup before they can be distributed safely.

### NIP-46 in release builds

Android 1.0 hides NIP-46 remote signing in release builds (#26): Settings has no Remote Signer
tile, so no NIP-46 relay connection is opened. Debug and profile builds keep it. To test it in a
release build, opt in explicitly:

```bash
flutter build apk --release --dart-define=SYMUDOL_ENABLE_NIP46=true
```

The flag is `kNip46Enabled` in `lib/features/nip46/application/nip46_feature.dart`.
