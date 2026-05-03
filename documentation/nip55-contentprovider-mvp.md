# NIP-55 ContentProvider deferral status

Status: **deferred safe stub**, not a complete background signing implementation.

This pass adds the Android ContentProvider entry points required by NIP-55, but deliberately keeps provider signing disabled until the Flutter vault/policy/signing path can be safely invoked from a provider call.

Important: Dart stores remembered permissions in Flutter secure storage under `nip55_permission_grants_v1`. The current native provider does not read that store and does not mirror allow grants. It must therefore be treated as a structural entry-point stub only.

## Implemented

- Exported `Nip55ContentProvider` authorities:
  - `io.threenine.androidiogel.SIGN_EVENT`
  - `io.threenine.androidiogel.NIP44_ENCRYPT`
  - `io.threenine.androidiogel.NIP44_DECRYPT`
  - `io.threenine.androidiogel.NIP04_ENCRYPT`
  - `io.threenine.androidiogel.NIP04_DECRYPT`
  - `io.threenine.androidiogel.DECRYPT_ZAP_EVENT`
- `SIGN_EVENT` projection decoding for event JSON and `current_user`.
- Projection shape validation for every declared provider method:
  - `SIGN_EVENT`: event JSON + `current_user`
  - `NIP04_ENCRYPT` / `NIP04_DECRYPT`: payload + peer pubkey + `current_user`
  - `NIP44_ENCRYPT` / `NIP44_DECRYPT`: payload + peer pubkey + `current_user`
  - `DECRYPT_ZAP_EVENT`: zap event payload + `current_user`
- NIP-55-shaped cursor helpers for `result` + lowercase `event`.
- NIP-55-shaped cursor helper for non-signing operation `result` responses.
- Safe null behavior for all provider calls.
- Native reject cursor hook placeholder for future mirrored reject grants.

## Deferred intentionally

Provider auto-signing is not enabled yet because the private-key and approval-policy implementation currently live in Dart/Flutter. A ContentProvider may be called while the Flutter engine is cold, and duplicating vault unlock, identity matching, signing, and signature verification native-side would weaken the trust boundary.

Next provider phase should either:

1. spin up a headless Flutter engine and call the existing Dart policy/signing code, or
2. maintain a narrow native provider session cache populated only after an unlocked, reviewed Flutter approval.

Until then, provider queries return `null`. This matches NIP-55's safe behavior for missing remembered permission and avoids surprise UI launches or cold native signing. Do not describe WP5 as complete background approval/signing until one of the next-phase designs above is implemented and tested.
