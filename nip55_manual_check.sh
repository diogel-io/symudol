#!/bin/bash
# Manual NIP-55 verification helper.
# Mirrors the scenarios documented in documentation/nip55-manual-verification.md.
# Requires an emulator/device with Diogel installed (see fix_emulators.sh / new.sh).
#
# Usage:
#   ./nip55_manual_check.sh <scenario> [active-pubkey]
#
# Scenarios:
#   get_public_key            - connect request while unlocked
#   sign_event                 - sign_event request while unlocked (needs pubkey)
#   malformed                  - sign_event with malformed content (needs pubkey)
#   pubkey_mismatch             - sign_event with a pubkey that won't match the identity
#   current_user_mismatch       - sign_event with a current_user that won't match the identity
#
# Set ADB_DEVICE to target a specific device/emulator (passed as `adb -s $ADB_DEVICE`).

set -euo pipefail

PACKAGE="io.threenine.diogel"
ADB=(adb)
if [ -n "${ADB_DEVICE:-}" ]; then
  ADB=(adb -s "$ADB_DEVICE")
fi

scenario="${1:-}"
pubkey="${2:-}"

require_pubkey() {
  if [ -z "$pubkey" ]; then
    echo "Scenario '$scenario' requires the active Diogel identity pubkey as the second argument." >&2
    exit 1
  fi
}

case "$scenario" in
  get_public_key)
    "${ADB[@]}" shell am start \
      -a android.intent.action.VIEW \
      -d 'nostrsigner:' \
      --es type get_public_key \
      "$PACKAGE"
    ;;

  sign_event)
    require_pubkey
    "${ADB[@]}" shell am start \
      -a android.intent.action.VIEW \
      -d 'nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A%22hello%20from%20nip55%22%2C%22tags%22%3A%5B%5D%7D' \
      --es type sign_event \
      --es id test-event-1 \
      --es current_user "$pubkey" \
      "$PACKAGE"
    ;;

  malformed)
    require_pubkey
    "${ADB[@]}" shell am start \
      -a android.intent.action.VIEW \
      -d 'nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A42%2C%22tags%22%3A%5B%5D%7D' \
      --es type sign_event \
      --es id malformed-content \
      --es current_user "$pubkey" \
      "$PACKAGE"
    ;;

  pubkey_mismatch)
    require_pubkey
    "${ADB[@]}" shell am start \
      -a android.intent.action.VIEW \
      -d 'nostrsigner:%7B%22kind%22%3A1%2C%22pubkey%22%3A%22bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb%22%2C%22content%22%3A%22bad%20pubkey%22%2C%22tags%22%3A%5B%5D%7D' \
      --es type sign_event \
      --es id pubkey-mismatch \
      --es current_user "$pubkey" \
      "$PACKAGE"
    ;;

  current_user_mismatch)
    "${ADB[@]}" shell am start \
      -a android.intent.action.VIEW \
      -d 'nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A%22wrong%20account%22%2C%22tags%22%3A%5B%5D%7D' \
      --es type sign_event \
      --es id current-user-mismatch \
      --es current_user bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
      "$PACKAGE"
    ;;

  *)
    echo "Usage: $0 <scenario> [active-pubkey]" >&2
    echo "Scenarios: get_public_key, sign_event, malformed, pubkey_mismatch, current_user_mismatch" >&2
    exit 1
    ;;
esac
