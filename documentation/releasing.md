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
   GitHub release with the changelog section as its notes, labels the PR `autorelease: tagged`, and
   closes the milestone.

Building, signing and uploading are not automated: do them from the tag, as the next section
describes. TestFlight is not set up yet.

## Building and signing a release

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
   use. Never distribute that APK.
4. Check the signer, which must be the upload key's fingerprint above:

   ```bash
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   ```

5. Upload `build/app/outputs/bundle/release/app-release.aab` in the Play Console, to internal
   testing first.
6. Delete `android/key.properties` once the bundle is uploaded. Git ignores it, but it holds the
   upload key's passwords; the environment variables avoid writing them to disk at all.

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
