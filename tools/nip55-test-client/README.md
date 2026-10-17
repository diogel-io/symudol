# NIP-55 Test Client

A minimal Android app that makes real NIP-55 requests to Symudol: intents, ContentProvider
queries, a forged-identity start of `MainActivity`, and the browser `callbackUrl` flow. It replaces
Amethyst for routine device checks (diogel-io/symudol#69).

It is a standalone Gradle project, not a Flutter module, so it has its own package
(`io.diogel.nip55testclient`) and signing key (`keystore/README.md`), as any other client would.

Run it through `../../nip55_device_check.sh`. What it checks and how to run it:
`../../documentation/nip55-device-checks.md`.

## Build

```bash
./gradlew assembleDebug testDebugUnitTest lintDebug
```

The APK is `app/build/outputs/apk/debug/app-debug.apk`. CI builds it in
`ghcr.io/cirruslabs/flutter:3.44.0`, the image Symudol's own checks use.

## Layout

| File | Purpose |
|------|---------|
| `ScenarioActivity.kt` | One button per scenario, and the `adb` entry point (`--es scenario <id>`). |
| `Scenarios.kt` | Every scenario and its pass criteria, in run order. |
| `Results.kt` | The running scenario, and its single `RESULT` line under logcat tag `Nip55Test`. |
| `Signer.kt` | Building `nostrsigner:` intents and querying the ContentProvider. |
| `CallbackActivity.kt` | Receives the browser flow's `nip55testclient://callback?event=`. |
| `Nostr.kt` | NIP-01 serialisation and event checks, tested on the JVM. |

A new scenario goes in `Scenarios.all` and in `SCENARIOS` in the script, at the same position.
