# Biometric Unlock — Decision

Decided 2026-10-20 in diogel-io/symudol#23, for 1.0.0. Meets security requirement SR-29 (workspace
`10-products/symudol/requirements/security/signer-security-requirements.md`). iOS (Face ID) comes
with the iOS ticket.

## What It Is

Biometric unlock is opt-in, in Settings → Biometric Unlock. It's a second wrap of the vault's DEK,
next to the PIN's Argon2id wrap (`pin-protection.md`, "Key Envelope and Migration"):

- **The key.** An AES-256-GCM key in the Android Keystore, alias `symudol_biometric_dek_wrap`
  (`BiometricVault.kt`). It needs a strong biometric for every use
  (`setUserAuthenticationRequired`, and `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)`
  on API 30+, per-use auth below it). The screen-lock PIN doesn't count. Adding a fingerprint
  invalidates it (`setInvalidatedByBiometricEnrollment`).
- **The check is the Keystore's.** `BiometricPrompt` gets the key's cipher as its `CryptoObject`,
  and the cipher only works once the user has authenticated. A yes from a dialog alone can't use
  the key.
- **The wrap.** The GCM IV and ciphertext are stored as `vault_biometric_wrap` in
  `flutter_secure_storage`, which is excluded from backup (#15). The GCM tag guarantees that an
  unwrap returns exactly the DEK that was wrapped, and the DEK only changes on a wipe, which deletes
  the wrap.

The DEK crosses the method channel only in `wrap` and `unwrap`. Native code zeroes its copies once
they're handed over, and nothing about them is logged (SR-21).

## When the PIN Is Still Needed

The PIN stays the root of the vault:

- **To turn it on.** Settings asks for the current PIN, checked like an unlock (charged, honours the
  lockout, counts towards wipe-after-N), then shows the system prompt. Someone holding an unlocked
  phone can't add a biometric path without the PIN.
- **After a phone restart.** Every successful PIN check records `vault_pin_verified_at` on the
  monotonic clock (boot count plus elapsed time, as the lockout uses). A different boot count asks
  for the PIN.
- **72 hours after the last PIN check.** A biometric unlock doesn't renew it. App restarts don't
  count: Android kills background apps often, and asking for the PIN each time would leave
  biometrics rarely usable.

Changing the PIN re-wraps the same DEK, so biometric unlock keeps working, and the change counts as
a PIN check.

## PIN Lockout

A successful biometric unlock is allowed during a PIN lockout. It clears the failed-PIN count and
the lockout, as a correct PIN does, so someone guessing PINs can't lock the owner out. It also
resets the count towards the wipe-after-N limit. A strong biometric proves the owner as well as the
PIN does. Android's own biometric lockout, after too many wrong fingers, sends the user to the PIN.

## When the Key Is Lost

Keystore keys can be lost after some OS updates or lock-screen changes, and adding a fingerprint
invalidates this one by design. Either way the unlock fails with `keyInvalidated`. Symudol then
deletes the wrap and the key, turns biometric unlock off, and says so on the unlock screen. The PIN
still works and nothing else is lost.

That is why this doesn't reverse "No Keystore Binding for the KEK" in `pin-protection.md`. There,
a lost Keystore key would have locked the vault for good. Here it only loses a convenience.

## Wipe

A wipe, whether from Settings, Forgot PIN or too many failed PINs, deletes the key in its own wipe
step, and `clearAll` removes the wrap and `vault_pin_verified_at`. A new vault starts with biometric
unlock off.

## What It Doesn't Do

- It unlocks the vault, nothing more. A NIP-55 or NIP-46 request still goes through review after
  an unlock (threat model T15).
- Only `BIOMETRIC_STRONG` is accepted; the phone's screen-lock PIN is not a stand-in.
- Biometrics are weaker than a PIN against someone who forces the owner's finger. The restart and
  72-hour rules bound that, and the feature is opt-in. The threat model records it.
