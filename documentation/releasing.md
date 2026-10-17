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
2. Get CI to run on the release PR. release-please opens it with the workflow `GITHUB_TOKEN`, and
   GitHub does not start workflows for that token's events, so close and reopen the PR, or push
   an empty commit to its branch.
3. Review the version, the `pubspec.yaml` bump and the `CHANGELOG.md` section. If a commit is in
   the wrong section, fix the message, not the generated PR: edit the merged PR's body to add

   ```text
   BEGIN_COMMIT_OVERRIDE
   fix(nip55): the corrected message
   END_COMMIT_OVERRIDE
   ```

   and the next run regenerates the release PR from it.
4. Merge the release PR. The release workflow tags the merge commit `v<version>`, creates the
   GitHub release with the changelog section as its notes, labels the PR `autorelease: tagged`, and
   closes the milestone.

Building, signing and uploading the app to the Play Store or TestFlight is not automated yet; do it
from the tag.
