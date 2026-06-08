# CLAUDE.md — sony-sed-e1

Sony SED-E1 SmartEyeglass macOS Swift SDK (SEGKit) + demo app (SEGExplorer).

## Layout
- `seg-swift/SEGKit/` — SDK: wire protocol, transports, subsystems
- `seg-swift/SEGExplorer/` — Demo app: 9 demos + REPL
- `Sony/` — Original Sony SDK docs + javadoc (read-only reference)
- `_dev/smarteyeglass-explorer/` — Java reference code (read-only)
- `ARCHITECTURE_MODERN.md` — Full protocol reverse-engineering

## Build
```bash
cd seg-swift/SEGKit && swift build && swift test
cd seg-swift/SEGExplorer && swift build
swift run SEGExplorer --bt          # Bluetooth
swift run SEGExplorer --local :7100 # TCP
```

## Hardware Lifecycle [H1]
NEVER send display commands until: BT connect (ch4) → FOTA 0x81/5s → OpenApp 0x31/3s → LINIT 0x30 → SyncResponse 0xFF. Violation = power cycle. Glasses need power cycling when RFCOMM hangs (kIOReturnNotAttached).

## BT Device Selection [H2]
Paired: 6b (primary, ac-9b-0a-37-a6-6b), 8f, 8e. ALWAYS ask suffix before connecting.

## Editing Swift Files [H4]
>500 lines: prefer Write or bash surgery. Re-read before edit if subagents touched file. On edit failure: re-read, don't retry stale oldText.

## Protocol = smali [H5]
Wire constants from Sony/ and _dev/smarteyeglass-explorer/libs/SmartEyeglassAPI/. Never guess.

## Hardware Claims [H6]
No "X works" without TX/RX hex in log + dynamic data + operator visual confirmation.

## Retry Policy [M1]
2 identical fails → change strategy. 3 any fails → ask operator.

## Subagents [M2]
Types: worker, scout, delegate, oracle. Recon=sonnet, build=opus.

## Key Wire Facts
- Big-endian everywhere (Java ByteBuffer)
- RFCOMM ch4=SPP data, ch1=HFP (wrong)
- Sensor ACK [0x01,0x00,0x00] required per IMU frame
- Display sleeps ~10s idle, 0xe8 ACK between cmds
- WiFi creds in .env (SSID=HOIV)
- Logs: ~/.seg-logs/seg-events-<ISO>.jsonl

## Monitor
Check .monitor/proposal-ready.flag between tasks. If exists: summarize to user, wait. Never auto-act.
