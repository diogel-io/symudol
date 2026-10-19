# Backup and Screen Capture — Decision

Decided 2026-10-19 in diogel-io/symudol#15. Meets security requirements SR-22 and SR-23 and
threat-model entries T12 and T13 (workspace
`10-products/symudol/requirements/security/signer-security-requirements.md` and
`10-products/symudol/architecture/threat-model.md`).

## Context

Until #15 the manifest set no `android:allowBackup` and no data-extraction rules, so Android's
default applied: app data went to cloud backup and to a new phone in a device transfer. That data
is:

- the vault, in `flutter_secure_storage`, encrypted under the PIN;
- remembered NIP-55 decisions, in `flutter_secure_storage` and mirrored in plain SharedPreferences
  (`nip55_permission_grants_v2`, and the legacy `nip55_provider_permissions_v1`) for the
  ContentProvider: caller package names, certificates and pubkeys;
- NIP-46 sessions, each with its `remoteSignerPrivkey`, in `flutter_secure_storage`.

`flutter_secure_storage` encrypts with an Android Keystore key, and Keystore keys never leave the
device. A restored copy is ciphertext the new phone cannot decrypt, while the SharedPreferences
mirror would restore in plain text. What a restore produced was untested.

Nothing set `FLAG_SECURE`, so the nsec import field, decrypted previews on the approval screen and
the PIN pad could be captured by a screenshot, a screen recording or the recent-apps preview.

## Options

### Backup

1. **Keep the default**: back up everything. The plain grant mirror leaves the phone, and the
   secure-storage parts restore as data the app cannot read.
2. **Back up some data**: exclude the vault, grants and NIP-46 sessions, and keep the rest.
   Everything Symudol stores is one of those three, so nothing useful would remain.
3. **Back up nothing**: turn off cloud backup and device transfer completely.

### Screen capture

1. **Per screen**: set and clear `FLAG_SECURE` from Dart over a method channel as routes change.
   Every route, dialog, transition and the approval screen opened from a NIP-55 intent would have
   to toggle it correctly, and a missed case leaks.
2. **App-wide**: set `FLAG_SECURE` once on MainActivity's window. Flutter draws every screen and
   dialog in that window.

## Decision

Backup option 3 and screen-capture option 2.

- `AndroidManifest.xml` sets `android:allowBackup="false"`, which turns off backup and transfer on
  Android 11 and below. On Android 12 and above, that flag stops cloud backup but not
  device-to-device transfer, so `android:dataExtractionRules` points to
  `res/xml/data_extraction_rules.xml`, which excludes every domain from both `cloud-backup` and
  `device-transfer`.
- `MainActivity.onCreate` sets `FLAG_SECURE` on its window before `super.onCreate`, so it applies
  from the first frame. That blocks screenshots, screen recording (MediaProjection) and the
  recent-apps thumbnail. `Nip55BridgeActivity` draws nothing, so it is left alone.
- The flag is set in every build type, so debug builds and tests behave like release.

`BackupPolicyTest` and `MainActivityWindowTest` check both.

## Consequences

- **Moving to a new phone.** Keys move only through an export the user asks for (SR-22). Until
  that export ships (#24, the nsec export, and #25, the encrypted vault backup file), a user who
  moves phones re-imports their nsec, and loses remembered decisions and NIP-46 pairings. The
  release notes and the Play listing say so.
- **Old backups.** Turning backup off does not delete backups taken by earlier builds. They expire
  on Android's own schedule, which the app cannot control.
- **Screenshots.** Users cannot screenshot any Symudol screen, including harmless ones such as the
  account list. `adb exec-out screencap` returns a black frame, so review walkthroughs and store
  screenshots need another way to capture, or a debug-only opt-out decided separately. Such an
  opt-out must never be reachable from an intent, because any app can send one.
