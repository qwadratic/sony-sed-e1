# SED-E1 Glasses Harness — Agent Handoff

> **For fresh agents with zero context.** Read this, produce the deliverables, write `HANDOFF_NEXT.md` with results + blockers for the next team.

---

## Project in one sentence

Drive Sony SmartEyeglass SED-E1 (419×138 green monochrome AR glasses) from macOS via Bluetooth and WiFi — no Android required. BT is working at 2.5fps. WiFi is implemented but needs end-to-end testing and better developer tooling.

---

## Repository

```
/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1/
├── macos-middleware/
│   ├── glasses-tool.swift       ← compiled Swift CLI (THE protocol driver)
│   ├── glasses-tool             ← compiled binary (rebuild: see below)
│   ├── glasses.conf             ← bt_address=auto, rfcomm_channel=4
│   └── glasses-wifi-setup.sh   ← macOS Internet Sharing helper (needs sudo)
├── glasses-sdk/
│   └── PROTOCOL_MAP.md         ← full wire protocol reference
├── README.md
└── HANDOFF.md                  ← this file
```

**Rebuild binary:**
```bash
cd macos-middleware
swiftc glasses-tool.swift -framework IOBluetooth -framework Foundation -o glasses-tool -O
```

---

## What works (confirmed on hardware)

| Feature | Status |
|---|---|
| BT RFCOMM connect + handshake | ✅ confirmed |
| Display rendering (glider demo) | ✅ confirmed at ~2.5fps |
| `wifi on` → 0x91 ENABLED | ✅ confirmed |
| WiFi connect + TCP accept + switch | ❌ not yet end-to-end tested (IP bug just fixed) |
| Multi-glasses scan (picks any paired SmartEyeglass) | ✅ |

---

## Your tasks (this iteration)

### Task 1 — JSON event logging in glasses-tool.swift

Add structured event emission to the Swift binary. Every TX/RX/state change writes a JSON line to `/tmp/glasses-events.jsonl`.

**Exact event schema (TUI and tests depend on this):**
```ts
// All events share: ts (Unix ms float), type
{ ts: 1234.5, type: "TX",       cmd: "0xe7", name: "LayoutPlaceRemoveCommand", bytes: 5923, phase: 5, wifi_active: false, ok: true }
{ ts: 1234.6, type: "RX",       cmd: "0x91", name: "WifiStatusRes",            payload: "03", phase: 5 }
{ ts: 1234.7, type: "STATE",    phase: 5, wifi_phase: 11, wifi_active: false, tcp_connected: false, bt_connected: true }
{ ts: 1234.8, type: "LOG",      level: "INFO"|"WARN"|"ERROR", msg: "WiFi ENABLED" }
{ ts: 1234.9, type: "WIFI",     event: "ENABLED"|"CONNECTED"|"SWITCHED"|"DROPPED", state: 3 }
{ ts: 1235.0, type: "COMPRESS", raw: 57822, compressed: 137, ratio: 0.002, ms: 1 }
```

**Implementation notes:**
- Class `JSONEventLog` with thread-safe `write(_ fields: [String:Any])` (DispatchQueue serialize)
- Global `var gJSONLog: JSONEventLog?` initialized at cmdConnect() start
- Helper `func emitEvent(_ type: String, _ extra: [String:Any] = [:])` adds ts automatically
- Emit TX in `sendCmd()`, RX in `onData`, STATE on `initPhase`/`wifiPhase` changes, WIFI on WiFi state changes, COMPRESS in `deflateCompress()`
- LOG: intercept all `log()` calls → also emit JSON (level from color: CLR_RED→ERROR, CLR_YLW→WARN, rest→INFO)
- Keep existing ANSI output unchanged — JSON is additive

