# NIP-55 ContentProvider MVP

This pass adds the Android ContentProvider entry points required by NIP-55, but deliberately keeps provider signing disabled until the Flutter vault/policy/signing path can be safely invoked from a provider call.

## Implemented

- Exported `Nip55ContentProvider` authorities:
  - `io.threenine.androidiogel.SIGN_EVENT`
  - `io.threenine.androidiogel.NIP44_ENCRYPT`
  - `io.threenine.androidiogel.NIP44_DECRYPT`
  - `io.threenine.androidiogel.NIP04_ENCRYPT`
  - `io.threenine.androidiogel.NIP04_DECRYPT`
  - `io.threenine.androidiogel.DECRYPT_ZAP_EVENT`
- `SIGN_EVENT` projection decoding for event JSON and `current_user`.
- NIP-55-shaped cursor helpers for `result` + lowercase `event`.
- Safe null behavior when no remembered provider permission exists.
- Native reject cursor hook for future mirrored reject grants.

## Deferred intentionally

Provider auto-signing is not enabled yet because the private-key and approval-policy implementation currently live in Dart/Flutter. A ContentProvider may be called while the Flutter engine is cold, and duplicating vault unlock, identity matching, signing, and signature verification native-side would weaken the trust boundary.

Next provider phase should either:

1. spin up a headless Flutter engine and call the existing Dart policy/signing code, or
2. maintain a narrow native provider session cache populated only after an unlocked, reviewed Flutter approval.

Until then, provider queries return `null` unless a native mirrored reject decision is present. This matches NIP-55's safe behavior for missing remembered permission and avoids surprise UI launches or cold native signing.
