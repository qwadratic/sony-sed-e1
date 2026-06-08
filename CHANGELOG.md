# Changelog

## [0.4.0] — 2026-06-08

### Changed — Repository Cleanup
- **Major cleanup**: removed legacy harness, old middleware, stale docs, APKs, Python/Node tooling
- Repo now focused on `seg-swift/` (SEGKit SDK + SEGExplorer demos)
- Kept: `Sony/` (SDK reference), `_dev/smarteyeglass-explorer/` (Java reference)
- Added `_dev/JAVA_SDK_SUMMARY.md` — condensed Java SDK reference (1072 lines)
- Added `_dev/SESSION_ANALYTICS_REPORT.md` — full session analytics
- Rewrote README.md, CLAUDE.md (with analytics-derived rules), .gitignore
- Removed: `harness/`, `macos-middleware/`, `glasses-sdk/`, `scripts/`, `tests/`,
  research notes, APKs, build artifacts, Python/Node tooling remnants

## [0.3.0] — 2026-06-08

### Changed
- **Project cleanup**: README, CLAUDE.md, CHANGELOG, SKILL.md rewritten to reflect SEGKit/SEGExplorer architecture
- Removed stale root-level research notes (moved to `_dev/`)
- Fixed `.gitignore` to exclude `.build/`, `.pytest_cache/`, `.venv/`, `.fallow/`
- Removed accidentally tracked Swift build artifacts from git

## [0.2.0] — 2026-06-07

### Added — SEGKit Swift SDK
- `GlassesConnection` — public API with `connectBluetooth()`, `connectLocal()`, delegate callbacks
- `ProtocolActor` — handshake FSM (FotaStatus/OpenApp timeouts for emulator compat)
- `TransportActor` — BT RFCOMM / WiFi TCP / local TCP, isolated rx buffers per transport
- `BluetoothBridge` — NSObject delegate → Swift actor bridge for IOBluetooth
- `DisplaySubsystem` — 419×138 grayscale → raw DEFLATE → wire frames
- `CameraSubsystem` — JPEG still capture + QVGA streaming with chunk reassembly
- `SensorSubsystem` — accel/gyro/mag/light/battery with required ACK
- `InputSubsystem` — full event types: tap, longPress, swipe, back, camera, PTT, jog CW/CCW
- `WifiSubsystem` — BT→WiFi upgrade with PSK derivation and TCP server
- `EventLogger` — persistent JSONL at `~/.seg-logs/` + live at `/tmp/seg-events.jsonl`
- `CommandConstants` — 80+ named cmd IDs from DEX RE

### Added — SEGExplorer Demo App
- 9 demos: Text, Animation, Graphics, Touch, Sensor, CameraCapture, CameraStream, AR, Audio
- Interactive BT device picker with RSSI, online detection, auto-select
- REPL with debug toggle, AR/normal mode switch, raw hex send
- CLI flags: `--bt`, `--local HOST:PORT`, `--debug`, `--verbose`, `--silent`

### Fixed
- Camera JPEG: big-endian byte order for size + accumulate all chunks (no dedup)
- Sensor IDs from smali: gyro=0x0d, mag=0x0e, light=0x10, battery=0x03
- Sensor ACK `[0x01, 0x00, 0x00]` required after each data frame
- BT connection: removed `openConnection()` (caused `kIOReturnNotAttached`), use `openRFCOMMChannelAsync`
- RFCOMM channel 4 (SPP data), not channel 1 (HFP)
- Crash fix: NSLock serializes DEFLATE compression (concurrent render from burst touch events)
- 200ms input debounce prevents render flooding

### Verified on hardware
- All 8 display demos rendering on Android emulator (screenshots captured)
- BT handshake + display rendering on real glasses (device 6b)
- Battery sensor streaming at ~100ms (battery=45%)
- Camera JPEG capture (7108B from emulator virtual camera)
- 17 unit tests passing

## [0.1.0] — 2026-06-06

### Added — Legacy monolithic CLI
- `macos-middleware/glasses-tool.swift` — single-file Swift protocol driver
- BT RFCOMM connection + full handshake (5-phase state machine)
- Display rendering: 419×138 grayscale, raw DEFLATE, ~2.5fps over BT
- WiFi data path: same-network mode, TCP server, auto-upgrade
- Glider animation demo (Game of Life: Gosper gun + R-pentomino)
- JSON event log at `/tmp/glasses-events.jsonl`
- TypeScript TUI harness (`harness/`) with live event log + protocol state
- pytest test suite for BT handshake, WiFi flow, display rendering
- 3-pane tmux session (`harness.tmux.sh`)
- Android emulator setup scripts (`scripts/setup-emulator.sh`)
- Full wire protocol reverse-engineering (`glasses-sdk/PROTOCOL_MAP.md`)
- Camera protocol RE from DEX bytecode (`glasses-sdk/CAMERA_PROTOCOL.md`)