**cmd name map for RX:**
```
0x01=ACK 0x02=NAK 0x05=PING 0x06=LevelNotification 0x08=VersionResponse
0x0a=ProtocolVersion 0x72=SettingsStatusResponse 0x81=FotaStatus
0x91=WifiStatusRes 0x95=WifiConnectivityStatus 0x96=WifiDPSwitchPathReq
0x97=WifiDPSwitchPathRes 0xe5=LayoutEventNotify 0xe8=ImageAck 0xff=SyncResponse
```

Build must pass: `swiftc glasses-tool.swift -framework IOBluetooth -framework Foundation -o glasses-tool -O`

---

### Task 2 — TypeScript TUI harness using `@earendil-works/pi-tui`

**Library:** `@earendil-works/pi-tui` v0.74.2 — Mario Zechner's TUI for Pi coding agent.
Path: `/Users/gerhardgustav/.pi/agent/npm/node_modules/@earendil-works/pi-tui`

**Key API (from dist/index.d.ts and dist/tui.d.ts):**
```ts
import { TUI, Component, Container, Box, Text, Spacer, Input, SelectList } from "@earendil-works/pi-tui";
import { ProcessTerminal } from "@earendil-works/pi-tui";

// Component interface — implement render(width): string[]
interface Component {
  render(width: number): string[];
  invalidate(): void;
  handleInput?(data: string): void;
}

// Text: paddingX, paddingY, optional bgFn
new Text("some text", 1, 0)          // paddingX=1, paddingY=0
new Text(content)                    // no padding

// Box: container with padding + optional background
const box = new Box(1, 0, (t) => chalk.bgBlue(t));
box.addChild(new Text("child"));

// Spacer: vertical gap
new Spacer(1)  // 1 blank line

// Input: text input field, call .getValue() / .setValue()
const input = new Input({ placeholder: "> ", onSubmit: (val) => ... });

// TUI: the main class, renders to terminal
const terminal = new ProcessTerminal(process.stdout, process.stdin);
const tui = new TUI(terminal);
tui.setRoot(myRootComponent);  // set root, triggers re-render
tui.render();                   // force render
```

**Theme pattern (from render.ts in pi-subagents):**
```ts
import type { Theme } from "@earendil-works/pi-coding-agent";
// theme.fg("accent"|"dim"|"error"|"success"|"warning"|"muted"|"border"|"toolTitle", text)
// theme.bold(text)
```

If `@earendil-works/pi-coding-agent` isn't available standalone, use chalk directly:
```ts
import chalk from "chalk";
const theme = {
  fg: (style: string, text: string) => {
    const map: Record<string, (s: string) => string> = {
      accent: chalk.cyan, dim: chalk.dim, error: chalk.red,
      success: chalk.green, warning: chalk.yellow, muted: chalk.gray,
      border: chalk.dim, toolTitle: chalk.bold,
    };
    return (map[style] ?? chalk.reset)(text);
  },
  bold: chalk.bold,
};
```

**harness/ directory structure:**
```
harness/
  package.json
  tsconfig.json
  src/
    index.ts          ← entry point, spawns glasses-tool, starts TUI
    components/
      HeaderBar.ts    ← status bar: BT/WiFi/Phase/Guardrail
      EventLog.ts     ← scrollable TX/RX log
      ProtocolState.ts ← right panel: current state
      QuickActions.ts  ← keyboard shortcut bar
      MessageComposer.ts ← bottom input
      GuardrailPanel.ts  ← pending-command confirmation (when guardrail=ON)
    events.ts         ← tail /tmp/glasses-events.jsonl, parse, emit
    state.ts          ← ProtocolStateModel, updated from events
    process.ts        ← spawn glasses-tool, write to stdin
```

**package.json:**
```json
{
  "name": "glasses-harness",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "dev": "node --loader ts-node/esm src/index.ts",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@earendil-works/pi-tui": "file:/Users/gerhardgustav/.pi/agent/npm/node_modules/@earendil-works/pi-tui",
    "chalk": "^5.3.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "@types/node": "^20.0.0",
    "ts-node": "^10.9.0"
  }
}
```

