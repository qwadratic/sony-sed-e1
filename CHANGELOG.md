# Changelog

## [Unreleased] — 2026-06-06

### Added
- `PLAN_ARCHITECTURE.md` — full thread/channel architecture plan + Android emulator E2E strategy
- `scripts/setup-emulator.sh` — create AVD (API 21/x86), install Sony APKs, forward MONITOR_SOCKET
- `scripts/adb-forward.sh` — fast socket re-forward for already-booted emulator
- `scripts/teardown-emulator.sh` — clean shutdown
- `handleWifiFrame()` — separate WiFi reassembly avoids BT+WiFi rxBuf collision
- `handleWifiFrame` handles 0x97 (WifiDPSwitchPathRes) so wifiActive is set correctly when 0x97 arrives WiFi-only
- Camera sequence: `0xce` SetMode → `0x38 sensorId=0x13` SensorStart → `0xb4` CaptureRequest (all via WiFi)
- `cameraNextExpectedSeq` dedup: drops duplicate 0xb6 chunks from BT mirror path
- JPEG data extraction fixed: payload[0]=frame_num, payload[3+]=JPEG (skip 3-byte overhead)
- Full `j2.commands` CMD byte table (80+ commands) RE'd from DEX bytecode
- `glasses-sdk/CAMERA_PROTOCOL.md` — complete camera protocol with payload formats

### Architecture plan (Track 1)
- `ProtocolSM` actor design (single owner of phase + wifiActive)
- `TransportManager` (BT rx/tx + WiFi rx/tx as separate queues)
- `ChannelRouter` (Control / Media / Display / Heartbeat channels)
- Supervisor watchdog + heartbeat thread design
- Control socket (`unix:///tmp/glasses-control.sock`) for harness

### Emulator plan (Track 2)
- SmartEyeglassEmulator APK identified — speaks full j2 wire protocol via LocalSocket
- ADB socket forward: `tcp:7002 → localabstract:com.sony.smarteyeglass.MONITOR_SOCKET`
- `--local HOST:PORT` transport flag design for glasses-tool
- CI/CD GitHub Actions workflow design
- pytest `--local` flag design for hardware-independent test suite

## [0.1.0] — 2026-06-06

First release.

### Features
- BT RFCOMM connection + full handshake (ProtocolVersion → SettingsStatus → Version → NewHostApp → SyncResponse)
- Display rendering: 419×138 8-bit grayscale, raw DEFLATE (`wbits=-15`), ~0.2% compression ratio
- Glider animation demo (~2.5fps over BT)
- WiFi data path: same-network mode — both devices join an existing AP, no Internet Sharing needed
- Auto-discovery: scans paired SmartEyeglass devices, picks on connect
- JSON event log at `/tmp/glasses-events.jsonl` (TX, RX, STATE, WIFI, COMPRESS, LOG)
- TypeScript TUI harness with live event log, protocol state panel, guardrail mode
- pytest test suite for BT handshake, WiFi flow, and display rendering
- `glasses-wifi-setup.sh` — WiFi readiness checker (en0 IP + `.env` validation)
- 3-pane tmux session (`harness.tmux.sh`)
