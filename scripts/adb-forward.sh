#!/usr/bin/env bash
# adb-forward.sh — (re)establish ADB socket forward without full emulator setup
# Run this after emulator is already booted and APKs installed.
set -euo pipefail

PORT="${1:-7002}"
adb forward tcp:$PORT localabstract:com.sony.smarteyeglass.MONITOR_SOCKET
echo "Forwarded: tcp:$PORT → localabstract:com.sony.smarteyeglass.MONITOR_SOCKET"
echo "Connect: ./macos-middleware/glasses-tool --local 127.0.0.1:$PORT"