**Layout:**
```
┌─ GLASSES HARNESS ──────────────────────────────────────────────────────────┐
│ BT: ● connected   WiFi: ○ off   Phase: 5   TCP: ✗   Guardrail: [OFF]  [G] │
├──────────────────────────────────┬─────────────────────────────────────────┤
│ EVENT LOG                        │ PROTOCOL STATE                          │
│ 00:01.234 TX 0xe7 Layout 5.8KB ✓│ Phase:      5 (display_ready)          │
│ 00:01.235 RX 0xe8 ImageAck  3B  │ WiFi Phase: 11 (wifi_enabled)          │
│ 00:01.240 TX 0xe7 Layout 5.8KB ✓│ BT:         connected ch4              │
│ [scrolls, newest at bottom]      │ TCP:        not connected              │
│                                  │ Frames:     142 sent                   │
│                                  │ Compression: 0.2% avg                  │
├──────────────────────────────────┴─────────────────────────────────────────┤
│ [w]ifi on  [c]onnect  [s]witch  [g]lider  [x]stop  [G]guardrail  [?]help  │
├─────────────────────────────────────────────────────────────────────────────┤
│ > _                                                                [Enter]  │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Keyboard shortcuts:**
| Key | Sends to stdin | Notes |
|-----|---------------|-------|
| w | `wifi on\n` | |
| c | `wifi connect auto\n` | |
| s | `wifi switch\n` | |
| b | `wifi bt\n` | |
| g | `glider\n` | |
| x | `stop\n` | |
| G | (toggle local guardrail state) | |
| ? | `help\n` | |
| Esc | clear composer | |
| q | `quit\n` then exit | |
| Enter / Space | send composer content | |

**Guardrail:**
- OFF (default): all commands sent immediately
- ON: user command queued in `GuardrailPanel`, shows `⚠ PENDING: <cmd>  [A]llow  [S]kip`
- Press A to allow/send, S to skip
- Header turns yellow when ON

**Event tailing (events.ts):**
```ts
import { createReadStream, watchFile } from "fs";
import readline from "readline";

export function tailEvents(path: string, onEvent: (e: GlassesEvent) => void) {
  let offset = 0;
  // Initial read then watch for new content
  const read = () => {
    const stream = createReadStream(path, { start: offset, encoding: "utf8" });
    const rl = readline.createInterface({ input: stream });
    rl.on("line", (line) => {
      try { const e = JSON.parse(line); offset += Buffer.byteLength(line+"\n"); onEvent(e); }
      catch {}
    });
  };
  try { read(); } catch {}
  watchFile(path, { interval: 100 }, read);
}
```

**Protocol state model (state.ts):**
```ts
export interface ProtocolState {
  phase: number;       // 0-5
  wifiPhase: number;   // 0,10,11,12,13
  wifiActive: boolean;
  tcpConnected: boolean;
  btConnected: boolean;
  framesSent: number;
  avgCompressionRatio: number;
  lastEvent?: GlassesEvent;
}

const PHASE_NAMES: Record<number, string> = {
  0: "init", 1: "proto_ver", 2: "settings", 3: "version",
  4: "new_host_app", 5: "display_ready"
};
const WIFI_PHASE_NAMES: Record<number, string> = {
  0: "off", 10: "turning_on", 11: "wifi_enabled",
  12: "tcp_connecting", 13: "wifi_active"
};
```

**Build and run:**
```bash
cd harness
npm install
npm run build
node dist/index.js             # auto-discovers glasses
node dist/index.js --no-glasses  # TUI only (dev mode, no subprocess)
```

---

### Task 3 — tmux session + pytest tests

**harness.tmux.sh** (repo root):
```bash
#!/bin/bash
# ./harness.tmux.sh          → start interactive session
# ./harness.tmux.sh --test   → start + run pytest immediately

SESSION=glasses
REPO=/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1

tmux kill-session -t $SESSION 2>/dev/null || true
tmux new-session -d -s $SESSION -x 220 -y 50

