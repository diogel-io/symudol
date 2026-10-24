# Biometric Unlock — Decision

Decided 2026-10-20 in diogel-io/symudol#23, for 1.0.0. Meets security requirement SR-29 (workspace
`10-products/symudol/requirements/security/signer-security-requirements.md`). iOS (Face ID) comes
with the iOS ticket.

## What It Is

Biometric unlock is opt-in, in Settings → Biometric Unlock. It's a second wrap of the vault's DEK,
next to the PIN's Argon2id wrap (`pin-protection.md`, "Key Envelope and Migration"):

- **The key.** An AES-256-GCM key in the Android Keystore, `symudol_biometric_dek_wrap.<time>`
  (`BiometricVault.kt`). Each turn-on makes a new key and deletes the older ones only once the new
  wrap succeeds, so a cancelled prompt leaves the existing key and wrap working. If an old key
  can't be deleted then, it is logged and left: the wrap no longer points at it (#108). A wrap
  saved before keys had a time suffix has no alias and is read as the first key,
  `symudol_biometric_dek_wrap`. It needs a strong biometric for every use
  (`setUserAuthenticationRequired`, and `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)`
  on API 30+, per-use auth below it). The screen-lock PIN doesn't count. Adding a fingerprint
  invalidates it (`setInvalidatedByBiometricEnrollment`). `BIOMETRIC_STRONG` covers class-3 face
  unlock as well as fingerprints, so the app's copy says "fingerprint or face".
- **The check is the Keystore's.** `BiometricPrompt` gets the key's cipher as its `CryptoObject`,
  and the cipher only works once the user has authenticated. A yes from a dialog alone can't use
  the key.
- **The wrap.** The key's alias, the GCM IV and the ciphertext are stored as `vault_biometric_wrap` in
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

Keystore keys can be lost after some OS updates or lock-screen changes, and adding a fingerprint,
removing every fingerprint, or removing the screen lock invalidates this one by design. Symudol
then deletes the wrap and the key, turns biometric unlock off, and says so on the unlock screen. The
PIN still works and nothing else is lost.

- **A fingerprint added:** the next unlock fails with `keyInvalidated`.
- **No fingerprint left** (all removed, or the screen lock cleared): Android reports none enrolled,
  and Symudol turns biometric unlock off as soon as it reads that, at the next lock or when the app
  comes back to the front. Settings then shows it as off, rather than claiming it's on. The
  turn-off runs in the vault's queue, after any turn-on or unlock still in progress (#108).
- **The sensor unavailable for now:** biometric unlock stays on. The unlock screen and Settings say
  the phone can't use it right now, and Settings can still turn it off.

A second unlock while the vault is open zeroes the first DEK before keeping the new one.

The status is read when the vault state changes (set-up, lock, unlock, wipe), after a biometric
action or a PIN change, when the app comes back to the front, before the unlock screen prompts, and
when the Settings tile is tapped. Other refreshes, such as a settings or identity change, keep the
last status (#108).

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
