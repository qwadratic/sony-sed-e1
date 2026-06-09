# CLAUDE.md — sony-sed-e1

Sony SED-E1 SmartEyeglass macOS Swift SDK (SEGKit) + demo app (SEGExplorer).

## Layout
- `SEGKit/` — SDK: wire protocol, transports, subsystems
- `SEGExplorer/` — Demo app: 9 demos + REPL + onboarding
- `STATUS.md` — what works, what doesn't, known issues
- `ROADMAP.md` — planned features (AR, WiFi streaming, firmware)

## Build
```bash
cd SEGKit && swift build && swift test
cd SEGExplorer && swift build
swift run SEGExplorer --bt          # Bluetooth
swift run SEGExplorer --bt --debug  # Wire hex logging
```

## Hardware Lifecycle
NEVER send display commands until: BT connect (ch4) → FOTA 0x81/5s → OpenApp 0x31/3s → LINIT 0x30 → SyncResponse 0xFF. Violation = power cycle.

## BT Device Selection
Paired: 6b (primary), 8f, 8e. ALWAYS ask suffix before connecting.

## Protocol = smali
Wire constants verified from DEX bytecode. Never guess protocol values.

## Input Events
Event type at `payload[1]` not `payload[0]` — leading zero byte in 0xe5 frames.

## Retry Policy
2 identical fails → change strategy. 3 any fails → ask operator.

## Key Wire Facts
- Big-endian everywhere
- RFCOMM ch4=SPP data, ch1=HFP (wrong)
- Sensor ACK [0x01,0x00,0x00] required per IMU frame
- Display sleeps ~10s idle, 0xe8 ACK between cmds
- Logs: ~/.seg-logs/seg-events-<ISO>.jsonl

## Monitor
Check .monitor/proposal-ready.flag between tasks.