# Pane 0 (left): harness TUI or glasses-tool
tmux send-keys -t $SESSION:0 "cd $REPO && node harness/dist/index.js" Enter

# Pane 1 (right top): JSON event stream  
tmux split-window -t $SESSION:0 -h
tmux send-keys -t $SESSION:0.1 "tail -F /tmp/glasses-events.jsonl | python3 -c \"import sys,json; [print(json.dumps(json.loads(l), separators=(',',':'))) for l in sys.stdin]\" 2>/dev/null" Enter

# Pane 2 (right bottom): test runner
tmux split-window -t $SESSION:0.1 -v
tmux send-keys -t $SESSION:0.2 "cd $REPO && echo 'Ready. Run: pytest tests/ -v'" Enter

if [[ "$1" == "--test" ]]; then
  sleep 3
  tmux send-keys -t $SESSION:0.2 "pytest tests/ -v" Enter
fi

tmux attach -t $SESSION
```

**tests/ structure:**
```
tests/
  __init__.py
  conftest.py          ← fixtures
  helpers/
    __init__.py
    events.py          ← EventStream class (tail + wait_for)
  test_protocol.py
  test_wifi.py
  test_display.py
```

**tests/helpers/events.py:**
```python
import json, time
from pathlib import Path

class EventStream:
    def __init__(self, path="/tmp/glasses-events.jsonl"):
        self.path = path

    def wait_for(self, type=None, cmd=None, event=None, timeout=10.0):
        """Block until matching event or timeout. Returns dict or None."""
        deadline = time.time() + timeout
        seen_size = Path(self.path).stat().st_size if Path(self.path).exists() else 0
        while time.time() < deadline:
            if Path(self.path).exists():
                with open(self.path) as f:
                    f.seek(seen_size)
                    for line in f:
                        try:
                            e = json.loads(line)
                            if type and e.get("type") != type: continue
                            if cmd  and e.get("cmd") != cmd: continue
                            if event and e.get("event") != event: continue
                            return e
                        except: pass
                    seen_size = f.tell()
            time.sleep(0.1)
        return None

    def clear(self):
        Path(self.path).write_text("")
```

**tests/conftest.py:**
```python
import pytest, subprocess, time
from helpers.events import EventStream

@pytest.fixture(scope="session")
def events():
    es = EventStream()
    es.clear()
    return es

