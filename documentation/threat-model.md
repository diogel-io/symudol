# Symudol Threat Model

Status: current

Baseline: `diogel-io/symudol` `master` at `5057dca`

This model was first written in the Diogel workspace against `22fca1e` and moved here, re-checked
against `5057dca`.

## How to read and maintain this document

- This document describes the code at the baseline commit. Paths are cited as they exist there.
- A pull request that adds an asset, a trust boundary or a control, or that changes one listed
  here, updates this document in the same pull request. The security review checklist in
  [SECURITY.md](../SECURITY.md) applies to every change touching a security-sensitive path.
- Each minor release's security review re-reads every control, and the rest of this document,
  against the release PR's head; after the release, the baseline moves to its `v<version>` tag.
- **Disclosure rule.** This repository is public. A newly found weakness is reported privately, as
  described in [SECURITY.md](../SECURITY.md), never in a public issue. It appears here only after
  its fix ships, or as a one-line pointer to an issue that is already public.

## Scope And Method

This model covers Symudol on Android for the 1.0 release: how other apps and remote clients ask it
to use a key, how the user decides, how the key is kept, and what the app sends over the network.
It covers NIP-55 (intents and the background ContentProvider), NIP-46 (remote signing over relays),
the vault, its backups and exports, and the native key copy.

iOS is not modelled here. Its key-access design is open in diogel-io/workspace#41, and the iOS
threats are listed as open items in section 9.

Code paths are relative to this repository. Android code is under
`android/app/src/main/kotlin/io/diogel/symudol/` and its tests under
`android/app/src/test/java/io/diogel/symudol/`; both are cited by file name. Findings in section 6
are conditions in the baseline code, verified by reading the paths named.

Issue numbers without a repository prefix refer to `diogel-io/symudol`. "Gap analysis" refers to
the 2026-10-04 gap analysis in the Diogel workspace.

## 1. Assets

