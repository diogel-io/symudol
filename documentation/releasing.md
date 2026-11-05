# Releasing Symudol

Symudol releases the way Porwr and Bancwr do: a GitHub milestone holds a release's scope, and a
release PR, opened and kept up to date by
[release-please](https://github.com/googleapis/release-please), ships it. The Diogel
release-process standard (`40-engineering/standards/release-process.md` in diogel-io/workspace)
describes the process for every product; this page covers what is specific to Symudol.

## The pieces

| File | What it does |
| --- | --- |
| `.github/workflows/release.yml` | Runs release-please on every push to `master`, and closes the version's milestone after a release. |
| `release-please-config.json` | Release type `dart`, tags `v<version>`, release PR title `chore(release): <version>`, changelog sections. |
| `.release-please-manifest.json` | The last released version. release-please updates it in each release PR; do not edit it by hand. |
| `CHANGELOG.md` | Written by release-please from the commits in each release. |
| `pubspec.yaml` | `version:` is bumped by the release PR. |

## Version and build number

`pubspec.yaml` carries `<version>+<build>`. Android uses the version as `versionName` and the build
number as `versionCode`; iOS uses them as `CFBundleShortVersionString` and `CFBundleVersion`.

Each release PR sets the new version and adds one to the build number, so `1.0.0+1` becomes
`1.0.0+2` for the first release, and `versionCode` always goes up, as the Play Store requires.

The version comes from the commit types since the last tag:

| Commit | Next version, from 1.0.0 |
| --- | --- |
| `fix:` | patch, `1.0.1` |
| `feat:` | minor, `1.1.0` |
| `feat!:` or a `BREAKING CHANGE:` footer | major, `2.0.0` |

To force a version, merge a commit whose message has a `Release-As: <version>` footer. The manifest
starts at `0.0.0`, and the commit that set up release-please carries `Release-As: 1.0.0`, so the
first release is `1.0.0`.

## Release notes

A tag produces release notes automatically: release-please writes the GitHub release's body from
the `CHANGELOG.md` section it generated, grouped by the changelog sections in
`release-please-config.json`:

| Section | Commit types shown |
| --- | --- |
| Features | `feat:` |
| Bug Fixes | `fix:` |
| Performance Improvements | `perf:` |

Reverts get their own section; `docs:`, `chore:`, `refactor:`, `test:`, `build:` and `ci:` are
hidden. Write commit messages for the person reading them, not the committer: they are what users
see. To correct a release's notes after the fact, edit the GitHub release, and fix the source by
amending the merged PR's body with a `BEGIN_COMMIT_OVERRIDE` block as described under
*Cutting a release*.

The tag also produces the signed artefacts the publish job attaches (#89): the AAB goes to the
Google Play track as a draft, and `symudol.apk` goes onto the GitHub release and to Zapstore.

## Scope: the milestone

Each planned release has a milestone named after its version without the `v`, for example `1.0.0`.
Put an issue in the milestone when it is scoped into that release, and put every pull request
that delivers one in the same milestone, then the release PR as well. Create a milestone only when
there is work to put in it. The release workflow closes it when the release is created.

## Cutting a release

1. Check that every issue in the version's milestone is closed or moved to a later milestone.
2. Finish the release's security review, as the Diogel release process requires. Every release
   reviews what changed since the last tag against [the threat model](threat-model.md); with no
   earlier tag, `v1.0.0` reviews what changed since the threat model's `Baseline:` commit. The first
   release (`v1.0.0`) and every minor release (`x.Y.0`) also re-read every control in its section 4
   against the release PR's head commit, which is the code that ships, and record the line that
   enforces each one, what it covers and what it does not, and the test that holds it. The review
   is recorded privately, naming the head commit it read. For `v1.0.0` and every minor release
   (the releases that walk every control), a `docs:` PR moves the threat model's `Baseline:` to the
   `v<version>` tag once the release has shipped; a patch release leaves the baseline where it
   is. The baseline moves only when the whole document has been re-checked, so that review also
   re-reads the assets, boundaries, adversaries, accepted risks, findings and verification hooks
   against the same head, and the `docs:` PR carries any row it corrected. A weakness it finds is
   reported and fixed as [SECURITY.md](../SECURITY.md) describes, and the release waits for the
   fix.
   If the release PR's head changes after the review, for example to fix what it found, review the
   difference before merging and record the new head. The release PR's **Security review** section
   says only that the review is complete, at which head commit, and its outcome; the details stay in
   the private record.
3. Get CI to run on the release PR. release-please opens it with the workflow `GITHUB_TOKEN`, and
   GitHub does not start workflows for that token's events, so close and reopen the PR, or push
   an empty commit to its branch.
4. Review the version, the `pubspec.yaml` bump and the `CHANGELOG.md` section. If a commit is in
   the wrong section, fix the message, not the generated PR: edit the merged PR's body to add

   ```text
   BEGIN_COMMIT_OVERRIDE
   fix(nip55): the corrected message
   END_COMMIT_OVERRIDE
   ```

   and the next run regenerates the release PR from it.
5. Merge the release PR. The release workflow tags the merge commit `v<version>`, creates the
   GitHub release with the changelog section as its notes, labels the PR `autorelease: tagged`,
   closes the milestone, and runs the publish job (#89): the signed AAB is uploaded as a draft to
   the Google Play track named by the `PLAY_TRACK` repository variable (default: `internal`), and
   the signed APK is attached to the GitHub release and published to Zapstore. Publish the draft in
   the Play Console to make the release installable.

## Publishing from CI (#89)

Merging the release PR is the one manual step; the publish job does the rest (except for the
first release on Zapstore, which needs the one-time C1 proof step below). It checks out the
`v<version>` tag, builds the signed AAB and APK with the upload key, asserts the APK's signer is
the upload key (the fingerprint below), uploads the AAB as a **draft** to the configured track,
attaches `symudol.apk` to the GitHub release, and publishes the same APK to Zapstore with `zsp`
(`zapstore.yaml`). A merge that creates no release builds nothing: every publish step sits behind
`release_created == 'true'`.

### Required secrets and variables

Set these on the repository before the first release; the job fails visibly if one is missing or
wrong, and the signer check runs before any upload.

| Secret or variable | Contents |
| --- | --- |
| `SYMUDOL_UPLOAD_KEYSTORE_BASE64` (secret) | The upload keystore (`symudol-upload.p12`), base64-encoded (`base64 -w0 symudol-upload.p12`). Decoded to a job-local file the runner deletes on every outcome |
| `SYMUDOL_UPLOAD_STORE_PASSWORD` (secret) | The upload keystore's password |
| `SYMUDOL_UPLOAD_KEY_ALIAS` (secret) | `symudol-upload` |
| `SYMUDOL_UPLOAD_KEY_PASSWORD` (secret) | The alias's password |
| `PLAY_SERVICE_ACCOUNT_JSON` (secret) | The Google Play service account's JSON key. The account needs only the internal-testing release permission on the app |
| `ZAPSTORE_SIGNER_NSEC` (secret) | The Diogel Zapstore publisher identity as an `nsec`; signs the catalog events only. It cannot sign Android updates |
| `PLAY_TRACK` (variable, optional) | The Play track to draft-publish to. Defaults to `internal` |

`zapstore.yaml` records the publisher's public half (`pubkey`); `zsp` refuses to publish when the
secret resolves to a different key. Commit it with the real npub before the first release.

One-time setup, done once by hand:

1. Play Console: create the service account, grant it release permission on the internal track,
   and store its JSON as `PLAY_SERVICE_ACCOUNT_JSON`.
2. Zapstore: generate the publisher key (keep the `nsec` offline as well as in the secret), and
   put its `npub` in `zapstore.yaml`.
3. Zapstore: prove the upload key belongs to the publisher (the NIP-C1 proof), so Zapstore
   clients can verify the APK signature belongs to the publisher. The publish job cannot do this:
   `zsp publish` stops with "No active proof found" until a proof exists, and it has no way to
   make one. zsp 2.0.1 makes the proof only in its interactive wizard, and for an app Zapstore
   doesn't list yet, the wizard publishes the proof only together with the first release. So the
   first release reaches Zapstore by hand:
   1. Cut the first release as usual. The publish job uploads to Play and the GitHub release, then
      its Zapstore step fails with "No active proof found". That is expected for this release
      only; don't rerun it.
   2. In a terminal on the release machine, with the upload key set up, check out the release tag
      and put the publisher `nsec` in `.env` as `SIGN_WITH`, which is where zsp's wizard reads it.
      `.env` is gitignored. This command keeps the key out of your shell history:

      ```bash
      git checkout v1.0.0
      (umask 077; read -rs -p 'Zapstore publisher nsec: ' N; echo; printf 'SIGN_WITH=%s\n' "$N" > .env)
      ```

   3. Run the script:

      ```bash
      tools/zapstore_c1_proof.sh
      ```

      It builds `symudol.apk` from the tag and checks its signer is the upload key, checks `.env`
      has a `SIGN_WITH` line, downloads the zsp version the publish job pins and checks its
      SHA-256, prints what to give the wizard, then runs zsp's wizard and `zsp check`. After a
      first run, `--no-build` reuses the APK; the script still checks its signer.
   4. In the wizard, choose **Use your nsec from .env**, then the upload keystore. When it asks to
      publish the release now, choose **Publish now**. The release and the proof go to Zapstore
      together. Later releases are published by the publish job.
   5. Delete `.env` and keep the `nsec` offline.

   You type the keystore password into zsp; the script never sees it, or the `nsec`.

   **If an upload fails with "authenticated pubkey is not allowed",** Zapstore hasn't whitelisted
   the publisher yet. Zapstore's docs say a committed `zapstore.yaml` whitelists a new publisher
   automatically, but in November 2026 that wasn't working (zapstore/zsp#25). Nothing is published
   when this happens. Ask for the key to be added with a "Whitelist request" issue in
   zapstore/relay, as Symudol did in zapstore/relay#15, then run the script again with
   `--no-build`.

   The proof lasts two years, and the publish job cannot renew it. Note the expiry that
   `zsp check` prints, and in the 30 days before it run the script again from the latest release
   tag: for a listed app the wizard renews the proof straight away, without a release.

### Rolling back a bad release

- **Draft not yet published in Play:** delete the draft in the Play Console. Nothing user-visible
  happened. Remove the APK from the GitHub release and delete the Zapstore event that points at it
  with `nak delete` signed with the publisher key.
- **Published to the internal track:** halt or discard the release in the Play Console and cut a
  new release with a higher build number (`Release-As:` never reuses a `versionCode`). Devices on
  the draft can only be fixed by a newer, signed build.
- **The upload key is leaked:** follow the reset procedure under *Building and signing a release*
  below, then replace the `SYMUDOL_UPLOAD_*` secrets. The app signing key is unaffected.

## Building and signing a release

> This section describes the manual path. Since #89 the release workflow's publish job does this
> from CI: use this path only for a local build, a workflow fix, or if CI publishing is down.

Google Play gets an Android App Bundle signed with Symudol's **upload key**. Play then signs what
users install with the **app signing key**, through Play App Signing (#37). The two keys are
separate:

| Key | Alias | Held | SHA-256 certificate fingerprint |
| --- | --- | --- | --- |
| App signing key | `symudol-app-signing` | Offline, with an offline backup; Play App Signing holds a copy uploaded with PEPK | `F6:88:2A:CD:85:CA:1A:5C:46:70:85:A9:50:0E:94:33:36:CD:E0:3D:7A:64:50:12:77:E9:D2:63:20:FE:57:E3` |
| Upload key | `symudol-upload` | The release machine, outside every repository, with an offline backup | `E4:23:FF:9E:65:68:70:F7:1D:76:C6:03:3B:44:1E:0F:00:16:4B:45:4B:9D:23:6E:A2:DE:38:76:4A:95:AE:F9` |

The fingerprints are public. The keystores and their passwords are not: never commit them, put them
in an issue, or copy them into the workspace. `android/.gitignore` ignores `key.properties`,
`*.p12`, `*.jks` and `*.keystore` as a backstop.

1. Check out the release tag, `git checkout v<version>`.
2. Point the build at the upload key, in one of two ways:
   - copy `android/key.properties.example` to `android/key.properties` and fill it in; or
   - set `SYMUDOL_UPLOAD_STORE_FILE`, `SYMUDOL_UPLOAD_STORE_PASSWORD`, `SYMUDOL_UPLOAD_KEY_ALIAS`
     and `SYMUDOL_UPLOAD_KEY_PASSWORD`, which override the file, so the passwords need not be
     written to disk.
3. Build the bundle:

   ```bash
   flutter build appbundle --release
   ```

   Without the upload key this fails with `No upload key`, so a bundle for Play is never
   debug-signed. `flutter build apk --release` still works without the key: it signs with the debug
   key and prints a warning, which is what the emulator and `nip55_device_check.sh --symudol-apk`
   use. Never distribute that APK: it is `app-release.apk`, and no `symudol.apk` is written without
   the key.
4. Check the signer, which must be the upload key's fingerprint above:

   ```bash
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   ```

5. Upload `build/app/outputs/bundle/release/app-release.aab` in the Play Console, to internal
   testing first.
6. To share the app outside Play, build the release APK with the upload key still set:

   ```bash
   flutter build apk --release
   # ANDROID_HOME is the Android SDK, for example ~/Android/Sdk; this picks its newest build tools.
   BUILD_TOOLS="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n 1)"
   "$BUILD_TOOLS"/apksigner verify --print-certs build/app/outputs/flutter-apk/symudol.apk
   ```

   With the upload key, the build also writes `build/app/outputs/flutter-apk/symudol.apk`, a copy of
   Flutter's `app-release.apk`; distribute that file. Its `certificate SHA-256 digest` must be the
   upload key's fingerprint above, in lower case without the colons. `keytool -printcert -jarfile`
   can't check it: with `minSdk` 24 the APK has only a v2 signature, not a JAR one.

   `symudol.apk` is signed with the upload key, but Play signs the copies it installs with the app
   signing key. Android won't update one with the other, so a phone that has Symudol from Play can't
   install `symudol.apk` over it, and the reverse. Switching means uninstalling, which erases the
   vault: tell people to save an encrypted vault backup first and restore it after reinstalling.
   Resetting the upload key also stops `symudol.apk` installs from taking the next `symudol.apk`.
7. Delete `android/key.properties` once the bundle is uploaded and the APK is built. Git ignores
   it, but it holds the upload key's passwords; the environment variables avoid writing them to
   disk at all.

`minSdk` (24), `targetSdk` (36) and `compileSdk` (36) are pinned in `android/app/build.gradle.kts`
with the reason for each. A Flutter upgrade does not change them; raise them in a reviewed PR.

**If the upload key is lost or leaked**, generate a new upload key, export its certificate
(`keytool -export -rfc`), and use **Request reset** under Play Console → App signing. Update the
fingerprint above. The app signing key is not affected, so installs keep updating.

**If the app signing key is leaked**, anyone can sign an update that installs over Symudol, and
existing installs cannot be moved to a new key except by Play's key upgrade, which only applies to
newer Android versions. Treat it as a security incident under [SECURITY.md](../SECURITY.md).

## Google Play listing

The store listing lives in `fastlane/metadata/android/en-GB/`, in the layout Google Play tooling
and F-Droid both read (#39). Nothing installs or runs fastlane yet: the files are the source the
Play Console is filled from, and the listing text changes through PRs like the code.

| File | Play Console field | Limit |
| --- | --- | --- |
| `title.txt` | App name | 30 characters |
| `short_description.txt` | Short description | 80 characters |
| `full_description.txt` | Full description | 4,000 characters |
| `images/icon.png` | App icon | 512×512 PNG |
| `images/featureGraphic.png` | Feature graphic | 1024×500 PNG or JPEG, no transparency |
| `images/phoneScreenshots/` | Phone screenshots | 2 to 8; long side at most twice the short side, 1200×2400 here |

- The icon is the launcher icon, `assets/images/symudol.png` on `#111827`. The feature graphic is
  the Symudol share card (workspace `60-marketing/brand/images/share/symudol-share.svg`) cropped to
  1024×500.
- `fastlane/README.md` says how the screenshots were taken. `FLAG_SECURE` blanks
  every capture (`backup-and-screen-capture-decision.md`), so they come from a local build with
  that line disabled, which is never committed.
- The privacy policy is `https://diogel.io/privacy/symudol`, from diogel-io/website, and
  Settings → Privacy policy opens it. Keep that address stable: the Play Console links to it.
- The data safety, content rating and other Play Console answers are kept in the workspace, in
  `10-products/symudol/releases/play-store-submission.md`.

Release builds hide NIP-46 (#26), so `android/app/src/release/AndroidManifest.xml` removes what only
NIP-46 uses: the camera, the foreground service and its notification permission. Play then asks for
no foreground-service declaration. Delete that file, and `ReleaseManifestTest`, when NIP-46 ships in
release builds; until then a release build made with `SYMUDOL_ENABLE_NIP46` has no QR scanning and
no background running.
