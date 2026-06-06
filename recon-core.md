# Code Context — sony-sed-e1 Recon

## Files Retrieved
1. `_dev/HANDOFF.md` (full) — original agent task spec: JSON logging, TUI harness, pytest, SKILL.md
2. `_dev/HANDOFF_NEXT.md` (full) — completion report: claims all 4 tasks done
3. `_dev/NEXT_STEPS.md` (full) — **STALE**: discusses display not working (0x35 command); fixed long ago
4. `PLAN_ARCHITECTURE.md` (full) — thread arch refactor + Android emulator E2E strategy; **doc-only, zero implemented**
5. `macos-middleware/glasses-tool.swift` (1995 lines) — THE protocol driver; single monolithic file
6. `harness/src/` — TypeScript TUI (index.ts, events.ts, state.ts, process.ts, 6 components)
7. `tests/` — pytest suite (conftest.py, test_protocol.py, test_wifi.py, test_display.py)
8. `scripts/` — setup-emulator.sh, adb-forward.sh, teardown-emulator.sh

---

## What's REAL Code (Working)

### glasses-tool.swift — 1995 lines, single file, fully functional
- **BT RFCOMM connect + handshake** (phases 0→5): lines 301-360, confirmed on hardware
- **Display rendering** (LayoutPlaceRemoveCommand 0xe7 + DEFLATE): lines 998-1060, confirmed at ~2.5fps BT
- **WiFi state machine** (on/connect/switch): lines 1145-1230, `wifi on` confirmed, full flow untested
- **Camera capture protocol** (0xce/0xb4/0xb5/0xb6/0xb7): lines 1230-1315 (REPL), 477-540 (WiFi handler), 1560-1620 (BT handler)
- **JSON event logging** (JSONEventLog class): lines 143-178, writes to `/tmp/glasses-events.jsonl`
- **RFCOMM frame reassembly**: rxBuf buffering with [cmdId:1B][len:2B][payload] parsing
- **WiFi TCP server**: lines 429-540, OS-assigned port, accept loop, separate wifiRxBuf reassembly
- **PSK derivation**: PBKDF2 via python3 subprocess, line 607
- **REPL**: 30+ commands (glider/stop/wifi/camera/raw/white/black/checker/etc.), lines 1084-1316
- **Config loading**: glasses.conf + .env, lines 1737-1800
- **Auto-discovery**: scan paired BT devices, pick SmartEyeglass, lines 1819+

### harness/ — TypeScript TUI, builds and renders
- All 6 components exist: HeaderBar, EventLog, ProtocolState, QuickActions, MessageComposer, GuardrailPanel
- Event tailing from `/tmp/glasses-events.jsonl` with file watch
- State machine mirrors Swift's phases
- Guardrail mode functional (queue + confirm before send)
- `--no-glasses` dev mode works

### tests/ — pytest suite, well-structured
- `conftest.py`: spawns glasses-tool, auto-selects device, EventStream fixture
- `test_protocol.py`: 6 tests (phase5, sync after fota, protocol version first, settings req, compression, bt state)
- `test_wifi.py`: 6 tests (wifi on, rx91, connect req size, state transitions, full flow, bt fallback)
- `test_display.py`: 6 tests (glider frames, frame size, stop black, layout init, compress ratio, multi-frame)
- **All require physical hardware** — no mock/emulator path exists

---

## What's DOC-ONLY / Stubbed (NOT Implemented)

### PLAN_ARCHITECTURE.md Track 1 — Thread Architecture
**100% doc-only.** None of these exist in code:
- `ProtocolSM` actor — NOT in glasses-tool.swift (grep confirms zero matches)
- `TransportManager` — NOT implemented
- `ChannelRouter` (Control/Media/Display/Heartbeat) — NOT implemented
- `MediaChannel` — NOT implemented
- `Supervisor` watchdog — NOT implemented
- Control socket (`unix:///tmp/glasses-control.sock`) — NOT implemented
- `macos-middleware/Sources/` directory — **does not exist**; everything is one 1995-line file

### PLAN_ARCHITECTURE.md Track 2 — Android Emulator E2E
**Scripts exist, transport does NOT:**
- `scripts/setup-emulator.sh` — exists, well-written, BUT:
- `--local HOST:PORT` flag in glasses-tool — **NOT IMPLEMENTED** (grep confirms zero matches)
- `--local` flag in pytest conftest — **NOT IMPLEMENTED**
- `Transport` enum (`bt/wifi/local`) — NOT in code
- CI/CD GitHub Actions workflow — NOT created
- `test_camera_emulator.py` — does NOT exist

### PLAN_ARCHITECTURE.md Work Order status:
| Item | Status |
|------|--------|
| A1: ProtocolSM actor | ❌ doc only |
| A2: TransportManager | ❌ doc only |
| A3: ChannelRouter | ❌ doc only |
| A4: MediaChannel | ❌ doc only |
| A5: Supervisor watchdog | ❌ doc only |
| A6: Control socket | ❌ doc only |
| B1: --local flag | ❌ scripts exist, transport not implemented |
| B2-B4: ADB scripts | ⚠️ scripts exist, nothing to connect to |
| C1-C4: Emulator tests | ❌ not started |
| D1-D3: Harness control socket | ❌ doc only |

---

## Document Contradictions

### 1. NEXT_STEPS.md is completely stale
- Says display "stays empty" and 0x35 command is wrong → **Fixed months ago**. Code now uses 0xe7 LayoutPlaceRemoveCommand (line 998) and confirmed working at 2.5fps.
- Suggests trying `MckinleyRawScreenImage` → irrelevant; the real command was found and works.
- References `/tmp/seg_decompiled/smali/` files → local dev artifacts, not in repo.

