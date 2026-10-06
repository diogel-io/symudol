# Android Diogel

Android Diogel is a privacy-first Android signer and identity-security companion for Nostr.

Its purpose is simple: keep private keys on the phone, make signing requests understandable, and let users approve or reject actions with confidence.

## Application intent

Android Diogel exists to reduce private-key exposure.

The application is built around a strict trust model:

- sensitive signing material stays on the device;
- signing and decryption requests are shown clearly before approval;
- users can manage Nostr identities without handing raw private keys to every client;
- client trust and request provenance should be explicit, not guessed;
- convenience must not silently weaken key safety.

Android Diogel is not intended to be a full Nostr social client, a generic crypto wallet, or a bloated all-purpose app. It is intended to be a focused mobile signer that does a small number of security-critical jobs well.

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
- `Nip55ContentProviderTest`: what the provider signs in the background, for which caller and
  which remembered decision, including a request for another account (`current_user`) and an
  event without an integer `kind`. It verifies signatures.

A NIP-55 security change adds its attack case here, and checks it fails on the code before the
fix. The fake caller is a package installed with `shadowOf(packageManager).installPackage(...)`
(give it a `SigningInfo` as well as `signatures`), called with `setCallingPackage(...)`.

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
