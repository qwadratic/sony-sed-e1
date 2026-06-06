#!/usr/bin/env bash
# setup-emulator.sh — create AVD, install Sony APKs, forward MONITOR_SOCKET to TCP
# Usage: ./scripts/setup-emulator.sh [--headless]
set -euo pipefail

SDK=/opt/homebrew/share/android-commandlinetools
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APK_DIR="$REPO/Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/apks"
MAIN_APK="$REPO/com.sony.smarteyeglass_1.3.17052901-24_minAPI19(armeabi-v7a)(nodpi)_apkmirror.com.apk"
LIVEWARE_APK="$REPO/com.sonyericsson.extras.liveware_5.7.36.0001-507360001_minAPI16(nodpi)_apkmirror.com.apk"
EMU_APK="$APK_DIR/SmartEyeglassEmulator.apk"
AVD_NAME="SmartEyeglass_AVD"
LOCAL_PORT=7002
HEADLESS="${1:-}"

export ANDROID_SDK_ROOT="$SDK"
export ANDROID_HOME="$SDK"
PATH="$SDK/cmdline-tools/latest/bin:$SDK/emulator:$SDK/platform-tools:$PATH"

echo "=== SmartEyeglass Emulator Setup ==="
echo "SDK: $SDK"
echo "Local port: $LOCAL_PORT"

# ── Create AVD if not exists ──────────────────────────────────────────────────
if ! avdmanager list avd | grep -q "$AVD_NAME"; then
  echo "Creating AVD: $AVD_NAME (API 21, x86, google_apis)..."
  echo "no" | avdmanager create avd \
    --name "$AVD_NAME" \
    --package "system-images;android-21;google_apis;x86" \
    --abi x86 \
    --device "Nexus 5" \
    --force
  echo "AVD created."
else
  echo "AVD $AVD_NAME already exists — skipping creation."
fi

# ── Start emulator ────────────────────────────────────────────────────────────
if ! adb devices | grep -q "emulator"; then
  echo "Starting emulator..."
  if [[ "$HEADLESS" == "--headless" || "$HEADLESS" == "-h" ]]; then
    "$SDK/emulator/emulator" -avd "$AVD_NAME" \
      -no-window -no-audio -no-snapshot-save \
      -gpu swiftshader_indirect &
  else
    "$SDK/emulator/emulator" -avd "$AVD_NAME" \
      -no-audio -no-snapshot-save \
      -gpu swiftshader_indirect &
  fi
  EMU_PID=$!
  echo "Emulator started (PID $EMU_PID). Waiting for boot..."
else
  echo "Emulator already running."
fi

# ── Wait for boot ─────────────────────────────────────────────────────────────
echo -n "Waiting for device..."
adb wait-for-device
for i in $(seq 1 60); do
  BOOT=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [[ "$BOOT" == "1" ]] && break
  echo -n "."
  sleep 2
done
echo " booted."

# ── Install APKs ─────────────────────────────────────────────────────────────
echo "Installing Sony APKs..."

# LiveWare extension manager (required by MisiAha daemon)
if [[ -f "$LIVEWARE_APK" ]]; then
  echo "  → LiveWare..."
  adb install -r "$LIVEWARE_APK" 2>/dev/null || echo "  (LiveWare already installed or failed — continuing)"
fi

# MisiAha daemon
if [[ -f "$MAIN_APK" ]]; then
  echo "  → SmartEyeglass daemon (MisiAha)..."
  adb install -r "$MAIN_APK" 2>/dev/null || echo "  (MisiAha already installed or failed — continuing)"
fi

# SmartEyeglassEmulator
if [[ -f "$EMU_APK" ]]; then
  echo "  → SmartEyeglassEmulator..."
  adb install -r "$EMU_APK" 2>/dev/null || echo "  (Emulator APK already installed or failed — continuing)"
else
  echo "  WARNING: SmartEyeglassEmulator.apk not found at $EMU_APK"
fi

# ── Start emulator app ────────────────────────────────────────────────────────
echo "Starting SmartEyeglassEmulator app..."
adb shell am start -n "com.sony.smarteyeglass.emulator/.MainActivity" 2>/dev/null || \
  echo "  (could not auto-start — open manually in emulator)"

sleep 2

# ── Forward UNIX socket to TCP ────────────────────────────────────────────────
echo "Forwarding MONITOR_SOCKET → tcp:$LOCAL_PORT..."
adb forward tcp:$LOCAL_PORT localabstract:com.sony.smarteyeglass.MONITOR_SOCKET

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Emulator ready."
echo "   Connect glasses-tool:"
echo "   ./macos-middleware/glasses-tool --local 127.0.0.1:$LOCAL_PORT"
echo ""
echo "   Run tests:"
echo "   uv run pytest tests/ -v --local 127.0.0.1:$LOCAL_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
