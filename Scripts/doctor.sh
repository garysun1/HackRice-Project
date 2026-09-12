#!/bin/bash
# 3am failure-recovery ladder. Run one level at a time: doctor.sh <level>
#   1 app-reset   2 sim-reboot   3 sim-erase   4 sim-recreate   5 kill-coresim   6 nuke-derived
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  1|app-reset)    Scripts/sim.sh reset && Scripts/sim.sh install ;;
  2|sim-reboot)   Scripts/sim.sh reboot ;;
  3|sim-erase)    Scripts/sim.sh erase && Scripts/sim.sh install ;;
  4|sim-recreate) Scripts/sim.sh recreate ;;
  5|kill-coresim)
    pkill -9 -f xcodebuild 2>/dev/null || true
    killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
    sleep 3
    Scripts/sim.sh up
    ;;
  6|nuke-derived)
    rm -rf .build/DerivedData .build/SPM
    echo "DerivedData + SPM caches removed; next build is clean"
    ;;
  *)
    echo "usage: doctor.sh 1-6 (escalate in order; if all fail, fall back to: swift test --package-path HealthCore)"
    exit 1
    ;;
esac
