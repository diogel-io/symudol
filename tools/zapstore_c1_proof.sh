#!/usr/bin/env bash
# One-time Zapstore setup: prove the upload key belongs to the Diogel publisher (NIP-C1, #89).
#
# Run this by hand on the release machine, from a checkout of the release tag (v<version>). It
# does the error-prone parts for you, then hands over to zsp's interactive setup wizard, which is
# the only way zsp 2.0.1 makes the proof.
#
# When to run it:
#   - First release: CI's `zsp publish` fails with "No active proof" until a proof exists, and
#     for an app Zapstore doesn't list yet the wizard publishes the proof only together with the
#     first release ("Publish now"). So after the first release is cut, run this from its tag and
#     choose "Publish now"; that is Symudol's first Zapstore release.
#   - Renewal: the proof lasts two years and CI cannot renew it. Run this again from the latest
#     release tag in the 30 days before the expiry `zsp check` prints; the wizard renews it.
#
# What it does:
#   1. checks HEAD is a release tag, and zapstore.yaml has the publisher's real npub;
#   2. builds symudol.apk with the upload key (or reuses one with --no-build), and stops unless
#      the APK's signer is the upload key the release workflow expects;
#   3. downloads the zsp version the release workflow pins, and stops unless its SHA-256 matches;
#   4. prints what the wizard will ask for, runs the wizard, then runs `zsp check`.
#
# The script never reads or asks for a secret. The build takes the upload key from
# android/key.properties or the SYMUDOL_UPLOAD_* variables, as documentation/releasing.md
# describes, and you type the keystore password and the publisher nsec into zsp yourself.
# See "Publishing from CI" in documentation/releasing.md.
#
# Usage:
#   tools/zapstore_c1_proof.sh [--no-build]
#
#   --no-build  use the existing build/app/outputs/flutter-apk/symudol.apk instead of building one

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release.yml"
APK="$ROOT/build/app/outputs/flutter-apk/symudol.apk"
BUILD=1

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    -h|--help) sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $arg (see --help)" ;;
  esac
done

[ -t 0 ] && [ -t 1 ] || die "run this in a terminal: zsp's setup wizard is interactive."
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] \
  || die "the release workflow pins zsp for linux-amd64 only; run this on the Linux release machine."
cd "$ROOT"

step "Checking the checkout"
# The wizard can publish this build as Symudol's first Zapstore release, so it must be a release.
tag="$(git describe --exact-match --tags --match 'v*' HEAD 2>/dev/null || true)"
if [ -z "$tag" ]; then
  die "HEAD is not a release tag. Check out the release first, for example: git checkout v1.0.0"
fi
[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || die "the checkout has uncommitted changes; the build must be exactly $tag."
echo "Release: $tag"

step "Checking zapstore.yaml"
npub="$(awk '/^pubkey:/ {print $2}' zapstore.yaml)"
case "$npub" in
  npub1*PLACEHOLDER*|"") die "zapstore.yaml has no real pubkey; put the publisher's npub there first." ;;
  npub1*) echo "Publisher: $npub" ;;
  *) die "zapstore.yaml pubkey is not an npub: $npub" ;;
esac

# The pins live in the release workflow, so this script always uses what CI uses.
zsp_url="$(grep -oE 'https://github\.com/zapstore/zsp/releases/download/[^ ]+' "$WORKFLOW" | head -n 1)"
zsp_sha="$(awk '/ZSP_SHA256:/ {print $2}' "$WORKFLOW" | head -n 1)"
upload_digest="$(grep -oE 'expected="[0-9a-f]{64}"' "$WORKFLOW" | head -n 1 | cut -d'"' -f2)"
[ -n "$zsp_url" ] && [ -n "$zsp_sha" ] && [ -n "$upload_digest" ] \
  || die "could not read the zsp pin or the upload key digest from $WORKFLOW."

