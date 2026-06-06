# Architecture & Emulator Plan

> Written 2026-06-06. Captures two tracks of work:
> 1. Proper thread/channel architecture for the macOS protocol runtime
> 2. Android emulator E2E strategy using SmartEyeglassEmulator + ADB

---

## Track 1 — Thread & Channel Architecture

### Problem with current code

Everything lives in one giant `connectAndRun()` closure. All state is shared, all
callbacks are nested, and there is no supervision. The BT + WiFi rxBuf collision
(same frame arriving twice → corrupt JPEG accumulation) is a direct symptom.

What's missing:
- No ownership of state — any closure can mutate anything
- No channel separation — display frames, camera chunks, handshake bytes all share one pipe
- No supervisor — a crashed goroutine / stalled timer is invisible
- No external control plane — the harness can't pause, inspect, or restart a subsystem

### Target architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Supervisor                           │
│  owns lifecycle, watches all threads, handles errors    │
│  exposes control API to harness (IPC / REPL)           │
└─────┬───────────────┬────────────────┬──────────────────┘
      │               │                │
      ▼               ▼                ▼
┌──────────┐   ┌──────────┐   ┌───────────────┐
│ Transport│   │ Protocol │   │   Channels    │
│ Manager  │   │ State    │   │   Router      │
│          │   │ Machine  │   │               │
│ BT RX/TX │   │          │   │ Control chan  │
│ WiFi RX/TX│  │ phase 0→5│   │ Media chan    │
└──────────┘   └──────────┘   │ Heartbeat ch │
                               └───────────────┘
```

### Threads

| Thread | Role | Queue type |
|--------|------|-----------|
| `bt-rx` | Reads RFCOMM, reassembles frames, enqueues to protocol queue | Producer |
| `wifi-rx` | Reads TCP, reassembles frames, enqueues to protocol queue | Producer |
| `protocol` | Consumes frames; dispatches by channel + cmd byte | Consumer (serial) |
| `bt-tx` | Serialized writes to RFCOMM | Consumer (serial) |
| `wifi-tx` | Serialized writes to TCP | Consumer (serial) |
| `heartbeat` | Sends ping every N seconds, checks ack within timeout | Timer |
| `media` | Accumulates camera JPEG chunks; writes file on done | Consumer (serial) |
| `supervisor` | Monitors all threads, restarts on failure, reports health | Monitor |

### Channel model

Three logical channels over each transport:

```
Control    cmd bytes: 0x01–0x9f  (handshake, mode, WiFi, sensors, camera ctrl)
Media      cmd bytes: 0xb4–0xb8, 0xf1  (camera data: Request/Response/Data/Done/Ack)
Display    cmd bytes: 0xe0–0xff  (LayoutInit, PlaceImageData, etc.)
```

Transport × Channel matrix:
```
             BT RFCOMM       WiFi TCP
Control      PRIMARY         SECONDARY (dup ignored)
Display      fallback        PRIMARY (30fps)
Media        fallback        PRIMARY (camera chunks)
Heartbeat    always BT       mirror on WiFi
```

Rule: for each (channel, direction), exactly ONE transport is PRIMARY. The other
transport's duplicates are dropped. Primary is determined by `wifiActive` flag,
which is owned exclusively by the `protocol` thread (never mutated from callbacks).

### State machine

Protocol phases are owned by a single `ProtocolSM` actor. No other thread touches
`initPhase`. All phase transitions happen via `protocol` queue messages.

```swift
enum Phase { case p0_wait, p1_settings, p2_version, p3_fota,
             p4_openapp, p5_ready, p5_wifi }

actor ProtocolSM {
    private(set) var phase: Phase = .p0_wait
    private(set) var wifiActive = false
    private(set) var wifiClientFd: Int32 = -1
    func handle(frame: Frame, transport: Transport) async { ... }
}
```

### Supervisor

```swift
actor Supervisor {
    var threads: [String: ThreadHandle]
    var lastHeartbeatAck: Date = .now
    
    func watchdog() {
        // every 5s: check lastHeartbeatAck < 15s ago
        // if stale: restart bt-rx, wifi-rx, log alert
        // expose status to harness via emitEvent("HEALTH", ...)
    }
    func restart(_ thread: String) { ... }
}
```

### Harness control API

The harness (TypeScript TUI) controls the runtime via:
1. **REPL stdin** — human-typed commands (current)
2. **JSON events** at `/tmp/glasses-events.jsonl` — telemetry out
3. **Control socket** (new) — `unix:///tmp/glasses-control.sock` — structured commands in,
   structured responses out. Harness can send `{"cmd":"camera","args":["still","sxga"]}`.