| Asset | Where it lives | Why it matters |
|-------|----------------|----------------|
| Identity private keys | Vault records in `flutter_secure_storage`, encrypted with a data key that is wrapped by a key derived from the PIN (`lib/features/vault/`). A user who turns on biometric unlock also has the DEK wrapped by an Android Keystore AES-256-GCM key that needs `BIOMETRIC_STRONG` for each use (`BiometricVault.kt`, T23) | Compromise is unrecoverable. A Nostr identity has no rotation story |
| PIN and key hierarchy | `PIN --Argon2id--> KEK --AES-256-GCM--> DEK --AES-256-GCM--> secrets` (`lib/features/vault/domain/vault_crypto_service.dart` for the parameters, `lib/features/vault/data/pointycastle_vault_crypto_service.dart` for the implementation). Argon2id runs at 64 MiB, 3 passes, 1 lane for new vaults; weaker vaults are upgraded on the next unlock | The PIN is the only thing between a stolen phone's storage and the keys. Biometric unlock is a second, opt-in way in (T23) |
| Native key copy | `Nip55CryptoBridge.kt`, a `ByteArray` held while the vault is unlocked | Lets the ContentProvider answer without Flutter, so it must not outlive the unlock |
| Signing capability while unlocked | Dart `VaultService` and the provider bridge | An attacker does not need the key if they can cause signatures |
| Remembered NIP-55 decisions | `SecureStorageNip55PermissionStore` (Dart) and its native mirror `Nip55PermissionMirror.kt` | A remembered allow is a standing authorisation to act without a screen |
| NIP-46 sessions | `SecureStorageNip46SessionStore`. Each session's `remoteSignerPrivkey` and connect secret are encrypted under a key derived from the vault's DEK (#32). Plaintext sessions left from before #32 are deleted | A session key lets its holder speak for Symudol to the paired client |
| Encrypted vault backup file | A file the user saves to a location they pick. Each key is a NIP-49 `ncryptsec` under a scrypt key from a passphrase of at least 12 characters (`log_n` 16), and making one needs the PIN (#25; `lib/features/backup/domain/nip49.dart`, `vault_backup.dart`) | Whoever holds the file can guess the passphrase offline |
| Exported nsec | Shown on the export screen after the PIN, and copied to the clipboard for 60 s on request (#24; `lib/features/accounts/presentation/export_key_screen.dart`) | It is the private key in plain text |
| Event content and plaintext | Memory during a request, the approval screen, the clipboard in the browser flow (every copy marked sensitive, #94) | Reveals what the user says, to whom, and what they decrypt |
| Which apps and clients the user uses | Remembered decisions, NIP-46 sessions, relay traffic | Reveals the user's Nostr apps and the identities they hold |

## 2. Trust Boundaries

| # | Boundary | Enforcement today |
|---|----------|-------------------|
| B1 | Client app to the `nostrsigner:` intent | `Nip55BridgeActivity.kt` (exported) takes the caller only from Android's `callingPackage` and its signing certificate, never from extras. It registers the request in `Nip55Handoff.kt` under an unguessable token. A foreground rate limit applies (5 `get_public_key` or 3 other requests per caller, method and kind every 30 s; `Nip55BridgeActivity.kt:29-34`) |
| B2 | Client app to the ContentProvider | `Nip55ContentProvider.kt` (exported, nine authorities, no permission) takes the caller from `callingPackage`. It answers only a remembered decision for that package and certificate, for the active identity, while the native key is live. A query waits at most 500 ms for Dart (`Nip55ProviderBridge.kt:18`) |
| B3 | Bridge and links to MainActivity | MainActivity is exported as the launcher. It reads only a token from a NIP-55 intent; `Nip55RequestRouter.kt` sends each answer only to the bridge that owns the request. `nostrconnect:` links reach MainActivity through `Nip46LinkAlias`, which is disabled until Dart enables it, so a build that hides NIP-46 leaves it off. A link is handed to Dart once and never logged (`AndroidManifest.xml:70-82`, `Nip46Links.kt:11-17`) |
| B4 | Native code to Dart | MethodChannel. Signing always crosses to Dart through `Nip55ProviderBridge.kt`; native code never signs (#12) |
| B5 | App to device storage and backups | `flutter_secure_storage` for the vault, grants and NIP-46 sessions. The manifest sets `android:allowBackup="false"`, and `data_extraction_rules.xml` excludes every domain from cloud backup and device transfer (#15). An encrypted backup file leaves the app only to a location the user picks (#25) |
| B6 | App to relays and servers | NIP-46 traffic to each session's relays (default `wss://relay.damus.io` and `wss://nos.lol`; `nip46_controller.dart:89-92`). Only when the user asks: profile and NIP-65 relay-list lookups and publishing, to the identity's own relays, the default relays (damus, nos.lol, primal) and the indexers (purplepag.es, profiles.nostr1.com, relay.nos.social), all configurable in Settings (`lib/features/profile/domain/profile_relays.dart:9-22`); Blossom uploads to `https://blossom.primal.net` by default (`profile_network_settings.dart:5`); NIP-05 checks over HTTPS |
| B7 | User to the approval screen | `ApprovalScreen` shows the caller, method, kind and content, with "remember" and a timeframe, for NIP-55 and NIP-46 requests |
| B8 | App to the NIP-46 foreground service | `Nip46ForegroundService` is not exported, holds no keys and does no crypto, and is stopped when MainActivity goes (#29; `AndroidManifest.xml:83-91`, `Nip46ForegroundService.kt:19`) |

B1 and B2 carry the NIP-55 model. Both are exported to every app on the device, so every control
that stops one app acting as another lives at these two boundaries.

## 3. Adversaries

| Adversary | Capability assumed |
|-----------|--------------------|
| Hostile app on the same device | Installed by the user without special permissions. Can send any intent, query any exported provider, at any rate, with crafted extras and content |
| Impersonating app | As above, and claims to be a client the user trusts: same label, package name in extras, or a look-alike name |
| Malicious or compromised client | A real client the user has granted remembered decisions to, which now asks for more than the user meant |
| Lost or stolen phone | The finder holds the device, locked or unlocked, and can attach a computer. Cannot break the OS lock screen |
| Relay operator | Sees NIP-46 envelopes and profile requests, with their timing and source IP. Can drop, delay or replay events |
| Backup or device-transfer reader | Reads an app backup or a device-to-device transfer, in the cloud or locally, or a backup file the user saved |
| Screen observer | Sees the screen directly, by screenshot or screen recording, or through the recent-apps preview |

Symudol does not defend against an attacker who controls the operating system, has root, or has
unlocked the bootloader.

## 4. Threats And Controls

| ID | Threat | Control | Owner | Residual risk |
|----|--------|---------|-------|---------------|
| T1 | An app claims to be a trusted client and has that client's remembered decisions applied | The caller comes only from Android (`callingPackage` and the certificate from the package manager). MainActivity receives only a token, never the request or the caller (gap analysis H1) | #7 (closed); #84 for grants without a certificate | Grants without a certificate: F4 (#84) |
| T2 | A request is attributed to Symudol itself, whose grants would then serve any caller | Symudol as its own caller is treated as unknown in the bridge and the provider, and no grant names Symudol's package (gap analysis M3) | #11 (closed) | Low |
| T3 | A remembered grant for one kind signs every kind in the background | A broad allow (any kind) is never stored as a remembered decision (`isRememberable`), and `sign_event` without an integer kind matches no grant | #5, #10 (closed) | Low |
| T4 | A remembered `sign_message` grant signs a Nostr event, since `sha256` of an event's serialised form is its id (gap analysis H2) | `sign_message` refuses any message that is an event serialisation, in both the intent and the provider paths (`_isEventSerialisationMessage` in `nip55_controller.dart`) | #8 (closed) | Low |
| T5 | A background request for another account is answered with the active one, or a malformed `kind` is read as 0 (gap analysis M2) | The provider checks `current_user` against the active identity and refuses a `sign_event` with no integer kind | #10 (closed) | Low |
| T6 | The key stays in native memory after the app is gone and the provider keeps answering (gap analysis H3) | The native copy is a `ByteArray`, cleared on lock, on `MainActivity.onDestroy` and at the background lock deadline, and every read checks the deadline, which is timed on `elapsedRealtime` (`Nip55CryptoBridge.kt:30`) | #9 (closed) | The key is in process memory while unlocked; a memory dump on a compromised OS is out of scope |
| T7 | A lock and the unlock just before it race, and the key is put back after the lock (gap analysis M5) | A lock always wins over an earlier unlock in `Nip55Controller` | #13 (closed) | Low |
| T8 | Hand-written native curve code produces a bad or leaky signature (gap analysis M4) | Native code never signs. Dart signs and verifies every signature. Native ECDH for NIP-04 and NIP-44 runs only while `Nip55NativeCrypto.selfTestPassed` | #12 (closed) | Native ECDH still uses non-constant-time `BigInteger` code. Accepted in section 7 |
| T9 | A hostile app or client floods the user with approval screens until one is approved by habit | Foreground rate limit at B1. One review at a time: a second request is completed by a remembered decision, deferred, or rejected without touching the active one. A NIP-46 session may have at most 20 requests waiting for review (`nip46_controller.dart:99`) | #68 (closed, tests) | Habituation across separate bursts remains |
| T10 | An approval leaves the user unable to tell what they are signing | `ApprovalScreen` shows caller, method, kind label (`nostr_event_kind_registry.dart`) and content, and marks broad requests | Kind 5 and 31234 briefs (done) | Unknown kinds are shown with a range label, not a description |
| T11 | Event content, plaintext or grants reach logcat, where other tools and bug reports can read them (gap analysis M6) | Kotlin logs only through `DiogelLog`: debug lines exist only in debug builds, and warnings carry only the exception class (`DiogelLog.kt:5-20`). R8 strips `Log.v/d/i` from release builds (`android/app/proguard-rules.pro:4-8`). Dart logs only through `diogelLog` (`lib/app/diogel_log.dart`) | #14 (closed, PR #92) | Low. See F1 |
| T12 | A backup or device transfer copies the vault, grants and NIP-46 session keys off the phone (gap analysis M7) | `android:allowBackup="false"`, and `res/xml/data_extraction_rules.xml` excludes every domain from `cloud-backup` and `device-transfer`, which Android 12 and above still allow with the flag alone. `BackupPolicyTest` checks both | #15 (closed) | Low. Backups taken by earlier builds expire on Android's schedule. Keys move to a new phone only through a user-requested nsec export (#24, T24) or an encrypted backup file (#25, T25) |
| T13 | The nsec import field, decrypted previews or the key are captured by screenshot, screen recording or the recent-apps preview (gap analysis M9) | `FLAG_SECURE` is set app-wide on MainActivity's window before `super.onCreate`, so every Flutter screen and dialog is covered from the first frame (`MainActivityWindowTest`). The nsec import fields turn off IME personalised learning | #15 (closed) | Low. Every clipboard copy is marked sensitive (#94, `SensitiveClipboard.kt`), selections of secrets cannot be copied (#96, `lib/app/sensitive_selection.dart`), and a copied nsec is cleared after 60 s |
| T14 | A finder with a stolen phone guesses the 6-digit PIN (gap analysis M8) | Argon2id at 64 MiB, 3 passes, 1 lane. Each attempt is counted before the check. The lockout escalates from 30 s at 5 failures to a 24 h cap from 14, is timed on `elapsedRealtime` plus the boot count, and restarts on reboot (`vault_service_impl.dart:65,78-98`). An optional wipe follows 10, 15 or 20 failures ([pin-protection.md](pin-protection.md)) | #16 (closed, PR #100) | A 6-digit PIN has 10^6 values. A successful biometric unlock clears the lockout (T23) |
| T15 | Unlocking is treated as consent to the request that was waiting | After an unlock the waiting request goes back through the approval policy (`resumePendingAfterUnlock`): a remembered decision completes it, anything else is shown for review | Existing behaviour | Low |
| T16 | A remembered rejection or a timed allow never expires | Grants carry `expiresAt` (`justOnce`, `eightHours`, `always`) and expired grants match nothing, in Dart and in the native mirror | Timeframe brief (done) | Low |
| T17 | A NIP-46 client gets more than it asked for at connect, or a broad grant matches before review (gap analysis M1) | Connect-time permissions are saved as kind-specific grants. A broad allow never auto-approves (`nip46_approval_policy_test.dart`) | #28 (closed, PR #137) | Low |
| T18 | NIP-46 session keys are read from storage and used to impersonate Symudol to a paired client | Encrypted under a key derived from the vault's DEK with HKDF, so storage alone gives no session key and NIP-46 starts only after an unlock (SR-27) | #32 (closed, PR #139) | After an unlock the keys stay in memory until the process ends, so a request that arrives while locked can be held (SR-31) |
| T19 | A NIP-46 request that needs review is never shown, and the client times out | NIP-46 requests are reviewed on the Approval screen (`pendingMethodRequests`, `lib/features/nip46/application/nip46_providers.dart:72`). A request that times out is answered with an error | #27 (closed, PRs #134 and #135) | Low |
| T20 | Relays learn which pubkeys the user holds and when the app is opened | Profiles are fetched only when the user asks, after a confirmation that names the relays | #83 (closed, PR #90). See F3 | When the user asks, the named relays learn the pubkey and the IP address |
| T21 | A relay replays or reorders NIP-46 requests | Events from any key other than the session's client are dropped. Subscriptions use `since`. Duplicate event ids are ignored | #30 (closed, PR #112) | Low |
| T22 | Release signing (gap analysis R1) | See [#37](https://github.com/diogel-io/symudol/issues/37) | #37 (open) | Release blocker |
| T23 | The vault is unlocked with a biometric the owner didn't choose to give: a finder enrols their own fingerprint, or forces the owner's finger | Biometric unlock is opt-in and needs the PIN to turn on. The Keystore key needs `BIOMETRIC_STRONG` for each use and is invalidated when a fingerprint is added (`BiometricVault.kt:244-248`). The PIN is needed after a reboot or 72 h from the last PIN check (`vault_service_impl.dart:69`; [biometric-unlock.md](biometric-unlock.md)) | #23 (closed, PR #107; hardening PR #109) | A forced finger works within 72 h of the last PIN, as with any phone's fingerprint unlock. A fingerprint unlock also clears a PIN lockout |
| T24 | The nsec is shown or copied to someone other than the owner, or handed out after the vault locks | The export screen warns first, asks for the PIN (charged like an unlock) and keeps the key hidden until the user asks. A copy is marked sensitive and cleared after 60 s. A lock that starts during the export hands out nothing (`vault_service_impl.dart:857-893`, `export_key_screen.dart:12-20`) | #24 (closed, PR #132) | Once shown or copied, the key is outside Symudol's control |
| T25 | A stolen backup file is opened by guessing its passphrase, or a crafted file exhausts the phone on restore | A backup needs the PIN and a passphrase of at least 12 characters (`vault_service_impl.dart:795-807`). Keys are NIP-49 `ncryptsec` under scrypt `log_n` 16. Restore refuses a cost above `log_n` 20, files over 1 MiB and more than 100 identities (`nip49.dart:17-21`, `vault_backup.dart:14-17`) | #25 (closed, PR #130) | A weak passphrase can be guessed offline |
| T26 | The vault is erased by accident, or by a finder | Wipe Vault in Settings needs `WIPE` typed and names what is lost (`wipe_vault_dialog.dart`). Forgot PIN explains and offers the same wipe. The wipe after failed PINs is off by default and can only be set while unlocked (`vault_service_impl.dart:60,566-570`). A NIP-55 client waiting for unlock is answered when the wipe finishes (#104) | #20, #22, #16 (closed) | A finder can erase the keys; recovery needs a backup or an exported key |
| T27 | Symudol signs and publishes an event of its own that the user did not mean to send | Profiles (kind 0, #41), relay lists (kind 10002, #88) and Blossom upload authorisations (kind 24242, #43) are signed only after a confirmation that shows what is signed and names the relays (`lib/features/profile/presentation/publish_dialog.dart:6-8,25`, `blossom_client.dart:11-15`) | #41, #88, #43 (closed) | The named relays and the Blossom server learn the pubkey and the IP address |
| T28 | A NIP-05 check is used to probe the user's local network, or runs without the user asking | NIP-05 is checked only when the user asks. Identifiers with an IP address, a port, a path or a local-network domain are refused (`lib/features/profile/data/nip05_client.dart:43-60`) | #44 (closed, PR #131) | The identifier's domain learns the IP address when the user asks |
| T29 | A `nostrconnect:` link or QR code pairs a client the user did not approve, or leaks its secret | The link alias is off unless NIP-46 is enabled. The link is handed to Dart once and never logged. A nostrconnect session opens its relays only once the user approves the connection (`nip46_controller.dart:339-342`), and a re-pairing replaces an unused session only after approval | #31 (closed, PR #140) | Low |

## 5. Security Requirements

The requirements derived from this model are the signer security requirements (SR-1 to SR-31) in
the Diogel workspace. Each requirement names the threats it answers.

## 6. Findings In Current Code

These are conditions in `master` at `5057dca`, not hypotheticals. Findings already owned by an open
issue are listed in section 4 and not repeated here unless more detail is needed.

### Open

#### F4 - Grants without a certificate

Open, low severity: see [diogel-io/symudol#84](https://github.com/diogel-io/symudol/issues/84).

### Closed

#### F1 - Release builds logged request details

Severity: medium. Owner: #14. Fixed by PR #92.

`MainActivity.kt` logged the whole intent on create and on new intent, and part of the synced grant
JSON, in release builds. It now logs only the intent action, in debug builds
(`MainActivity.kt:57,255`). Provider lines are debug-only, and R8 strips any other debug logging
from release builds.

Tests: `Nip55LoggingTest` (`signingRequestsDoNotLogTheEvent`,
`encryptionAndDecryptionDoNotLogPlaintextOrCiphertext`, `malformedGrantsDoNotLogGrantData`,
`onlyDiogelLogWritesToTheSystemLog`); `MainActivityLoggingTest` (`onCreateDoesNotLogTheIntent`,
`onNewIntentDoesNotLogTheIntentOrTheRequest`); `test/app/diogel_log_test.dart` ("only diogelLog
writes logs under lib/").

#### F2 - Backups could carry grants and NIP-46 session keys

Severity: medium. Owner: #15. Fixed by PR #93.

`AndroidManifest.xml` set no `android:allowBackup` and no data-extraction rules, so the default
applied, and a backup could carry remembered decisions and NIP-46 session keys. Backup and device
transfer are now off (`AndroidManifest.xml:32-33`, T12). Since #32, NIP-46 session keys are also
encrypted under a key derived from the vault's DEK (T18).

Tests: `BackupPolicyTest` (`backupIsOff`, `theManifestPointsAtTheRules`,
`cloudBackupAndDeviceTransferExcludeEverything`); `MainActivityWindowTest`
(`theWindowIsSecureBeforeFlutterStarts`).

#### F3 - Profiles were fetched without the user asking

Severity: medium. Owner: #83. Fixed by PR #90.

The Accounts and Requests screens fetched profile metadata for every identity from two public
relays on each visit, so each relay learnt every pubkey the user holds, linked to one IP address.
Profiles are now fetched only when the user asks, after a confirmation that names the relays. This
follows the rule #44 adopts for NIP-05 (fetch only on request).

Tests: `test/features/profile/application/profile_providers_test.dart` ("reading a profile does not
fetch it"); `test/features/accounts/presentation/accounts_screen_profile_test.dart` ("opening the
Accounts screen fetches no profile", "cancelling the confirmation fetches nothing").

## 7. Accepted Risks

- **Native ECDH is hand-written and not constant-time.** It is used only for remembered NIP-04 and
  NIP-44 encrypt and decrypt, behind the self-test. Moving these to Dart or a vetted library is a
  follow-up from #12.
- **scrypt for backup keys is hand-written Kotlin** (`Scrypt.kt`), tested by `ScryptTest`.
- **The provider bridge has a 500 ms limit** (`Nip55ProviderBridge.kt:18`). A background request
  that Dart cannot answer in time returns nothing, and the client falls back to an intent. This
  fails closed.
- **NIP-46 runs in the background only while Symudol's activity exists.** It starts on unlock
  when a client is connected, and an opt-in foreground service keeps its relays open while
  Symudol is in the background. Swiping Symudol away ends it, and nothing wakes Symudol once its
  process is gone. A request that arrives while the vault is locked is held and decided after
  unlock (SR-31, #29).
- **NIP-46 duplicate requests (T21).** Duplicate event ids are refused (`nip46_controller_test.dart`
  "duplicate inbound event IDs are ignored"). NIP-46 is hidden in release builds (#26).
- **`get_public_key` is answered while the vault is locked** to a client with a remembered
  decision, from the persisted public key. The key is public, and the client already holds it.
- **No product analytics.** Symudol adds none, by choice.

## 8. Verification Hooks

These are covered by automated tests today, and must stay covered:

- The caller is the one Android reports, whatever the extras say (T1): `Nip55BridgeActivityTest`,
  `Nip55HandoffTest`.
- An answer goes only to the bridge that owns the request (T1, T9): `Nip55RequestRouterTest`.
- The Dart and Kotlin permission matchers agree, and a caller without a certificate is never
  remembered (T1, #17): `Nip55PermissionParityTest`,
  `test/features/nip55/application/nip55_controller_test.dart`.
- The provider answers only remembered decisions, for the right caller and account, refuses a
  `sign_event` without an integer kind, and never signs natively (T3, T5, T8):
  `Nip55ContentProviderTest`.
- The native key is zeroed when cleared, replaced or past the deadline (T6): `Nip55CryptoBridgeTest`.
- A failed self-test stops native encryption (T8): `Nip55ContentProviderTest`.
- A `sign_message` event serialisation is refused, and a concurrent intent is rejected as busy
  (T4, T9): `test/features/nip55/application/nip55_controller_test.dart`.
- A broad allow is never remembered (T3): `test/features/nip55/application/nip55_controller_test.dart`.
- An expired grant matches nothing (T16): `test/features/nip55/domain/nip55_approval_policy_test.dart`.
- No log line carries event content, plaintext or grant data, and only the log wrappers write logs
  (T11): `Nip55LoggingTest`, `MainActivityLoggingTest`, `test/app/diogel_log_test.dart`.
- Backup and device transfer exclude every domain (T12): `BackupPolicyTest`.
- `FLAG_SECURE` is set app-wide on MainActivity's window, not per screen (T13): `MainActivityWindowTest`.
- Clipboard copies are marked sensitive (T13): `SensitiveClipboardTest`,
  `test/app/sensitive_clipboard_test.dart`.
- The lockout does not shorten when the clock moves and restarts on reboot (T14):
  `test/features/vault/domain/vault_service_test.dart` ("the lockout is timed on the monotonic clock
  only", "an elapsed clock that went backwards restarts the lockout", "a reboot restarts the
  remaining lockout").
- A NIP-46 kind-specific grant is matched by kind, and a broad one never skips review (T17):
  `test/features/nip46/domain/nip46_approval_policy_test.dart` ("a kind grant allows only its own
  kind", "a broad allow grant never auto-approves").
- No network request is made before the user asks for profile data (T20):
  `test/features/profile/application/profile_providers_test.dart`,
  `test/features/accounts/presentation/accounts_screen_profile_test.dart`.
- Duplicate NIP-46 event ids are ignored (T21): `test/features/nip46/application/nip46_controller_test.dart`.
- Biometric unlock needs the PIN to turn on, an added fingerprint turns it off while the PIN still
  works, and the PIN is asked for again after a restart or 72 h (T23):
  `test/features/vault/domain/vault_service_test.dart` ("turning it on needs the PIN, then the
  prompt", "72 hours after the last PIN, the PIN is needed first", "an invalidated key turns it off,
  and the PIN still works"); `test/features/vault/presentation/biometric_unlock_test.dart` ("after a
  restart it asks for the PIN, without a prompt").
- The nsec export asks for the PIN first, hides the key until asked, clears the clipboard after
  60 s, and hands out nothing once a lock starts (T24):
  `test/features/accounts/presentation/export_key_screen_test.dart`,
  `test/features/vault/domain/vault_service_test.dart` ("a lock that starts during the export hands
  out nothing").
- A backup refuses a short passphrase, and restore refuses an oversized cost or file (T25):
  `test/features/vault/domain/vault_backup_service_test.dart`,
  `test/features/backup/domain/vault_backup_test.dart`.
- The wipe needs `WIPE` typed, and the wipe after failed PINs fires only at the chosen count (T26):
  `test/features/settings/presentation/wipe_vault_dialog_test.dart`,
  `test/features/vault/domain/vault_service_test.dart`.
- NIP-05 identifiers with an IP address or a local-network domain are refused (T28):
  `test/features/profile/data/nip05_client_test.dart`.
- A nostrconnect session opens no relay until it is approved (T29):
  `test/features/nip46/application/nip46_controller_test.dart` ("opens no relay until the connection
  is approved (#31)", "a rejected connection never opens a relay (#31)").

`nip55_device_check.sh` with `tools/nip55-test-client/` covers the same NIP-55 cases on a device
([nip55-device-checks.md](nip55-device-checks.md)).

## 9. Open Items

1. **iOS.** The Notification Service Extension cannot ask for the PIN. Option A (notify and
   approve) keeps the PIN guarantee; option B (auto-sign remembered permissions) stores the key
   where the extension can read it. The choice is diogel-io/workspace#41, then #60 and #63. This
   model must be extended before iOS ships.
2. **NIP-46 for Android 1.0.** Decided in #26 (PR #111): NIP-46 is hidden in release builds unless
   built with `SYMUDOL_ENABLE_NIP46` (`lib/features/nip46/application/nip46_feature.dart:10-11`).
   T17, T19 and T21 are closed (#28, #27, #30).
3. **Grants without a certificate (F4).** #84.
4. **Release signing (T22).** #37, a release blocker.

## References

- The signer security requirements (SR-1 to SR-31), in the Diogel workspace.
- The 2026-10-04 Symudol gap analysis (findings H1 to H3 and M1 to M9), in the Diogel workspace.
- The Symudol product brief, in the Diogel workspace.
- Decision records in this folder: [nip55-native-crypto-decision.md](nip55-native-crypto-decision.md),
  [nip55-contentprovider-mvp.md](nip55-contentprovider-mvp.md),
  [backup-and-screen-capture-decision.md](backup-and-screen-capture-decision.md),
  [pin-protection.md](pin-protection.md), [biometric-unlock.md](biometric-unlock.md),
  [nip46-client-interop.md](nip46-client-interop.md),
  [nip55-device-checks.md](nip55-device-checks.md).
- The Porwr approval threat model this one follows: `diogel-io/porwr` `docs/threat-model.md`.
