# NIP-55 Device Checks

Status: active

Tracking issue: diogel-io/symudol#69

## Why A Test Client

Some NIP-55 behaviour can only be shown on a device, by a **separate app** making real requests.
Caller identity is the main example. `adb shell am start` comes from the shell, not from an app
with its own package and certificate, so it cannot stand in for a client. Amethyst can, but on an
emulator it is hard to set up and often crashes.

`tools/nip55-test-client/` is a small Android app with its own package
(`io.diogel.nip55testclient`) and its own test-only signing key (`keystore/README.md`). It makes
the requests a client makes. Each scenario decides its own verdict and logs one line under the
logcat tag `Nip55Test`:

```text
RESULT <scenario> PASS|FAIL <reason>
```

`nip55_device_check.sh` installs both apps, starts every scenario through `adb`, reads those lines,
and prints a summary. The JVM tests (`android/app/src/test`, #68) remain the first line: they run
in CI. These checks are for what the JVM cannot show.

## Run It

Needs `adb`, an attached device or a running emulator, and either a Flutter and Android SDK to
build both APKs or prebuilt APKs.

```bash
./nip55_device_check.sh
```

| Option | Effect |
|--------|--------|
| `--symudol-apk PATH` | Install this Symudol APK instead of building one. |
| `--client-apk PATH` | Install this test-client APK, for example the CI artifact, instead of building one. |
| `--keep-data` | Don't clear Symudol's data first. Grants from an earlier run remain, so `provider_before_grant` can fail. |
| `--yes` | Don't ask before clearing Symudol's data. |
| `--only SCENARIO` | Run only this scenario. Repeatable. |
| `ADB_DEVICE=<serial>` | Target one device when several are attached. |

By default the script **clears Symudol's data**, including identities and grants, so every run
starts with no grants. Use a test device or emulator.

### It Is Semi-Attended

Remembered grants and an unlocked vault need a person in Symudol's UI. The script:

1. asks you to create or import an identity in Symudol and unlock it;
2. before each scenario, prints what to do in Symudol, for example "approve and remember";
3. waits for the scenario's verdict, up to its timeout.

Scenarios with nothing to approve run on their own.

## Scenarios

Run in this order. The provider checks after a grant use the grants the intent scenarios
remember.

| Scenario | Transport | You do | Passes when |
|----------|-----------|--------|-------------|
| `provider_before_grant` | ContentProvider | nothing | no method answers before any grant |
| `provider_broad_grant` (#5) | intent, then provider | approve the login with "sign any event", and remember | a kind-9999 `sign_event` is still not answered in the background |
| `intent_get_public_key` | `nostrsigner:` intent | approve and remember | a 64-hex key returns, from package `io.diogel.symudol` |
| `intent_sign_event` | intent | approve and remember kind 1 | the event comes back signed by that key, with an id that hashes its fields |
| `intent_sign_message` | intent | approve and remember | a 128-hex signature returns |
| `intent_nip44_round_trip` | intent | approve and remember both | decrypting the ciphertext returns the plaintext |
| `intent_nip04_round_trip` | intent | approve and remember both | as above, NIP-04 |
| `intent_reject` | intent | reject the kind 7 reaction, without remembering | `RESULT_OK` with a Boolean `rejected` set to `true`, the request `id`, and no `result` (NIP-55) |
| `provider_after_grant` | ContentProvider | nothing, keep Symudol unlocked | every remembered method answers, with correct results |
| `provider_columns` (#19) | ContentProvider | nothing, keep Symudol unlocked | every answer, including `nip44_decrypt` and `nip04_decrypt` of a remembered encrypt's ciphertext, has `signature`, `result` and `event`; `get_public_key` also has `package` |
| `provider_bound` (#18) | ContentProvider | nothing, keep Symudol unlocked | every query answers within 750 ms (the 500 ms bound plus IPC), including an unremembered kind |
| `provider_decrypt_zap_event` | provider, then intent, then provider | approve the zap decryption and remember it | a private zap made with the remembered `nip04_encrypt` decrypts to the plaintext, by intent and then by provider |
| `intent_sign_message_event_serialisation` (#8) | intent | nothing | an event serialisation sent as a message is not signed |
| `provider_sign_message_event_serialisation` (#8) | ContentProvider | nothing | as above, through the provider, with a `sign_message` grant |
| `intent_forged_identity` (#7) | explicit start of `MainActivity` | nothing; approve if asked (see below) | no answer within 30 s |
| `browser_callback` | browser-style intent with `callbackUrl` | approve | Symudol opens `nip55testclient://callback?event=<signature>` |

The client checks a signed event's shape, its key and that its id is the hash of its fields. It
does not verify the Schnorr signature itself: Symudol's vault service verifies every signature
before returning it (`nip55-native-crypto-decision.md`).

### Forged Identity (#7)

The client starts `io.diogel.symudol.MainActivity` directly, not through the `nostrsigner:` bridge.
Its extras claim the request comes from Amethyst (`callingPackage`, `callerCertificateSha256`).
Since #67, `MainActivity` accepts a request only from its own bridge, so nothing happens and the
scenario passes after 30 s.

Before #67, Symudol took the caller from those extras and answered whoever started it. To show
that the scenario catches the bug, run it against a build from before the fix:

```bash
git worktree add ../symudol-pre-67 5ca0362^1   # master just before #67 merged
(cd ../symudol-pre-67 && flutter build apk --debug)
./nip55_device_check.sh --symudol-apk ../symudol-pre-67/build/app/outputs/flutter-apk/app-debug.apk \
  --only intent_get_public_key --only intent_forged_identity
git worktree remove ../symudol-pre-67
```

On that build Symudol asks to share the key with Amethyst. Approve it, as a user who trusts
Amethyst would, and the scenario fails: the answer goes to the test client.

## Devices

### Emulator

Use an x86_64 **Google APIs** system image with hardware acceleration. On Linux that means KVM:

```bash
emulator -accel-check                      # should report KVM is installed and usable
sdkmanager "system-images;android-35;google_apis;x86_64"
avdmanager create avd -n symudol-nip55 -k "system-images;android-35;google_apis;x86_64"
emulator -avd symudol-nip55 -no-snapshot
```

`-no-snapshot` boots cold and saves no snapshot. Stale snapshots and locks are the usual cause of
an emulator that won't boot. If one still fails, run `./fix_emulators.sh`.

### USB Phone

Turn on developer options and USB debugging, connect, and accept the debugging prompt. Check
`adb devices` lists it. If more than one device is attached, set `ADB_DEVICE`.

### Firebase Test Lab

Not supported for this suite. Test Lab runs instrumentation and Robo tests, and these scenarios
need a person to approve in Symudol, with the script reading logcat as it goes. Test Lab can still
show that both APKs install and the client starts on a range of devices, for example with
`gcloud firebase test android run --type robo --app <client.apk>`.

## Real Clients

The test client covers Symudol's side of the protocol. Before a release, check the real clients
too: Amethyst, Dark Wisp and Nostria. The procedure, the client versions and the latest results
matrix are in [`nip55-client-interop.md`](nip55-client-interop.md) (diogel-io/symudol#87).

## CI

CI builds the test client and uploads `nip55-test-client-apk` with each run. Use it with
`--client-apk`. Nothing here runs an emulator in CI.