# The build signs with the upload key only when all four settings are present, each from its
# SYMUDOL_UPLOAD_* variable or android/key.properties (android/app/build.gradle.kts). Otherwise
# it signs with the debug key and writes no symudol.apk, so check first. Only the presence of
# each setting is tested; no value is read into this script or printed.
upload_setting_present() { # <key.properties name> <variable>
  [ -n "${!2:-}" ] || { [ -f android/key.properties ] && grep -qE "^$1=.+" android/key.properties; }
}
missing=()
upload_setting_present storeFile SYMUDOL_UPLOAD_STORE_FILE || missing+=(storeFile/SYMUDOL_UPLOAD_STORE_FILE)
upload_setting_present storePassword SYMUDOL_UPLOAD_STORE_PASSWORD || missing+=(storePassword/SYMUDOL_UPLOAD_STORE_PASSWORD)
upload_setting_present keyAlias SYMUDOL_UPLOAD_KEY_ALIAS || missing+=(keyAlias/SYMUDOL_UPLOAD_KEY_ALIAS)
upload_setting_present keyPassword SYMUDOL_UPLOAD_KEY_PASSWORD || missing+=(keyPassword/SYMUDOL_UPLOAD_KEY_PASSWORD)

if [ "$BUILD" = 1 ]; then
  [ "${#missing[@]}" -eq 0 ] || die "the upload key is not set up, so the build would be debug-signed.
Missing: ${missing[*]}
Create android/key.properties from android/key.properties.example (it is gitignored), or export
the SYMUDOL_UPLOAD_* variables, as \"Building and signing a release\" in documentation/releasing.md
describes. Then run this script again."
  step "Building symudol.apk with the upload key"
  command -v flutter >/dev/null || die "flutter is not on PATH."
  flutter build apk --release
fi
[ -f "$APK" ] || die "$APK is missing. Build it with the upload key: run this script without \
--no-build."

step "Checking symudol.apk is signed with the upload key"
android_home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
build_tools="$(ls -d "$android_home"/build-tools/* 2>/dev/null | sort -V | tail -n 1)"
[ -x "$build_tools/apksigner" ] || die "apksigner not found under $android_home/build-tools; set ANDROID_HOME."
digest="$("$build_tools/apksigner" verify --print-certs "$APK" \
  | awk '/certificate SHA-256 digest/ {print $NF; exit}')"
[ "$digest" = "$upload_digest" ] \
  || die "symudol.apk is signed by $digest, not the upload key ($upload_digest)."
echo "Signer is the upload key."

step "Downloading zsp ($zsp_url)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
zsp="$work/zsp"
curl -fsSL -o "$zsp" "$zsp_url"
echo "$zsp_sha  $zsp" | sha256sum -c - >/dev/null || die "zsp does not match the SHA-256 pinned in $WORKFLOW."
chmod +x "$zsp"
echo "zsp checksum verified."

store_file="${SYMUDOL_UPLOAD_STORE_FILE:-}"
if [ -z "$store_file" ] && [ -f android/key.properties ]; then
  store_file="$(sed -n 's/^storeFile=//p' android/key.properties | head -n 1)"
fi

step "Starting zsp's setup wizard"
cat <<EOF
When the wizard asks, give it:
  Nostr identity:  the Diogel Zapstore publisher, $npub
                   (its nsec; never the app's or a personal key)
  APK:             $APK
  Keystore:        ${store_file:-the upload keystore, symudol-upload.p12}
  Key alias:       symudol-upload  (the upload key, not symudol-app-signing)
If it offers "Publish Symudol ${tag#v} now?", Zapstore doesn't list Symudol yet: choose
"Publish now". The proof goes out with this first release, and nothing else can publish it.
The passwords and the nsec are typed into zsp only; this script never sees them.

EOF
read -r -p "Press Enter to start the wizard, or Ctrl+C to stop. " _
"$zsp"

step "Checking the proof with zsp check"
"$zsp" check
echo
echo "Note the proof's expiry above. CI cannot renew it: run this script again from the latest"
echo "release tag in the 30 days before it expires."
