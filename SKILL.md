# SED-E1 Agent Skill Reference

> Zero-context entry point. Dense tables + code. Current as of 2026-06-08.

## 1. Quick Start

```bash
cd /Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1/seg-swift/SEGExplorer
swift run SEGExplorer --bt              # real glasses
swift run SEGExplorer --local HOST:PORT # emulator
cd ../SEGKit && swift test              # 17 unit tests
```

## 2. Architecture

| Package | Role |
|---------|------|
| **SEGKit** | SDK: wire protocol, BT/WiFi/TCP transport, DEFLATE, sensors, camera, display |
| **SEGExplorer** | Extension app: 9 demos using SEGKit public API |

Key files: `GlassesConnection.swift` (public API), `ProtocolActor.swift` (handshake FSM), `TransportActor.swift` (transport layer), `DisplaySubsystem.swift` (rendering), `SensorSubsystem.swift` (IMU+light+battery), `CameraSubsystem.swift` (JPEG), `InputSubsystem.swift` (touch/buttons), `WifiSubsystem.swift` (BT→WiFi upgrade).

## 3. Protocol

Frame: `[cmdId:1B][len:2B BE][payload]`. Everything big-endian.

### Handshake (RFCOMM ch4)
```
← 0x0a ProtocolVersion → 0x71 SettingsReq ← 0x72 SettingsRes
→ 0x07 VersionReq ← 0x08 VersionRes → 0x85 NewHostApp
← 0x81 FotaStatus → 0xff SyncResponse (CRITICAL) ← 0x31 OpenApp
→ 0xe0 LayoutInit
```

### Display
`0xe7` with sub-cmds: PLACE_STATE(0x01) + PLACE_IMGOBJ(0x03, w=419 h=138) + PLACE_IMGDATA(0x07, DEFLATE wbits=-15). Image: 57,822 bytes, 1 byte/pixel grayscale.

### Sensors
| Sensor | ID | Cmd | ACK required |
|--------|----|-----|:---:|
| Accel | 0x01 | 0x3a | ✅ |
| Gyro | 0x0d | 0xbc | ✅ |
| Mag | 0x0e | 0xbd | ✅ |
| Light | 0x10 | 0x3b | ✅ |
| Battery | 0x03 | 0x3e | ✅ |
ACK = `[0x01, 0x00, 0x00]` after every frame.

### WiFi
`0x92` TurnOn → `0x91` Enabled → `0x94` ConnectReq(184B) → `0x95` Connected → TCP_ACCEPT → `0x96` SwitchPath → `0x97` Switched. PSK: PBKDF2-HMAC-SHA1. macOS = TCP server.

### Input (0xe5)
Tap=0x12, LongTap=0x13, SwipeL=0x14, SwipeR=0x15, Back=0x08, Camera=0x09, PTT=0x0b, JogCW=0x04, JogCCW=0x05.

## 4. BT Devices
**6b** (primary), 8f, 8e. RFCOMM channels [7,1,7,4] — use ch4 (SPP). Always ask operator which device.

## 5. Logs
Live: `/tmp/seg-events.jsonl`. Archive: `~/.seg-logs/seg-events-<ISO8601>.jsonl`.

## 6. Repository
```
seg-swift/SEGKit/          active SDK
seg-swift/SEGExplorer/     active demo app
glasses-sdk/               protocol docs
macos-middleware/           legacy CLI + WiFi creds (.env)
harness/                   legacy TypeScript TUI
scripts/                   emulator setup
_dev/                      gitignored: Java explorer, research, analytics
Sony/                      gitignored: Sony SDK
ARCHITECTURE_MODERN.md     full Sony stack archaeology (79KB)
```

## 7. Known Issues
- Camera video over BT = 1 frame (needs WiFi)
- Glasses hang after bad session (power cycle)
- WiFi upgrade untested on hardware
- AR registration protocol incomplete
