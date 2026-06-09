# SEGExplorer UAT Guide

## Quick Start

```bash
# 1. Build
cd seg-swift/SEGExplorer && swift build

# 2. Launch UAT tmux session (BT + debug logging)
./scripts/uat-tmux.sh --bt --debug

# 3. Or connect to specific device
./scripts/uat-tmux.sh --bt --address ac:9b:0a:37:a6:6b --debug

# 4. Or TCP (emulator / ADB forward)
./scripts/uat-tmux.sh --local localhost:7100
```

## tmux Layout

```
┌─────────────────────┬──────────────────┐
│ [0] SEGExplorer     │ [1] Log tail     │
│     REPL            │ ~/.seg-logs/     │
│                     ├──────────────────┤
│                     │ [2] Command help │
└─────────────────────┴──────────────────┘
```

## AI-Driven UAT

Use `scripts/uat-send.sh` to drive the explorer from another terminal or AI agent:

```bash
# Switch to TextDemo
./scripts/uat-send.sh --demo 0
sleep 2

# Capture what's on screen
./scripts/uat-send.sh --capture

# Simulate tap
./scripts/uat-send.sh --tap

# Check debug logs
./scripts/uat-send.sh --logs 10

# Send raw wire bytes
./scripts/uat-send.sh --raw "c3 00 01 01"

# Toggle debug wire logging
./scripts/uat-send.sh --debug

# Back to menu
./scripts/uat-send.sh --menu

# Session status
./scripts/uat-send.sh --status
```

## REPL Commands

| Cmd | Action |
|-----|--------|
| `0`–`8` | Switch demo (Text, Animation, Graphics, Touch, Sensor, CameraCapture, CameraStream, AR, Audio) |
| `t` | Simulate tap |
| `m` | Back to menu |
| `d` | Cycle log level: silent → normal → verbose → debug |
| `ar` | Enter AR mode (sends 0xc3) |
| `normal` | Return to normal display mode |
| `raw XX XX` | Send raw hex bytes to glasses |
| `q` | Disconnect and quit |

## Demo Checklist

| # | Demo | What to verify | Pass criteria |
|---|------|---------------|---------------|
| 0 | Text | Text renders on display | Operator sees "Hello SmartEyeglass" |
| 1 | Animation | Glider GoL runs | Pixels animate at ~2fps |
| 2 | Graphics | 3D cube wireframe | Rotating cube visible |
| 3 | Touch | Touch coordinates display | Tap/swipe events show on display |
| 4 | Sensor | IMU data on display | Numbers change when glasses move |
| 5 | CameraCapture | JPEG saved | `/tmp/seg-capture-*.jpg` created, valid JPEG |
| 6 | CameraStream | Frame stream | Multiple frames captured to `/tmp/` |
| 7 | AR | AR mode switch | Display enters AR rendering mode |
| 8 | Audio | ffmpeg recording | Audio recorded via microphone |

## Hardware Notes

- **Display sleeps ~10s idle** — tap touchpad to wake
- **Power cycle** between sessions if RFCOMM hangs (`kIOReturnNotAttached`)
- **Device suffixes**: 6b (primary), 8f, 8e — always confirm which one is powered on
- **WiFi creds**: `.env` file at project root (SSID=HOIV)
- **Logs**: `~/.seg-logs/seg-events-<ISO>.jsonl` (persistent), `/tmp/seg-events.jsonl` (live tail)
