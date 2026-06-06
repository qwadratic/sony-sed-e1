#!/usr/bin/env bash
# teardown-emulator.sh — kill emulator + remove ADB forwards
set -euo pipefail
adb forward --remove-all 2>/dev/null || true
adb emu kill 2>/dev/null || true
pkill -f "emulator.*SmartEyeglass" 2>/dev/null || true
echo "Emulator stopped, forwards removed."
