#!/usr/bin/env bash
# Device-level NIP-55 checks with the test client (diogel-io/symudol#69).
#
# Installs Symudol and tools/nip55-test-client on an attached device or emulator, runs every
# scenario through adb, and prints a pass/fail summary. Each scenario reports its own verdict to
# logcat (tag Nip55Test); this script only starts them and reads the verdicts.
#
# Semi-attended: scenarios that need an approval in Symudol pause for it, and say what to tap.
# See documentation/nip55-device-checks.md.
#
# Usage:
#   ./nip55_device_check.sh [--symudol-apk PATH] [--client-apk PATH] [--keep-data] [--yes]
#                           [--only SCENARIO]...
#
#   --symudol-apk PATH  Symudol APK to install (default: build one with `flutter build apk --debug`)
#   --client-apk PATH   test-client APK to install (default: build one with Gradle)
#   --keep-data         don't clear Symudol's data first (grants from earlier runs then remain,
#                       so provider_before_grant can fail)
#   --yes               don't ask before clearing Symudol's data
#   --only SCENARIO     run only this scenario; repeatable
#
# Set ADB_DEVICE to target a specific device or emulator (passed as `adb -s $ADB_DEVICE`).

set -euo pipefail

SYMUDOL_PACKAGE="io.diogel.symudol"
CLIENT_PACKAGE="io.diogel.nip55testclient"
CLIENT_ACTIVITY="$CLIENT_PACKAGE/.ScenarioActivity"
TAG="Nip55Test"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$ROOT/tools/nip55-test-client"

# The order matters: the provider checks after a grant use the grants the intent scenarios
# remember. Kept in step with Scenarios.all in the client.
SCENARIOS=(
  provider_before_grant
  provider_broad_grant
  intent_get_public_key
  intent_sign_event
  intent_sign_message
  intent_nip44_round_trip
  intent_nip04_round_trip
  provider_after_grant
  intent_sign_message_event_serialisation
  provider_sign_message_event_serialisation
  intent_forged_identity
  browser_callback
)

# What the operator does in Symudol while a scenario runs. Empty: nothing, it runs unattended.
hint() {
  case "$1" in
    provider_broad_grant)
      echo "Approve the login, including the permission to sign any kind of event, and remember it." ;;
    intent_get_public_key)
      echo "Approve sharing the public key and remember it (it may complete without asking)." ;;
    intent_sign_event)
      echo "Approve signing the kind 1 event and remember it for kind 1." ;;
    intent_sign_message)
      echo "Approve signing the message and remember it." ;;
    intent_nip44_round_trip)
      echo "Approve NIP-44 encrypt, then NIP-44 decrypt; remember both." ;;
    intent_nip04_round_trip)
      echo "Approve NIP-04 encrypt, then NIP-04 decrypt; remember both." ;;
    provider_after_grant)
      echo "Nothing to tap. Keep Symudol unlocked." ;;
    intent_sign_message_event_serialisation)
      echo "Symudol should refuse this by itself. Do not approve anything. Waits up to 30 s." ;;
    intent_forged_identity)
      echo "On a fixed build nothing appears: wait 30 s. If Symudol asks to share your key with Amethyst, approve it (that is the bug)." ;;
    browser_callback)
      echo "Approve signing the event. Symudol then opens the client's callback." ;;
    *) echo "" ;;
  esac
}

# Longest each scenario may take, in seconds: the client's own timeout plus some slack.
timeout_for() {
  case "$1" in
    provider_before_grant | provider_sign_message_event_serialisation) echo 40 ;;
    intent_sign_message_event_serialisation | intent_forged_identity) echo 45 ;;
    provider_after_grant) echo 75 ;;
    provider_broad_grant) echo 165 ;;
    intent_nip44_round_trip | intent_nip04_round_trip) echo 195 ;;
    *) echo 135 ;;
  esac
}

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

symudol_apk=""
client_apk=""
keep_data=false
assume_yes=false
only=()

while [ $# -gt 0 ]; do
  case "$1" in
    --symudol-apk) symudol_apk="${2:?--symudol-apk needs a path}"; shift 2 ;;
    --client-apk) client_apk="${2:?--client-apk needs a path}"; shift 2 ;;
    --keep-data) keep_data=true; shift ;;
    --yes) assume_yes=true; shift ;;
    --only) only+=("${2:?--only needs a scenario}"); shift 2 ;;
    -h | --help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 >&2 ;;
  esac