This gives the harness (and automated tests) full control without stdin injection.

### Migration path

The rewrite does NOT have to be all at once. Incremental:

1. **Step 1 (now)**: Extract `wifiRxBuf` reassembly (done) + `handleWifiFrame` (done)
2. **Step 2**: Move `wifiActive` to be set only from `handleWifiFrame(0x97)` (done)
3. **Step 3**: Introduce `DispatchQueue` per channel (bt-rx, wifi-rx already separate)
4. **Step 4**: Extract `ProtocolSM` actor from the closure
5. **Step 5**: Add supervisor watchdog + heartbeat thread
6. **Step 6**: Add control socket for harness

---

## Track 2 — Android Emulator E2E Strategy

### Why emulator

Real hardware UAT is slow: requires powered glasses, proximity, BT pairing, WiFi setup.
Emulator gives:
- Deterministic timing
- CI/CD integration (no hardware)
- Full protocol coverage (inject any frame, read any response)
- Camera stub (inject synthetic JPEG frames)

### What exists in the SDK

Sony shipped `SmartEyeglassEmulator.apk` — an Android app that:
- Runs on a standard Android device or emulator
- Exposes `com.sony.smarteyeglass.MONITOR_SOCKET` (Android abstract UNIX socket)
- Listens for the same j2 protocol the real glasses use
- Renders the display on-screen
- Simulates sensors (accelerometer, light, battery) via UI sliders
- Has an `IHostAppMonitoring` AIDL interface for programmatic control
- Uses `McKinleyLocalServerConnection` — same as MisiAha daemon

The emulator IS the glasses — it speaks the identical wire protocol. No BT needed.

### Transport bridge: ADB socket forwarding

```
macOS glasses-tool.swift
    ↕  TCP localhost:7002
adb forward tcp:7002 localabstract:com.sony.smarteyeglass.MONITOR_SOCKET
    ↕  Android abstract UNIX socket (inside emulator)
SmartEyeglassEmulator.apk
```

`adb forward` creates a TCP proxy from macOS localhost:PORT to the Android abstract socket.
Our glasses-tool gets a new transport: `LocalSocket` that connects to localhost:7002 instead
of BT RFCOMM or WiFi TCP.

Same wire protocol. Same cmd bytes. No glasses hardware required.

### Emulator setup steps

```bash
# 1. Create AVD (Android 5.0 = API 21, x86, google_apis)
# Using installed SDK at /opt/homebrew/share/android-commandlinetools
SDK=/opt/homebrew/share/android-commandlinetools
avdmanager create avd \
  --name "SmartEyeglass_AVD" \
  --package "system-images;android-21;google_apis;x86" \
  --abi x86 \
  --device "Nexus 5"

# 2. Start emulator (headless)
$SDK/emulator/emulator -avd SmartEyeglass_AVD -no-window -no-audio &

# 3. Wait for boot
adb wait-for-device
adb shell getprop sys.boot_completed  # wait for "1"

# 4. Install Sony stack
adb install com.sonyericsson.extras.liveware_*.apk     # LiveWare extension manager
adb install com.sony.smarteyeglass_*.apk               # MisiAha daemon
adb install SmartEyeglassEmulator.apk                  # Emulator UI

# 5. Start the emulator app
adb shell am start -n com.sony.smarteyeglass.emulator/.MainActivity

# 6. Forward UNIX socket to TCP
adb forward tcp:7002 localabstract:com.sony.smarteyeglass.MONITOR_SOCKET

# 7. Connect glasses-tool via local socket
./macos-middleware/glasses-tool --local 127.0.0.1:7002
```

### What needs stubbing / bypassing

| Blocker | Approach |
|---------|---------|
| BT hardware requirement in MisiAha | Emulator app bypasses BT — uses LocalSocket directly |
| LiveWare checks for SmartEyeglass accessory | SmartEyeglassEmulator registers as a virtual accessory |
| Camera hardware | Emulator has `existsCamera` flag — can inject synthetic JPEG via `EXTRA_CAMERA_VIDEO_SOCKET_NAME` socket |
| Sensor hardware | Emulator has UI sliders; can drive via `adb shell input` or AIDL |
| Google Play Services | google_apis system image includes Play Services stubs |
| Package signature checks | `adb install` with `--bypass-signature` or use debug APK |

### Camera E2E via emulator

The emulator handles camera requests differently:
1. Host app sends `camera still` → our tool sends `0xce + 0x38 + 0xb4` to MONITOR_SOCKET
2. MisiAha daemon handles it, asks emulator for image
3. Emulator returns synthetic JPEG (a test image) via `EXTRA_CAMERA_VIDEO_SOCKET_NAME`
4. MisiAha encodes as `0xb5 + 0xb6 chunks + 0xb7` back through MONITOR_SOCKET
5. Our tool receives and saves JPEG

