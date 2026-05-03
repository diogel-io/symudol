# NIP-55 ContentProvider warm-session support

Status: **warm-session ContentProvider support**, not cold background signing.

The Android ContentProvider entry points now fail closed by default, but can execute NIP-55 operations when the existing Flutter/UI engine is alive, the vault is unlocked, and the shared Dart approval policy finds a remembered allow grant inside the active approval session.

This deliberately avoids native private-key duplication and avoids launching UI from a provider. A cold provider call still returns `null`.

## Implemented

- Exported `Nip55ContentProvider` authorities:
  - `io.threenine.androidiogel.SIGN_EVENT`
  - `io.threenine.androidiogel.NIP44_ENCRYPT`
  - `io.threenine.androidiogel.NIP44_DECRYPT`
  - `io.threenine.androidiogel.NIP04_ENCRYPT`
  - `io.threenine.androidiogel.NIP04_DECRYPT`
  - `io.threenine.androidiogel.DECRYPT_ZAP_EVENT`
- Projection shape validation for every declared provider method:
  - `SIGN_EVENT`: event JSON + `current_user`
  - `NIP04_ENCRYPT` / `NIP04_DECRYPT`: payload + peer pubkey + `current_user`
  - `NIP44_ENCRYPT` / `NIP44_DECRYPT`: payload + peer pubkey + `current_user`
  - `DECRYPT_ZAP_EVENT`: zap event payload + `current_user`
- Provider queries bridge synchronously to the warm Flutter engine through `Nip55ProviderBridge` with a short timeout.
- Dart handles provider requests through the same parser, approval policy, vault, signing, and crypto services used by manual NIP-55 requests.
- Successful provider responses return NIP-55-shaped cursors:
  - `SIGN_EVENT`: `result`, `event`
  - crypto/decrypt operations: `result`
  - remembered reject: `rejected`
- Provider never starts an activity.
- Provider returns `null` when:
  - Flutter/UI engine is not attached
  - request times out or errors
  - vault is locked
  - no remembered allow grant matches
  - approval session is absent/expired
  - caller package/certificate/current_user/event pubkey validation fails

## Security model

- Private key material remains in Dart/vault code; it is not persisted or mirrored to native provider code.
- Provider caller identity is passed as package + signing certificate hash and evaluated by the existing Dart permission policy.
- Browser flows still must not receive remembered app grants.
- Sensitive decrypt scopes remain blocked from normal remembered/session auto-approval unless a later explicit-sensitive-grant design is added.

## Deferred intentionally

This is not cold-start ContentResolver support. A provider call while the app process/Flutter engine is cold still returns `null`. Full cold background support would need a reviewed architecture such as a headless Flutter service/session model or a very narrow native session cache. Do not duplicate long-lived signing capability natively without a separate security review.
