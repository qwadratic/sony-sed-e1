#!/bin/bash
# glasses-wifi-setup.sh — Sony SED-E1 WiFi hotspot setup
# Usage: sudo ./glasses-wifi-setup.sh [start|stop|status]
# Requires sudo — writes /Library/Preferences/SystemConfiguration/com.apple.nat.plist

SSID="DIRECT-ma-SonyGlasses"
PASSWORD="sony1234"
WIFI_UUID="19ABF24D-BA16-4A82-B6AE-37EC82632230"   # Wi-Fi (en0) on this Mac
NAT_PLIST="/Library/Preferences/SystemConfiguration/com.apple.nat.plist"

if [[ $EUID -ne 0 ]]; then
    echo "❌  Run with sudo: sudo $0 ${1:-start}"
    exit 1
fi

case "${1:-start}" in
start)
    echo "📡  Writing hotspot config: SSID=$SSID  pass=$PASSWORD"
    cat > "$NAT_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NAT</key>
    <dict>
        <key>AirPort</key>
        <dict>
            <key>SharingNetworkName</key>
            <string>$SSID</string>
            <key>SharingNetworkPassword</key>
            <string>$PASSWORD</string>
        </dict>
        <key>Enabled</key>
        <integer>1</integer>
        <key>PrimaryService</key>
        <string>$WIFI_UUID</string>
        <key>SharingDevices</key>
        <array>
            <string>$WIFI_UUID</string>
        </array>
        <key>SharingNetworkNumberStart</key>
        <string>192.168.2.1</string>
        <key>SharingNetworkMask</key>
        <string>255.255.255.0</string>
    </dict>
</dict>
</plist>
PLIST

    echo "🔄  Restarting Internet Sharing daemon..."
    launchctl kickstart -k system/com.apple.NetworkSharing 2>/dev/null || \
        launchctl load -w /System/Library/LaunchDaemons/com.apple.NetworkSharing.plist 2>/dev/null

    echo "⏳  Waiting for bridge100..."
    for i in $(seq 1 10); do
        sleep 1
        IP=$(ipconfig getifaddr bridge100 2>/dev/null)
        if [[ -n "$IP" ]]; then
            echo ""
            echo "✅  Hotspot UP"
            echo "    SSID    : $SSID"
            echo "    Password: $PASSWORD"
            echo "    macOS IP: $IP  (this is your goAddr for wifi connect)"
            echo ""
            echo "Next steps:"
            echo "  1. Run ./glasses-tool  (BT connects, GoL starts)"
            echo "  2. Type: wifi on"
            echo "  3. Type: wifi connect $SSID $PASSWORD $IP"
            echo "  4. Type: wifi switch"
            exit 0
        fi
        printf "."
    done
    echo ""
    echo "⚠️   bridge100 not up after 10s. Check System Settings → Sharing → Internet Sharing."
    echo "    If the toggle is OFF, turn it ON manually — then re-run this script."
    ;;

stop)
    echo "🛑  Stopping Internet Sharing..."
    launchctl unload /System/Library/LaunchDaemons/com.apple.NetworkSharing.plist 2>/dev/null || true
    echo "✅  Stopped"
    ;;

status)
    IP=$(ipconfig getifaddr bridge100 2>/dev/null || echo "not active")
    echo "bridge100 : $IP"
    ifconfig ap1 2>/dev/null | grep -E 'status|ssid' || echo "ap1       : not active"
    echo ""
    echo "Connected clients (ARP):"
    arp -an 2>/dev/null | grep "192.168.2" || echo "  (none yet)"
    ;;

*)
    echo "Usage: sudo $0 [start|stop|status]"
    exit 1
    ;;
esac
