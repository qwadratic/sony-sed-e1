# Sony SED-E1 SmartEyeglass — Swift SDK

Reverse-engineered Swift SDK for Sony SmartEyeglass SED-E1. Connects directly from macOS via Bluetooth RFCOMM — no Android phone or Sony HostApp needed.

**SEGKit** (SDK library) + **SEGExplorer** (demo app with 9 interactive demos).

> Wire protocol reverse-engineered from Sony's Android APKs via smali/DEX analysis.
> Reference Java sources: [github.com/kaustubhcs/Sony](https://github.com/kaustubhcs/Sony)
> Original APKs: [apkmirror.com/sony-semiconductor-solutions-corporation/smarteyeglass](https://www.apkmirror.com/apk/sony-semiconductor-solutions-corporation/smarteyeglass/) (two versions exist — unclear which matches the Java source)

## Quick Start

```bash
# Build
cd SEGKit && swift build
cd SEGExplorer && swift build

# Connect via Bluetooth (interactive device picker)
swift run SEGExplorer --bt

# Connect to specific device
swift run SEGExplorer --bt --address ac:9b:0a:37:a6:6b

# Debug wire logging
swift run SEGExplorer --bt --debug
```

## Architecture

```
SEGKit/                    # SDK library — wire protocol, transports, subsystems
├── Sources/SEGKit/
│   ├── GlassesConnection  # Public API entry point
│   ├── ProtocolActor      # Handshake FSM + frame routing
│   ├── TransportActor     # BT RFCOMM / WiFi TCP / local TCP
│   ├── BluetoothBridge    # IOBluetooth ↔ actor bridge
│   ├── DisplaySubsystem   # DEFLATE-compressed 419×138 monochrome bitmaps
│   ├── CameraSubsystem    # JPEG capture + streaming
│   ├── SensorSubsystem    # IMU, light, battery sensors
│   ├── InputSubsystem     # Tap, swipe, jog wheel, buttons
│   ├── WifiSubsystem      # BT→WiFi upgrade path
│   ├── CommandConstants    # All 80+ wire command IDs
│   └── EventLogger        # Persistent JSONL event logging

SEGExplorer/               # Demo app — 9 demos exercising all SDK features
├── Sources/SEGExplorer/
│   ├── main.swift          # CLI entry + REPL
│   ├── ExplorerApp.swift   # Onboarding + demo lifecycle
│   └── Demos/              # Text, Animation, Graphics, Touch,
│                           # Sensor, CameraCapture, CameraStream, AR, Audio
```

## Hardware

| Spec | Value |
|------|-------|
| Display | 419×138 monochrome green OLED, 8-bit grayscale |
| Camera | 1.3MP CMOS, JPEG output, QVGA streaming |
| IMU | BMI160: accelerometer + gyroscope + magnetometer |
| Touch | Capacitive strip: tap, long press, swipe L/R |
| Buttons | Back, camera, PTT, jog wheel (CW/CCW) |
| Transport | BT 3.0 SPP (RFCOMM ch4) + WiFi 802.11b/g/n 2.4GHz |
| Battery | Reports level via 0x3e sensor frames |

## License

Research/educational use. Sony SmartEyeglass SDK components under Sony's original license.