If synthetic camera isn't auto-triggered, inject via:
```bash
adb shell am broadcast \
  -a com.sony.smarteyeglass.CAMERA_NOTIFY_CAPTURED \
  --es com.sony.smarteyeglass.EXTRA_DATA_URI /sdcard/test.jpg
```

### glasses-tool LocalSocket transport

New transport type in Swift (alongside BT RFCOMM and WiFi TCP):

```swift
enum Transport {
    case bt(IOBluetoothRFCOMMChannel)
    case wifi(Int32)          // TCP fd
    case local(Int32)         // TCP fd to adb-forwarded UNIX socket
}
```

`--local HOST:PORT` flag → connect via TCP to adb-forwarded socket.
Same wire protocol. Same frame handler. Zero hardware dependency.

### CI/CD integration

```yaml
# .github/workflows/e2e.yml
- name: Start Android emulator
  run: |
    avdmanager create avd --name ci_avd --package "system-images;android-21;google_apis;x86" --abi x86
    emulator -avd ci_avd -no-window -no-audio &
    adb wait-for-device && adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'

- name: Install Sony stack
  run: |
    adb install apks/com.sonyericsson.extras.liveware.apk
    adb install apks/com.sony.smarteyeglass.apk
    adb install apks/SmartEyeglassEmulator.apk
    adb shell am start -n com.sony.smarteyeglass.emulator/.MainActivity
    adb forward tcp:7002 localabstract:com.sony.smarteyeglass.MONITOR_SOCKET

- name: Compile glasses-tool
  run: swiftc -O -o glasses-tool macos-middleware/glasses-tool.swift

- name: Run E2E tests
  run: uv run pytest tests/ -v --local 127.0.0.1:7002
```

### pytest integration

New `--local` flag for conftest `proc` fixture:
```python
@pytest.fixture(scope="module")
def proc(request):
    local = request.config.getoption("--local", default=None)
    args = ["./macos-middleware/glasses-tool"]
    if local:
        args += ["--local", local]
    ...
```

Tests become hardware-independent: same test suite runs on CI (emulator) and on
physical hardware (BT/WiFi).

---

## Work order

### Phase A — Architecture cleanup (pure Swift, no hardware needed)

- [ ] A1: `ProtocolSM` actor — extract state machine from closure
- [ ] A2: `TransportManager` — owns BT + WiFi fd, routes frames to correct queue
- [ ] A3: `ChannelRouter` — maps (cmdId, transport) → (Control|Media|Display|Heartbeat)
- [ ] A4: Camera `MediaChannel` — dedicated queue, dedup, chunk accumulation, file write
- [ ] A5: Supervisor watchdog + heartbeat
- [ ] A6: Control socket (`unix:///tmp/glasses-control.sock`)

### Phase B — Local transport (ADB)

- [ ] B1: `--local HOST:PORT` flag in glasses-tool → TCP instead of RFCOMM
- [ ] B2: ADB forward script (`scripts/adb-forward.sh`)
- [ ] B3: Emulator setup script (`scripts/setup-emulator.sh`)
- [ ] B4: Verify full handshake + display + camera against emulator

### Phase C — E2E test suite on emulator

- [ ] C1: `--local` flag in pytest conftest
- [ ] C2: Emulator-aware `test_protocol.py` (no tap required)
- [ ] C3: `test_camera_emulator.py` (synthetic JPEG injection)
- [ ] C4: GitHub Actions workflow for CI

### Phase D — Harness control socket

- [ ] D1: Add control socket to glasses-tool
- [ ] D2: Harness TypeScript client for control socket
- [ ] D3: Replace stdin injection in tests with socket commands

---

## Key files to create

```
scripts/
  setup-emulator.sh      # create AVD, install APKs, forward socket
  adb-forward.sh         # just the adb forward step (fast re-run)
  teardown-emulator.sh   # kill emulator, remove forward

macos-middleware/
  Sources/               # refactored: split glasses-tool.swift into modules
    Transport.swift      # BT + WiFi + Local transport abstraction
    Protocol.swift       # ProtocolSM actor
    Channels.swift       # ChannelRouter (Control/Media/Display)
    Camera.swift         # MediaChannel + JPEG accumulator
    Supervisor.swift     # watchdog + heartbeat
    REPL.swift           # interactive commands
    Main.swift           # entry point

tests/
  test_camera_emulator.py   # camera E2E against emulator
  conftest.py               # updated with --local flag
```
