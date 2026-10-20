# PIN Protection — Decision

Decided 2026-10-20 in diogel-io/symudol#16. Meets security requirement SR-20 and answers its open
question 3 (fixed escalation plus an opt-in wipe), and covers threat-model entry T14 (workspace
`10-products/symudol/requirements/security/signer-security-requirements.md` and
`10-products/symudol/architecture/threat-model.md`).

## Context

The PIN is 6 digits: 10^6 possibilities. Before #16:

- the lockout topped out at 5 minutes after 10 attempts, and never escalated or wiped;
- it was a wall-clock timestamp, so moving the date forward in Settings ended it;
- the failure was counted only after the check failed, so killing the app during the check saved the
  guess;
- Argon2id ran at 19 MiB, 2 passes, 1 lane, the OWASP minimum.

## Lockout Schedule

| Consecutive failures | Lockout |
| --- | --- |
| 1–4 | none |
| 5 | 30 s |
| 6 | 1 min |
| 7 | 5 min |
| 8 | 15 min |
| 9 | 1 h |
| 10 | 2 h |
| 11, 12, 13 | 4 h, 8 h, 16 h |
| 14 and more | 24 h (the cap) |

`VaultServiceImpl.lockoutFor` is the table in code. Reaching the 10th attempt means sitting through
about 1 h 21 min of lockouts, and the 14th about 1.3 days; after that, each guess costs 24 h. Online
guessing of the whole PIN space is out of reach.

A correct PIN resets the count and clears the lockout.

## Counted Before Checking

`unlock` writes the incremented count, and the lockout that count earns, before it runs Argon2id.
A correct PIN then clears both. Killing the app mid-check therefore still charges the attempt. The
cost is that a crash during a correct unlock leaves one charged attempt, which the next success
resets.

Unlock attempts run one at a time, so a second attempt cannot overtake one that erases the vault.

## Clock-proof Timing

A lockout is stored as `{bootCount, startElapsedMs, durationMs}` (`VaultLockout`, under
`vault_lockout`), timed on Android's `SystemClock.elapsedRealtime()` plus
`Settings.Global.BOOT_COUNT`, read from `MainActivity` over the `io.diogel.symudol/clock` channel
(`MonotonicClock.kt`, `PlatformMonotonicClock`).

- **Same boot:** time left is `duration − (now − start)`, clamped to `[0, duration]`. Changing the
  date or time in Settings does not move `elapsedRealtime`.
- **Another boot, or the elapsed clock went backwards:** what was served cannot be measured, so the
  whole duration is left again, re-based to now and saved. A reboot restarts a lockout. It never
  ends one. A user who reboots mid-lockout waits longer, which is acceptable for a 6-digit PIN.

Other platforms fall back to wall time with a fixed boot id. Symudol ships on Android only, and iOS
needs its own clock before it ships.

The unlock screen counts down on a `Stopwatch`, which is also monotonic, and re-reads the time left
from the service when the app resumes, because a `Stopwatch` does not run while the phone sleeps.
The countdown is only a display: the service enforces the lockout.

## Optional Wipe After N Failures

