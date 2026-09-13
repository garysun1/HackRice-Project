#!/bin/bash
# Simulator lifecycle for the Interim overnight build. Fully headless — never launches Simulator.app.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.garysun.healthapp"
SIM_NAME="HackRice"
UDID_FILE=".build/sim-udid"
APP_PATH=".build/DerivedData/Build/Products/Debug-iphonesimulator/HealthApp.app"
mkdir -p .build/logs .build/screenshots

udid() { cat "$UDID_FILE"; }

case "${1:-}" in
  up)
    if [[ -f "$UDID_FILE" ]] && xcrun simctl list devices -j | grep -q "$(cat "$UDID_FILE")"; then
      UDID=$(udid)
    else
      RUNTIME=$(xcrun simctl list runtimes -j | jq -r '[.runtimes[] | select(.platform=="iOS" and .isAvailable)] | sort_by(.version) | last.identifier')
      [[ "$RUNTIME" != "null" && -n "$RUNTIME" ]] || { echo "FAIL: no iOS runtime installed"; exit 1; }
      DEVTYPE=$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.name | test("^iPhone [0-9]+ Pro$"))] | last.identifier')
      UDID=$(xcrun simctl create "$SIM_NAME" "$DEVTYPE" "$RUNTIME")
      echo "$UDID" > "$UDID_FILE"
      echo "created $SIM_NAME ($UDID)"
    fi
    xcrun simctl bootstatus "$UDID" -b
    echo "booted $UDID"
    ;;
  install)
    xcrun simctl terminate "$(udid)" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$(udid)" "$APP_PATH"
    xcrun simctl privacy "$(udid)" grant microphone "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl privacy "$(udid)" grant calendar "$BUNDLE_ID" 2>/dev/null || true
    echo "installed + mic/calendar granted"
    ;;
  launch)
    shift
    # Always relaunch fresh — a running instance keeps its OLD launch flags.
    xcrun simctl terminate "$(udid)" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$(udid)" "$BUNDLE_ID" "$@"
    ;;
  shot)
    OUT="${2:-.build/screenshots/$(date +%H%M%S).png}"
    xcrun simctl io "$(udid)" screenshot "$OUT" >/dev/null
    echo "$OUT"
    ;;
  logs)
    xcrun simctl spawn "$(udid)" log show --last "${2:-2m}" --style compact \
      --predicate 'subsystem == "com.garysun.healthapp"' 2>/dev/null | tail -50
    ;;
  reset)
    xcrun simctl terminate "$(udid)" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl uninstall "$(udid)" "$BUNDLE_ID" 2>/dev/null || true
    echo "app state reset (reinstall with: sim.sh install)"
    ;;
  reboot)
    xcrun simctl shutdown "$(udid)" 2>/dev/null || true
    xcrun simctl bootstatus "$(udid)" -b
    ;;
  erase)
    xcrun simctl shutdown "$(udid)" 2>/dev/null || true
    xcrun simctl erase "$(udid)"
    xcrun simctl bootstatus "$(udid)" -b
    echo "erased + rebooted (permissions cleared — reinstall re-grants mic)"
    ;;
  recreate)
    xcrun simctl shutdown "$(udid)" 2>/dev/null || true
    xcrun simctl delete "$(udid)" 2>/dev/null || true
    rm -f "$UDID_FILE"
    "$0" up
    ;;
  *)
    echo "usage: sim.sh up|install|launch [args]|shot [path]|logs [window]|reset|reboot|erase|recreate"
    exit 1
    ;;
esac
