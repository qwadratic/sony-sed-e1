#!/bin/bash
# watch-for-glasses.sh
# Polls until SmartEyeglass appears in BT, then auto-runs glasses-tool

TOOL="$(dirname "$0")/glasses-tool"
INTERVAL=3

echo "👓 Watching for SmartEyeglass..."
echo "   Power on glasses: slide POWER switch 4+ seconds"
echo "   Press Ctrl-C to stop"
echo ""

while true; do
    # Check paired devices
    ADDR=$(blueutil --paired 2>/dev/null | grep -i "smarteyeglass\|SED-E1\|sony" | grep -oE '[0-9a-f]{2}(-[0-9a-f]{2}){5}' | head -1)
    
    if [ -n "$ADDR" ]; then
        echo "✅ Found in paired list: $ADDR"
        echo "Running: $TOOL sdp $ADDR"
        "$TOOL" sdp "$ADDR"
        echo ""
        echo "Running: $TOOL probe $ADDR"
        "$TOOL" probe "$ADDR"
        echo ""
        echo "Connecting (Ctrl-C to stop)..."
        "$TOOL" connect "$ADDR"
        exit 0
    fi
    
    # Also scan for new devices
    FOUND=$(blueutil --inquiry 2 2>/dev/null | grep -i "smarteyeglass\|SED-E1")
    if [ -n "$FOUND" ]; then
        ADDR=$(echo "$FOUND" | grep -oE '[0-9a-f]{2}(-[0-9a-f]{2}){5}' | head -1)
        echo "✅ Discovered: $FOUND"
        echo ""
        echo "Pair in System Settings → Bluetooth first, then re-run this script."
        echo "Or run: ./glasses-tool connect $ADDR"
        exit 0
    fi
    
    printf "."
    sleep $INTERVAL
done