### 2. PLAN_ARCHITECTURE.md vs actual code
- Describes `macos-middleware/Sources/*.swift` split → **directory doesn't exist**, everything is `glasses-tool.swift`
- References `--local HOST:PORT` flag → **not implemented in Swift**
- References `--local` in pytest conftest → **not implemented**
- Work order implies Step 1-3 partially done ("(done)" annotations on steps 1-3) → **false**: the annotations mean WiFi frame handling exists, but the actual ProtocolSM/TransportManager/ChannelRouter refactoring is NOT done
- Claims "BT + WiFi rxBuf collision" is a problem → **actually already mitigated**: wifiRxBuf is separate (line 581), and camera handlers check `wifiActive` flag to avoid duplication

### 3. HANDOFF.md vs HANDOFF_NEXT.md
- HANDOFF.md status table: "WiFi connect + TCP accept + switch: ❌ not yet end-to-end tested" 
- HANDOFF_NEXT.md: also says WiFi not tested
- But code has full WiFi implementation including auto-upgrade (line 834), TCP accept (line 540), and WiFi data path with separate rx loop (line 570+)
- **The code is ahead of what docs claim**

### 4. HANDOFF.md JSON schema vs actual implementation
- HANDOFF.md specifies `CAMERA` event type is NOT in the schema — but code emits `CAMERA` events extensively (lines 497, 503, 511, 523, etc.)
- HANDOFF.md shows RX event schema with `name` field — actual code emits RX without `name` in many places (WiFi handler at line 489 omits it)

### 5. SKILL.md vs PLAN_ARCHITECTURE.md
- SKILL.md is a reference for the *current* state (single-file Swift CLI)
- PLAN_ARCHITECTURE.md describes a *future* multi-file actor-based architecture
- Both exist at root level with no indication of which is canonical

---

## Key Code

### Core architecture (actual)
```
glasses-tool.swift (single file, 1995 lines)
├── Globals: gChannel, gDelegate, gJSONLog, gCapture
├── cmdConnect() — one giant function (lines 301-1680)
│   ├── Local vars: initPhase, wifiPhase, wifiActive, wifiServerFd, wifiClientFd
│   ├── Nested funcs: emitState, sendCmd, sendViaTCP, wifiCreateServer, handleWifiFrame,
│   │   wifiStartAccept, derivePSK, buildWifiConnectReq, detectWifiChannel,
│   │   wifiStartConnect, golInit, golStep, golToImage, buildLayoutDisplayCmd,
│   │   deflateCompress, handleREPLCommand, golSendFrame, golStartGliderDemo
│   └── RX dispatch: gDelegate.onData callback with switch on (initPhase, cmdId)
├── cmdScan(), cmdSDP(), cmdProbe(), cmdPairGuide()
├── GlassesConfig struct + load()
├── scanAndSelectGlasses()
└── main: arg parsing → dispatch
```

### Wire protocol (confirmed working)
- Handshake: 0x0a → 0x71 → 0x72 → 0x07 → 0x08 → 0x85 → 0x81 → 0xff → 0x06 → phase 5
- Display: 0xe0 LayoutInit + 0xe7 LayoutPlaceRemoveCommand (PLACE_STATE + PLACE_IMGOBJ + PLACE_IMGDATA)
- Image: 419×138, 1 byte/pixel grayscale, DEFLATE compressed (wbits=-15)
- WiFi: 0x92→0x91(state=3)→0x94(184B payload)→0x95(state=3)→TCP_ACCEPT→0x96(mode=1)→0x97
- Camera: 0xce(mode)→0xb4(req)→0xb5(resp)→0xb6(chunks+ACK)→0xb7(done)

---

## Architecture

**Current reality**: One monolithic Swift file with everything in nested closures inside `cmdConnect()`. State is captured by closures, not owned by actors. BT and WiFi have separate rx paths but share the same main-thread dispatch. The TypeScript harness is a passive observer (reads JSON events, sends stdin commands). Tests require physical hardware.

**Planned future** (PLAN_ARCHITECTURE.md): Actor-based architecture with ProtocolSM, TransportManager, ChannelRouter, Supervisor, control socket, and ADB-based emulator testing. **Zero lines of this exist.**

The gap between plan and reality is the entire PLAN_ARCHITECTURE.md document.

---

## Risks & Open Questions

1. **WiFi end-to-end never tested** — `wifi connect auto` through `wifi switch` has never been confirmed working despite full implementation existing
2. **Camera over BT never tested** — camera protocol was RE'd from DEX and implemented, but HANDOFF_NEXT.md doesn't mention any hardware test
3. **No mock/emulator test path** — all tests require physical glasses; `--local` transport is not implemented despite scripts existing
4. **Single-file tech debt** — 1995-line closure-based design makes refactoring risky; every nested function captures `initPhase`, `wifiPhase`, etc. by reference
5. **NEXT_STEPS.md is dangerous** — any agent reading it will think display doesn't work and attempt to fix something already working

---

## Start Here

**`macos-middleware/glasses-tool.swift`** — this is the entire runtime. Start at line 301 (`cmdConnect`) which is 1380 lines of nested closures containing all protocol logic. Understanding this function = understanding the project.

Then read `PLAN_ARCHITECTURE.md` work order section (bottom) to understand what's been *planned* but not built. The gap between that plan and the current single-file reality is where any refactoring work lives.

**Delete or archive `_dev/NEXT_STEPS.md`** — it's stale and misleading. The display rendering problem it describes was solved months ago.
