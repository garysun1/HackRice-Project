#!/bin/bash
# Pre-bed verification: everything an unattended overnight run needs, checked while a human is still awake.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { echo; echo "== $1"; }

step "1/7 Xcode active + licensed"
[[ "$(xcode-select -p)" == /Applications/Xcode.app/* ]] || { echo "FAIL: run  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; exit 1; }
xcodebuild -version || { echo "FAIL: license? run  sudo xcodebuild -license accept"; exit 1; }

step "2/7 iOS simulator runtime present"
xcrun simctl list runtimes -j | jq -e '[.runtimes[] | select(.platform=="iOS" and .isAvailable)] | length > 0' >/dev/null \
  || { echo "FAIL: no iOS runtime. Run:  xcodebuild -downloadPlatform iOS"; exit 1; }
xcrun simctl list runtimes | grep iOS

step "3/7 CLI tools"
for tool in xcodegen xcbeautify gtimeout jq; do
  command -v "$tool" >/dev/null || { echo "FAIL: $tool missing (brew install xcodegen xcbeautify coreutils jq)"; exit 1; }
done
echo "xcodegen/xcbeautify/gtimeout/jq OK"

step "4/7 Simulator keyboard settings (UI-test flake prevention)"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
echo "hardware keyboard disconnected"

step "5/7 Dedicated simulator boots"
Scripts/sim.sh up

step "6/7 Project generates + builds"
xcodegen generate
Scripts/build.sh

step "7/7 App installs, launches, screenshots"
Scripts/sim.sh install
Scripts/sim.sh launch --mock-speech -demoMode
sleep 4
Scripts/sim.sh shot .build/screenshots/preflight-smoke.png
echo
echo "PREFLIGHT GREEN — safe to sleep. Screenshot: .build/screenshots/preflight-smoke.png"
