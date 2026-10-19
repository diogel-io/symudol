# NIP-55 Client Interoperability

Status: active

Tracking issue: diogel-io/symudol#87

Symudol 1.0.0 must sign for the three Android Nostr clients it targets: Amethyst, Dark Wisp and
Nostria. This is the repeatable procedure for checking that on an emulator, and the record of the
latest run.

The test client (`nip55-device-checks.md`) checks Symudol's side of the protocol and runs first.
This procedure checks what only the real clients can show: that each one logs in, signs, encrypts
and handles a rejection the way it is written.

## What Each Client Uses

From each client's source, at the versions below:

| | Amethyst | Dark Wisp | Nostria |
|---|---|---|---|
| Methods | `get_public_key`, `sign_event`, `nip04_encrypt`, `nip04_decrypt`, `nip44_encrypt`, `nip44_decrypt`, `decrypt_zap_event` | `get_public_key`, `sign_event`, `nip44_encrypt`, `nip44_decrypt` | `get_public_key`, `sign_event`, `nip04_encrypt`, `nip04_decrypt`, `nip44_encrypt`, `nip44_decrypt` |
| Path | provider first, intent when it returns `null` | provider first, intent when it returns `null` | provider first, intent when it returns `null` |
| `current_user` | hex | npub | hex |
| Reads | `result`, `event`, `package`, `id`, `rejected` | `event`, then `signature`, then `result` | `result`, `event`, `package`, `id` |
| On a rejection | expects `RESULT_OK` with `rejected` | reads `RESULT_OK` with `rejected` as success with an empty signature | treats any non-OK result as rejected |

None of them uses `sign_message`, batch `results` or `callbackUrl`. Where a client never calls a
method, the matrix records "not used".

Symudol answers a user rejection with NIP-55's `RESULT_OK` and a Boolean `rejected` extra, and a
signer failure (busy, malformed request, timeout) with `RESULT_CANCELED`. Every provider answer
carries `signature`, `result` and `event`, and `get_public_key` adds `package`
(`nip55-contentprovider-mvp.md`).

## Set Up

### Emulator

Use an x86_64 Google APIs image with KVM, as in `nip55-device-checks.md`:

```bash
emulator -avd symudol-nip55 -no-snapshot
```

Amethyst often crashes on emulators. If it does, run Amethyst on a USB phone instead and record
the device in the matrix.

### Symudol

Install the build under test and note its commit:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
git rev-parse --short HEAD
```

Create or import an identity, and unlock the vault.

### The Clients

Download each APK from the project's own GitHub releases. Record its SHA-256 in the matrix, and
never commit the files.

| Client | Version | Release | APK |
|--------|---------|---------|-----|
| Amethyst | 1.19.0 | <https://github.com/vitorpamplona/amethyst/releases> | `amethyst-fdroid-x86_64-v1.19.0.apk` |
| Dark Wisp | 1.2.5 | <https://github.com/barrydeen/dark-wisp-android/releases> | `app-release.apk` |
| Nostria | 4.1.77 | <https://github.com/nostria-app/nostria/releases> | `Nostria_4.1.77.apk` |

```bash
sha256sum <apk>
adb install -r <apk>
```

To test a newer client version, update this table and run the whole procedure again.

## Checks

Run every step for each client in turn. Follow the provider path in logcat:

```bash
adb logcat -s Diogel-ContentProvider
```

A provider answer shows as a `query:` line with no Symudol screen. An intent opens Symudol's
review screen.

1. **Login.** Log in to the client with Symudol (the client's "Login with Amber" or "external
   signer" option). Approve the public key in Symudol. The client must show the same public key
   as Symudol's active identity.
2. **Intent path.** For every method the client uses, trigger it with nothing remembered and
   approve it once in Symudol, without remembering. The action must complete in the client.
3. **Provider path.** Repeat each action, approving with "remember" the first time. The next
   repeat must complete with no Symudol prompt, and logcat must show the provider answering.
4. **Rejection.** Trigger a new action and reject it in Symudol. The client must not post, sign or
   decrypt anything, and must not crash. Note what it shows.

### Actions Per Client

| Client | Actions |
|--------|---------|
| Amethyst | post a note; react to a note; send and read a NIP-04 direct message; send and read a NIP-17 direct message (NIP-44); open a private zap (`decrypt_zap_event`) |
| Dark Wisp | post a note; react to a note; send and read a direct message (NIP-44) |
| Nostria | post a note; react to a note; send and read a direct message in each scheme it offers (NIP-04 and NIP-44) |

Nostria asks for an untyped `sign_event` permission at login. Symudol never remembers that
(diogel-io/symudol#5), so each new event kind prompts once until it is remembered. That is
expected.

## Results

Record pass, fail or not used for each client, method and path, with the Symudol commit, the
client versions and their SHA-256. Fix each failure in Symudol, or link the issue raised for it
in the 1.0.0 milestone. Raise a client's own defect upstream on that client and link it.

### Latest Run

Not run yet. The table below is filled in from the first run.

| Symudol commit | Device | Date |
|----------------|--------|------|
| | | |

| Client | Version | SHA-256 |
|--------|---------|---------|
| Amethyst | 1.19.0 | |
| Dark Wisp | 1.2.5 | |
| Nostria | 4.1.77 | |

| Method | Path | Amethyst | Dark Wisp | Nostria |
|--------|------|----------|-----------|---------|
| `get_public_key` (login) | intent | | | |
| `get_public_key` | provider | | | |
| `sign_event` | intent | | | |
| `sign_event` | provider | | | |
| `nip04_encrypt` | intent | | not used | |
| `nip04_encrypt` | provider | | not used | |
| `nip04_decrypt` | intent | | not used | |
| `nip04_decrypt` | provider | | not used | |
| `nip44_encrypt` | intent | | | |
| `nip44_encrypt` | provider | | | |
| `nip44_decrypt` | intent | | | |
| `nip44_decrypt` | provider | | | |
| `decrypt_zap_event` | intent | | not used | not used |
| `decrypt_zap_event` | provider | | not used | not used |
| Rejection | intent | | | |

| Failure | Issue |
|---------|-------|
| | |
