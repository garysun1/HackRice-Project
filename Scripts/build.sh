#!/bin/bash
# Build Interim for the dedicated simulator. Parseable output, hang-proof.
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=$(cat .build/sim-udid)
mkdir -p .build/logs
LOG=".build/logs/build-$(date +%H%M%S).log"

gtimeout 540 env NSUnbufferedIO=YES xcodebuild build \
  -project HealthApp.xcodeproj -scheme HealthApp \
  -destination "platform=iOS Simulator,id=$UDID" -destination-timeout 120 \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SPM \
  -skipPackagePluginValidation -skipMacroValidation \
  2>&1 | tee "$LOG" | xcbeautify --quiet
echo "BUILD OK ($LOG)"