Settings → "Erase after failed PIN attempts": Off (the default), 10, 15 or 20. Turning it on, or
changing the count, asks for confirmation, and it can only be changed while the vault is unlocked.
When a wrong PIN brings the count to N, `unlock` calls `VaultService.wipe()` (#20), which erases
every identity and key, the NIP-55 grants and their native mirror, and the NIP-46 sessions. The app
then returns to setup. A NIP-55 request that was waiting for the vault to unlock is answered as soon
as the erase finishes (#104), so the client hears at once instead of after its 5-minute unlock
timeout.

From 3 attempts before the limit, the unlock screen warns: "3 attempts left before Symudol erases
all keys."

## Argon2id Cost

New vaults use 64 MiB, 3 passes, 1 lane (`VaultKdfParams.defaultParams`). That was the strongest
setting tried whose median derivation stayed within the 1.5 s ceiling.

Measured with `integration_test/argon2_bench_test.dart` in profile mode, which compiles AOT like a
release build:

```bash
flutter drive --profile --driver=test_driver/integration_test.dart \
  --target=integration_test/argon2_bench_test.dart
```

It derives a key in a background isolate (as unlock does) five times per setting and reports the
median. Its second test times the whole `VaultService.unlock` with the default params: secure
storage, the clock channel, Argon2id and the DEK unwrap. It erases the app's vault on that device.

**Device:** Android emulator, API 34 (`google_apis`, x86_64), 2 cores, 2 GB RAM, on an Intel
i7-10700T host, 2026-10-20. The plan named an API 26 image; none was installed, and the API level
does not change Argon2id's cost on the same CPU, so the installed API 34 image was used with the
same core and memory limits.

| Setting | Run 1 median (runs) | Run 2 median (runs) |
| --- | --- | --- |
| 64 MiB / t3 | 1328 ms (1166, 1232, 1328, 1704, 2718) | 1071 ms (1054, 1057, 1071, 1133, 1210) |
| 46 MiB / t2 | 727 ms (710, 721, 727, 752, 761) | 520 ms (508, 518, 520, 528, 534) |
| 32 MiB / t3 | 657 ms (605, 639, 657, 674, 749) | 521 ms (516, 519, 521, 524, 526) |
| 19 MiB / t2 (before #16) | 311 ms (267, 272, 311, 383, 399) | 210 ms (205, 209, 210, 214, 226) |
| Whole unlock, 64 MiB / t3 | — | 1064 ms (1039, 1060, 1064, 1075, 1079) |

64 MiB / t3 makes each offline guess about 5 times as expensive as before.

**Limits of this evidence.** An emulator limits cores and memory but not the speed of each core:
those are the host's desktop cores. A low-end ARM phone may be several times slower, so confirm the
unlock time on a real low-end phone before release. If it exceeds about 1.5 s, step down the ladder
(46 MiB / t2 or 32 MiB / t3) by changing `defaultParams`: vaults on stronger params than the new
default stay as they are, and weaker ones upgrade.

The slower KDF is felt on every unlock, including the NIP-55 and NIP-46 flows that wait for unlock;
the unlock screen's loading state covers it.

## Key Envelope and Migration

The salt, the KDF params and the wrapped DEK are stored together as one JSON value,
`vault_key_envelope`, written in a single `flutter_secure_storage` write (`VaultKeyEnvelope`). A
re-wrap, whether a KDF upgrade or a PIN change (#21), can never leave a salt from one wrap beside a
DEK from another. The store version is set to `2`.

Existing vaults migrate on their next successful unlock:

- **Key fields:** reads fall back to the three legacy keys (`vault_kdf_salt`, `vault_kdf_params`,
  `vault_wrapped_dek`), and the legacy keys are deleted only after the envelope is written.
- **KDF:** if the stored params are weaker than `defaultParams`, the same DEK is re-wrapped under a
  new KEK with a fresh salt and the default params, in one envelope write. If that write fails, the
  old envelope keeps working and the upgrade is retried on the next unlock. The first unlock after
  upgrading therefore runs Argon2id twice.
- **Lockout:** a legacy `vault_lockout_until` in the future becomes a `VaultLockout` for the time
  left (capped at 24 h), and the legacy key is deleted. The failure count carries over.

Migration is one-way: once the envelope is written, older builds cannot read the vault. Downgrades
are not supported, which matches release-please's forward-only releases.

## Changing the PIN

Settings → Change PIN (diogel-io/symudol#21) asks for the current PIN, then the new PIN twice.

- **The current PIN is checked like an unlock.** It is charged before Argon2id runs, honours the
  lockout, and counts towards the wipe-after-N limit, through the same code as unlocking. Change
  PIN would otherwise be a second place to guess the PIN on an unlocked phone, and learning it there
  lets someone unlock later. Unlocks and changes are queued, so they never overlap.
- **The same DEK is re-wrapped.** It gets a fresh salt and `VaultKdfParams.defaultParams` (so a
  change also upgrades weaker parameters), and is saved in one `vault_key_envelope` write.
  Identities, NIP-55 grants and NIP-46 sessions are untouched. The DEK is taken from the envelope,
  not the session, so a lock during the change does not stop it.
- **An interrupted change keeps the old PIN.** Until that one write lands, the old envelope is the
  only one stored; a failed write is reported and the old PIN still works.

A change runs Argon2id twice (check, then re-wrap): about 2 s on the reference emulator.

## A Forgotten PIN

A forgotten PIN can't be recovered or reset, by design: the keys are encrypted with it and
Symudol keeps no copy. "Forgot PIN?" on the unlock screen (diogel-io/symudol#22) says so and
offers one way forward, erasing the vault and starting again, through the same confirmation as
Settings → Wipe Vault (#20): it names what is lost and needs `WIPE` typed. It works while locked
and during a lockout. Any NIP-55 request that was waiting for the vault to unlock is answered once
the erase has finished: `Nip55Controller` answers it when the vault goes from existing to none,
whichever way it was erased (#104). A wipe that fails and leaves the vault answers nothing, since
the request can still be unlocked.

Anyone holding the phone can therefore erase the vault from the lock screen. That exposes no key,
and the typed confirmation guards against accidents; someone with the phone could already clear
the app's data from Android's settings. Restoring from a backup joins this dialog once backups
exist (#25).

## No Keystore Binding for the KEK

Binding the KEK to an Android Keystore key, so that offline guessing needs the device, was
considered and rejected.

`flutter_secure_storage` already encrypts every stored value, including the salt and the wrapped
DEK, under a Keystore key that never leaves the device. An attacker with a copy of the app's data
but not the device has only ciphertext, so stored data is already device-bound. A second Keystore
key would not stop an attacker who has the device, because the app would use it on their behalf for
every guess. And it would add a way to lose the vault: if that key were lost (Keystore keys have
been lost on some devices after OS updates or lock-screen changes), the vault could not be opened
even with the right PIN.

Biometric unlock (#23) is a different thing: an optional second wrap of the same DEK, under a
Keystore key that needs a fingerprint. Losing that key only turns biometric unlock off; the PIN
wrap is untouched (`biometric-unlock.md`).

## Verification (2026-10-20)

On the emulator above, with release builds:

- **Migration:** a vault and an identity made with a release build of `master` (`40fbb51`), plus 5
  wrong PINs to set a legacy lockout, then this build installed over it. The legacy lockout carried
  over (21 s left), the old PIN unlocked, the same identity was there, and secure storage held
  `vault_key_envelope`, `vault_version` and `vault_lockout`, with no legacy key fields. Later
  unlocks worked.
- **Clock:** 5 wrong PINs gave a 30 s lockout. With automatic time off and the clock moved a day
  forward, the lockout and the countdown carried on. Rebooting with 33 s of a 1 min lockout left
  showed the full minute again after boot (boot count 1 → 2).
- **Wipe warning:** with "Erase after 10" turned on in Settings (confirmation shown), the 7th wrong
  PIN showed "3 attempts left before Symudol erases all keys." The erase itself is covered by the
  `VaultServiceImpl wipe after failed PINs` tests rather than a walkthrough, since reaching the
  10th attempt means waiting out about 1 h 21 min of lockouts.
