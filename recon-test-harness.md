# Code Context — Tests + Harness Recon

## Files Retrieved
1. `tests/conftest.py` (full, 75 lines) — Fixtures: `events` (session), `proc` (module-scoped subprocess), `cmd()` helper, autouse `clear_events_before_test`
2. `tests/test_protocol.py` (full, 61 lines) — 6 BT handshake tests
3. `tests/test_wifi.py` (full, 96 lines) — 6 WiFi tests (on/connect/switch/fallback)
4. `tests/test_display.py` (full, 73 lines) — 6 display/rendering tests
5. `tests/helpers/events.py` (full, 64 lines) — `EventStream` class: tails `/tmp/glasses-events.jsonl`
6. `harness/src/index.ts` (full, 174 lines) — TUI entry point, key bindings, event tailing
7. `harness/src/events.ts` (full, 79 lines) — Event types & `EventTailer` class
8. `harness/src/state.ts` (full, 80 lines) — `ProtocolState` interface, `applyEvent` reducer
9. `harness/src/process.ts` (full, 65 lines) — `GlassesProcess`: spawns `glasses-tool connect`
10. `pytest.ini` (4 lines) — `testpaths = tests`, `pythonpath = tests`, `-x --tb=short`

## Key Code

### Event Bridge (shared between tests & harness)
Both Python tests and the TS harness consume the same event file:
```
/tmp/glasses-events.jsonl
```
- **Python side** (`tests/helpers/events.py`): `EventStream.wait_for(type, cmd, event, timeout)` — polls file with seek-forward, returns matching JSON dict or `None`.
- **TS side** (`harness/src/events.ts`): `EventTailer` uses `watchFile` + `createReadStream(start: offset)` to emit parsed events.

### Event Types (harness/src/events.ts)
```typescript
type GlassesEventType = "TX" | "RX" | "STATE" | "LOG" | "WIFI" | "COMPRESS"
// NO "CAMERA" type defined
```

### ProtocolState (harness/src/state.ts)
```typescript
interface ProtocolState {
  phase: number;          // 0-5 (init → display_ready)
  wifiPhase: number;      // 0,10,11,12,13
  wifiActive: boolean;
  tcpConnected: boolean;
  btConnected: boolean;
  framesSent: number;
  compressSamples: number[];
  avgCompressionRatio: number;
  lastEvent?: GlassesEvent;
}
```
`applyEvent()` handles STATE, TX, WIFI, COMPRESS — **does NOT handle CAMERA events**.

### Test Inventory (18 tests total)
| Module | Tests | Requires |
|---|---|---|
| `test_protocol.py` | 6 | BT connection, physical glasses |
| `test_wifi.py` | 6 | BT + WiFi same-network + `.env` creds |
| `test_display.py` | 6 | BT + phase 5 reached |

### conftest.py — `proc` fixture
- Spawns `glasses-tool connect` as subprocess
- Pipes `1\n` to stdin for auto-device-selection (unless `GLASSES_ADDR` env set)
- Module-scoped → one BT connection per test file
- `cmd(proc, s)` writes to stdin pipe

### Harness TUI (harness/src/index.ts)
- `--no-glasses` flag exists for dev mode (TUI only, no subprocess)
- Key bindings: `w`=wifi on, `c`=wifi connect auto, `s`=wifi switch, `b`=wifi bt, `g`=glider, `x`=stop, `G`=guardrail toggle, `q`=quit
- No camera-related key bindings or commands

## `--local` Flag Status

**Designed but NOT implemented.** References exist only in:
- `CHANGELOG.md` (lines 28-30): design notes
- `PLAN_ARCHITECTURE.md` (lines 206-314): detailed design spec
- `scripts/adb-forward.sh` (line 9): usage example comment
- `scripts/setup-emulator.sh` (lines 105-108): usage example comments
- `.git/COMMIT_EDITMSG`: commit message mentioning design

**Not implemented in:**
- ❌ `tests/conftest.py` — no `pytest_addoption`, no `--local` arg parsing
- ❌ `macos-middleware/glasses-tool.swift` — no `--local` argument handling
- ❌ `harness/src/process.ts` — always spawns `glasses-tool connect`

**Bottom line:** `--local` is a planned feature for TCP-based transport (for Android emulator / adb-forwarded connections) that enables hardware-independent CI. The architecture doc (`PLAN_ARCHITECTURE.md:278-285`) shows the exact conftest changes needed.

## Camera Events — NOT Handled in Harness

**Swift middleware (`glasses-tool.swift`):** Camera is fully implemented:
- `emitEvent("CAMERA", ...)` emitted for `CAPTURE_RESPONSE`, `CAPTURE_ERROR`, `CHUNK`, `SAVED`
- Commands: `camera start`, `camera stop`, `camera burst`
- JPEG accumulation from `0xb5`/`0xb6` WiFi frames

**Harness gap:** The harness has **zero camera awareness**:
- `harness/src/events.ts` — `GlassesEventType` does not include `"CAMERA"`
- `harness/src/state.ts` — `applyEvent()` has no CAMERA case
- `harness/src/index.ts` — no camera key binding, no camera UI
- No `CameraEvent` interface defined

**Test gap:** No camera tests exist anywhere in `tests/`.

## Architecture

```
glasses-tool (Swift subprocess)
    │
    ├──writes──→  /tmp/glasses-events.jsonl   (JSONL: TX/RX/STATE/WIFI/COMPRESS/CAMERA)
    │
    ├──stdin ←── conftest.py proc fixture    (pytest: cmd("glider"), cmd("wifi on"), etc.)
    │              └── EventStream reads JSONL, wait_for() pattern-matches
    │
    └──stdin ←── harness GlassesProcess      (TUI: key bindings → sendCmd())
                   └── EventTailer reads JSONL → applyEvent() → ProtocolState → render
```

Key coupling: both test suite and harness depend on the same JSONL schema emitted by `glasses-tool`. Adding new event types (like CAMERA) requires updating both consumers.

## Gaps & Risks

1. **`--local` not implemented** — tests require physical hardware. PLAN_ARCHITECTURE.md has the design but no code exists.
2. **CAMERA events ignored by harness** — `glasses-tool` emits them but harness drops them silently (JSON parse succeeds but `applyEvent` has no case).
3. **No camera tests** — despite full camera protocol in Swift.
4. **Module-scoped `proc`** — all tests in a file share one BT connection; a test that breaks the connection kills the rest.
5. **Hardcoded path** — `REPO` in conftest.py is absolute: `/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1`.
6. **No CI story** — all 18 tests need live glasses hardware.

## Start Here

**`tests/conftest.py`** — this is the fixture hub. Any change to test infrastructure (adding `--local`, adding camera tests, changing process management) flows through here. The `proc` fixture and `EventStream` are the two integration points between Python tests and the Swift subprocess.

For harness camera support, start at **`harness/src/events.ts`** (add `CameraEvent` type) then **`harness/src/state.ts`** (add camera state + `applyEvent` case).
