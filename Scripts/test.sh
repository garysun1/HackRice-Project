#!/bin/bash
# Run app tests against the booted simulator. Usage: test.sh [unit|ui|all]
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=$(cat .build/sim-udid)
SUITE="${1:-unit}"
mkdir -p .build/logs .build/results
RESULT=".build/results/run-$(date +%H%M%S).xcresult"

ONLY=()
case "$SUITE" in
  unit) ONLY=(-only-testing:AppTests) ;;
  ui)   ONLY=(-only-testing:AppUITests) ;;
  all)  ;;
esac

gtimeout 540 env NSUnbufferedIO=YES xcodebuild build-for-testing \
  -project HealthApp.xcodeproj -scheme HealthApp \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SPM \
  -skipPackagePluginValidation -skipMacroValidation \
  2>&1 | tee .build/logs/test-build-latest.log | xcbeautify --quiet

gtimeout 900 env NSUnbufferedIO=YES xcodebuild test-without-building \
  -project HealthApp.xcodeproj -scheme HealthApp \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath .build/DerivedData \
  -resultBundlePath "$RESULT" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  ${ONLY[@]+"${ONLY[@]}"} \
  2>&1 | tee .build/logs/test-latest.log | xcbeautify --quiet

echo "--- summary ---"
xcrun xcresulttool get test-results summary --path "$RESULT" 2>/dev/null | jq '{result, totalTestCount, passedTests, failedTests}' \
  || grep -E "Test Suite|tests? (passed|failed)" .build/logs/test-latest.log | tail -5
echo "RESULT: $RESULT"