done

if [ ${#only[@]} -gt 0 ]; then
  for scenario in "${only[@]}"; do
    case " ${SCENARIOS[*]} " in
      *" $scenario "*) ;;
      *) echo "Unknown scenario: $scenario" >&2; exit 1 ;;
    esac
  done
  SCENARIOS=("${only[@]}")
fi

ADB=(adb)
if [ -n "${ADB_DEVICE:-}" ]; then
  ADB=(adb -s "$ADB_DEVICE")
fi

command -v adb >/dev/null || { echo "adb is not on PATH." >&2; exit 1; }
if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
  echo "No device: attach one or start an emulator (set ADB_DEVICE if several are attached)." >&2
  exit 1
fi

# ── APKs ─────────────────────────────────────────────────────────────────────

if [ -z "$symudol_apk" ]; then
  echo "Building Symudol (flutter build apk --debug)…"
  (cd "$ROOT" && flutter build apk --debug)
  symudol_apk="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
fi
if [ -z "$client_apk" ]; then
  echo "Building the test client (gradlew assembleDebug)…"
  (cd "$CLIENT_DIR" && ./gradlew assembleDebug --console=plain -q)
  client_apk="$CLIENT_DIR/app/build/outputs/apk/debug/app-debug.apk"
fi
for apk in "$symudol_apk" "$client_apk"; do
  [ -f "$apk" ] || { echo "No APK at $apk" >&2; exit 1; }
done

if ! $keep_data && ! $assume_yes; then
  device="$("${ADB[@]}" shell getprop ro.product.model | tr -d '\r')"
  read -r -p "This clears Symudol's data on $device: its identities and grants. Continue? [y/N] " reply
  case "$reply" in
    y | Y | yes) ;;
    *) echo "Stopped. Use --keep-data to keep Symudol's data."; exit 1 ;;
  esac
fi

echo "Installing $symudol_apk"
"${ADB[@]}" install -r -t "$symudol_apk" >/dev/null
echo "Installing $client_apk"
"${ADB[@]}" install -r -t "$client_apk" >/dev/null

if ! $keep_data; then
  "${ADB[@]}" shell pm clear "$SYMUDOL_PACKAGE" >/dev/null
fi
# A fresh client: no public key left over from an earlier run.
"${ADB[@]}" shell pm clear "$CLIENT_PACKAGE" >/dev/null

echo
echo "In Symudol, create or import an identity and unlock the vault."
"${ADB[@]}" shell monkey -p "$SYMUDOL_PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
read -r -p "Press Enter when Symudol is unlocked. " _

# ── Scenarios ────────────────────────────────────────────────────────────────

# The verdict line for $1 since the last `logcat -c`, or nothing yet.
verdict() {
  "${ADB[@]}" logcat -d -v raw -s "$TAG:I" | tr -d '\r' | grep -m1 "^RESULT $1 " || true
}

names=()
verdicts=()
reasons=()

for scenario in "${SCENARIOS[@]}"; do
  echo
  echo "▶ $scenario"
  what="$(hint "$scenario")"
  [ -n "$what" ] && echo "  $what"

  "${ADB[@]}" logcat -c
  "${ADB[@]}" shell am start -n "$CLIENT_ACTIVITY" --es scenario "$scenario" >/dev/null

  line=""
  deadline=$((SECONDS + $(timeout_for "$scenario")))
  while [ -z "$line" ] && [ $SECONDS -lt $deadline ]; do
    sleep 1
    line="$(verdict "$scenario")"
  done

  if [ -z "$line" ]; then
    result="FAIL"
    reason="no verdict from the client within $(timeout_for "$scenario") s"
  else
    # RESULT <id> <PASS|FAIL> <reason>
    result="$(echo "$line" | cut -d' ' -f3)"
    reason="$(echo "$line" | cut -d' ' -f4-)"
  fi
  echo "  $result: $reason"
  names+=("$scenario")
  verdicts+=("$result")
  reasons+=("$reason")
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo
echo "Summary"
failed=0
for i in "${!names[@]}"; do
  printf '  %-4s  %-42s %s\n' "${verdicts[$i]}" "${names[$i]}" "${reasons[$i]}"
  [ "${verdicts[$i]}" = "PASS" ] || failed=$((failed + 1))
done
echo
echo "$(( ${#names[@]} - failed )) passed, $failed failed."
[ "$failed" -eq 0 ]
