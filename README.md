# Sony SED-E1 SmartEyeglass — Swift SDK

SEGKit (SDK) + SEGExplorer (demo app) for Sony SmartEyeglass SED-E1.
Reverse-engineered wire protocol, Bluetooth RFCOMM + WiFi transports, 9 demo apps with 1:1 Sony parity.

## Quick Start

```bash
# Build the SDK and explorer app
cd seg-swift/SEGKit && swift build
cd seg-swift/SEGExplorer && swift build

# Connect via Bluetooth (interactive device picker)
swift run SEGExplorer --bt

# Connect via TCP (emulator / ADB forward)
swift run SEGExplorer --local localhost:7100
```

## Architecture

```
seg-swift/
├── SEGKit/          # SDK — wire protocol, transports, subsystems
│   └── Sources/SEGKit/
│       ├── GlassesConnection.swift   # Public API entry point
│       ├── ProtocolActor.swift       # Handshake FSM + frame routing
│       ├── TransportActor.swift      # BT RFCOMM / WiFi TCP / local TCP
│       ├── BluetoothBridge.swift     # IOBluetooth ↔ actor bridge
│       ├── DisplaySubsystem.swift    # DEFLATE-compressed bitmap rendering
│       ├── CameraSubsystem.swift     # JPEG capture + streaming
│       ├── SensorSubsystem.swift     # IMU, light, battery sensors
│       ├── InputSubsystem.swift      # Tap, swipe, jog wheel, buttons
│       ├── WifiSubsystem.swift       # BT→WiFi upgrade path
│       ├── CommandConstants.swift    # All 80+ wire command IDs
│       ├── EventLogger.swift         # Persistent JSONL event logging
│       └── PublicTypes.swift         # Shared types + enums
└── SEGExplorer/     # Demo app — 9 demos exercising all SDK features
    └── Sources/SEGExplorer/
        ├── main.swift                # CLI entry + REPL
        ├── ExplorerApp.swift         # Demo lifecycle manager
        └── Demos/                    # Text, Animation, Graphics, Touch,
                                      # Sensor, CameraCapture, CameraStream,
                                      # AR, Audio
```

## REPL Commands

| Command | Action |
|---------|--------|
| `1`–`9` | Switch demo |
| `d` | Toggle debug wire logging |
| `ar` | Enter AR mode |
| `normal` | Return to normal display mode |
| `raw XX XX` | Send raw hex bytes |
| `q` | Quit |

## Reference

- **[ARCHITECTURE_MODERN.md](ARCHITECTURE_MODERN.md)** — Full protocol reverse-engineering (1923 lines)
- **[_dev/JAVA_SDK_SUMMARY.md](_dev/JAVA_SDK_SUMMARY.md)** — Java SDK API reference
- **[seg-swift/UAT_GUIDE.md](seg-swift/UAT_GUIDE.md)** — Hardware testing guide

## Hardware

- **Display**: 419×138 monochrome, DEFLATE-compressed bitmaps
- **Transport**: BT RFCOMM channel 4 (SPP), WiFi TCP upgrade
- **Sensors**: Accelerometer, gyroscope, magnetometer, light, battery
- **Camera**: 1.3MP JPEG capture, QVGA streaming
- **Input**: Touchpad (tap/swipe), jog wheel (CW/CCW), back/camera/PTT buttons

## License

Research/educational use. Sony SmartEyeglass SDK components under Sony's original license.