@pytest.fixture
def proc(events):
    """Requires physical glasses powered on."""
    p = subprocess.Popen(
        ["./macos-middleware/glasses-tool", "connect"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        cwd="/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1"
    )
    yield p
    try: p.stdin.write(b"quit\n"); p.stdin.flush()
    except: pass
    p.wait(timeout=5)

def cmd(proc, s):
    proc.stdin.write(f"{s}\n".encode()); proc.stdin.flush()
```

**tests/test_protocol.py:**
```python
def test_reaches_phase5(proc, events):
    ev = events.wait_for(type="STATE", timeout=30)
    assert ev and ev["phase"] == 5

def test_sync_response_after_fota(proc, events):
    fota = events.wait_for(type="RX", cmd="0x81", timeout=20)
    assert fota
    sync = events.wait_for(type="TX", cmd="0xff", timeout=3)
    assert sync, "SyncResponse not sent after FotaStatus"

def test_compression_ratio(proc, events, cmd):
    cmd(proc, "glider")
    c = events.wait_for(type="COMPRESS", timeout=5)
    assert c and c["ratio"] < 0.1, f"Poor compression: {c}"
```

**tests/test_wifi.py:**
```python
def test_wifi_on_enabled(proc, events, cmd):
    cmd(proc, "wifi on")
    ev = events.wait_for(type="WIFI", event="ENABLED", timeout=5)
    assert ev and ev["state"] == 3

def test_wifi_connect_req_size(proc, events, cmd):
    cmd(proc, "wifi connect auto")
    ev = events.wait_for(type="TX", cmd="0x94", timeout=5)
    assert ev and ev["bytes"] == 187  # 3 header + 184 payload

def test_wifi_full_flow(proc, events, cmd):
    cmd(proc, "wifi on")
    assert events.wait_for(type="WIFI", event="ENABLED", timeout=5)
    cmd(proc, "wifi connect auto")
    assert events.wait_for(type="WIFI", event="CONNECTED", timeout=15), "Glasses did not join WiFi"
    cmd(proc, "wifi switch")
    assert events.wait_for(type="WIFI", event="SWITCHED", timeout=5), "WiFi path switch not confirmed"
```

---

### Task 4 — SKILL.md

Create `/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1/SKILL.md` — the agent skill file for this project.

**Target reader:** any coding agent with zero context about the project.
**Format:** dense tables + code blocks, minimal prose. Scannable in 30 seconds.
**Must cover:**
1. Quick start (3 commands to build + run)
2. TUI keyboard reference (all shortcuts, one-line descriptions)
3. REPL command list (every glasses-tool command)
4. Full protocol reference (all command bytes, handshake sequence, WiFi flow, display format)
5. JSON event schema
6. Test framework (pytest fixtures, how to run, how to write a new test)
7. tmux session setup
8. Open problems + how to continue WiFi work
9. Git log summary (where things stand)

---

## Protocol reference (agent-dense)

### Handshake sequence
```
Glasses→Host  0x0a ProtocolVersion       (first frame, len=varies)
Host→Glasses  0x71 SettingsStatusReq     [0x71, 0x00, 0x00]
Glasses→Host  0x72 SettingsStatusRes
Host→Glasses  0x07 VersionReq            [0x07, 0x00, 0x01, 0x01]
Glasses→Host  0x08 VersionRes            (firmware version string)
Host→Glasses  0x85 NewHostApp            [0x85, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]
Glasses→Host  0x81 FotaStatus
Host→Glasses  0xff SyncResponse          [0xff, 0x00, 0x00]  ← CRITICAL, unlocks glasses
Glasses→Host  0x06 LevelNotification     (user taps touch sensor → phase 4→5)
```

### Display (confirmed working)
```
0xe7 LayoutPlaceRemoveCommand
  subcommand 0x01 PLACE_STATE   (10B): stateId=0, jog=0,0,0, options=0
  subcommand 0x03 PLACE_IMGOBJ  (24B): objId=0, layerId=0, x=0, y=0, w=419(0x01a3), h=138(0x008a), sticky=0, subtype=0, loadId=0
  subcommand 0x07 PLACE_IMGDATA (N B): objId=0, imgFormat=1, <raw DEFLATE data>

LayoutInit (0xe0): [0xe0,0x00,0x0a, 0,0,0,0, 0,0,0,0, 0,0]  ← viewX=0 viewY=0 state=0
Image format: 419*138 = 57822 bytes, 1 byte/pixel (0=black 255=white)
Compression: raw DEFLATE, wbits=-15 (Java Deflater nowrap=true)
             Python: zlib.compressobj(9, zlib.DEFLATED, -15)
             Swift:  deflateInit2_(&strm, Z_BEST_COMPRESSION, Z_DEFLATED, -15, ...)
```

### WiFi (implemented, end-to-end untested)
```
0x90 WifiStatusReq       → glasses (len=0)
0x91 WifiStatusRes       ← glasses: payload[0]=state (3=ENABLED)
0x92 WifiTurnOnReq       → glasses (len=0)
0x93 WifiTurnOffReq      → glasses (len=0)
0x94 WifiConnectReq      → glasses (184-byte payload)
0x95 WifiConnectivityStatus ← glasses: payload[0]=state (3=CONNECTED)
0x96 WifiDPSwitchPathReq → glasses: [0x96,0x00,0x01,mode] mode=0x00 BT 0x01 WiFi
0x97 WifiDPSwitchPathRes ← glasses: confirms path switch

WifiConnectReq payload (184B) offsets:
  0x00 32B SSID (UTF-8 null-padded)
  0x20 32B passphrase (UTF-8 null-padded)
  0x60 4B  goAddr  = macOS IPv4 (we are TCP server / Group Owner)
  0x64 4B  staAddr = glasses suggested IPv4 (flip last octet of goAddr)
  0x68 4B  subnetMask (255.255.255.0)
  0x6C 4B  dnsServer (zeros OK)
  0x70 4B  gateway (zeros OK)
  0x74 2B  goChannel = WiFi frequency in MHz (2437 for ch6) — NOT channel number
  0x76 2B  acceptPortNum = our TCP server port (big-endian)
  0x78 64B PSK = PBKDF2-HMAC-SHA1(passphrase, ssid, 4096, 32) as 64-char hex string

TCP model: macOS=SERVER (accept), glasses=CLIENT (connect back)
WiFi state machine: 0x92→0x91(state=3)→0x94→0x95(state=3)→TCP_ACCEPT→0x96(mode=1)→0x97
```

### REPL commands (glasses-tool stdin)
```
glider                     start glider animation
stop                       stop + black frame
white/black/checker/stripes/cross  test patterns
wifi on/off/status         WiFi radio control
wifi connect <s> <p> <ip>  WifiConnectReq with explicit creds
wifi connect auto          uses .env SSID/PSWD + ipconfig getifaddr en0
wifi switch                WifiDPSwitchPathReq mode=1
wifi bt                    WifiDPSwitchPathReq mode=0
wifi setup                 print instructions
raw HEX                    send raw bytes, e.g. "raw e9 00 01 01"
help / quit
```

---

## WiFi current status + how to continue

1. **Last hardware test**: `wifi on` → confirmed 0x91 ENABLED ✅
2. **`wifi connect auto`**: had IP=auto bug (fixed in commit 3b95fbe). Not re-tested since fix.
3. **Next step**: power on glasses, run `./glasses-tool`, then:
   ```
   wifi on           ← should see 0x91 ENABLED
   wifi connect auto ← should see 0x95 CONNECTED then "TCP connected"
   wifi switch       ← should see 0x97 path=WIFI, 30fps starts
   ```
4. If 0x95 never arrives: glasses may not be able to join existing WiFi. Try with a dedicated hotspot.
5. If 0x95 arrives but no TCP connect: check firewall (`sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`).

---

## Success criteria for this iteration

- [ ] `glasses-tool.swift` compiles clean with JSON event logging
- [ ] `/tmp/glasses-events.jsonl` gets populated when glasses connect
- [ ] `harness/` builds with `npm run build`
- [ ] `node harness/dist/index.js --no-glasses` shows TUI with all panes
- [ ] `harness.tmux.sh` starts 3-pane session
- [ ] `pytest tests/test_protocol.py` passes (with glasses connected)
- [ ] SKILL.md exists and is dense/complete

---

## Feedback loop — write HANDOFF_NEXT.md when done

Template:
```markdown
# HANDOFF_NEXT.md

## Completed
- [x] Task 1: JSON logging — works, emit X events/sec
- [x] Task 2: TUI — builds, components render correctly
...

## Failed / Blocked
- Task X failed because Y. Error: ...
- WiFi end-to-end: not tested / partially works / fully works

## Test results
pytest output here

## What next team should tackle
1. ...

## Known issues
- ...
```

---

## Git log
```
3b95fbe fix: getInterfaceIP uses ipconfig subprocess, guard auto IP
b2b227e feat: multi-glasses, native DEFLATE, 30fps WiFi, stop/setup
e0dafbf refactor: glider on demand only
415d9ae feat: glider demo
a3fb5da feat: WiFi data path (TCP server, WifiConnectReq, state machine)
d3a36e8 feat: Game of Life rendering from macOS via BT SPP (first working display)
```
