# ARCHITECTURE_MODERN.md — Sony SED-E1: From Android to Modern Platforms

> Comprehensive architecture analysis: Sony's original SmartEyeglass framework deconstructed,  
> then reimagined across Swift Actors, Kotlin Multiplatform, and Rust+WASM.  
> Written for engineers who will implement from this document.

---

## Part 1: "What Sony Built" — Architecture Archaeology

### 1.1 The Three-Layer Stack

```
┌──────────────────────────────────────────────────────────────────┐
│ Layer 1: Extension App                                           │
│   ExplorerExtensionService → ExplorerControl → BaseDemo[8]       │
│   Uses: SmartEyeglassControlUtils, AccessorySensorManager        │
│   IPC out: Intents (broadcast + tunneled) to HostApp             │
│   IPC in:  BroadcastReceiver (16 actions) + LocalSocket (sensors)│
└──────────────┬───────────────────────────────────────────────────┘
               │ Android Intents (or Tunnel Messenger)
               │ ContentProvider queries (Registration tables)
               │ LocalSocket (sensor data, camera data, AR animation)
┌──────────────▼───────────────────────────────────────────────────┐
│ Layer 2: Host App (MisiAha daemon / SmartConnect)                │
│   McKinleyConnectionControllerHandler                            │
│   5 transports: BT RFCOMM, WiFi TCP, USB, LocalSocket, Monitor  │
│   Translates: Intent extras → j2 wire protocol bytes            │
│   Translates: wire protocol bytes → Intent broadcasts           │
└──────────────┬───────────────────────────────────────────────────┘
               │ j2 wire protocol: [cmdId:1B][len:2B][payload:varB]
               │ BT RFCOMM SPP (default) or WiFi TCP (high bandwidth)
┌──────────────▼───────────────────────────────────────────────────┐
│ Layer 3: Glasses Hardware (SED-E1) — IMMUTABLE FIRMWARE          │
│   419×138 green monochrome OLED                                  │
│   3MP CMOS camera (JPEG output)                                  │
│   BMI160 IMU (accel + gyro + mag)                                │
│   Capacitive touch strip                                         │
│   WiFi 802.11b/g/n 2.4GHz + Bluetooth 3.0 SPP                   │
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 Exact Data Flow: Demo Tap → Glasses Display Update

Trace a single tap event through the full stack (e.g., TextDemo cycling font size):

```
1. User taps glasses touch sensor
   └─ Hardware generates: [0xe5][0x00][0x02][action][data]  (LayoutEventNotify)

2. Wire → MisiAha daemon
   └─ McKinleyConnectionControllerHandler.handleFrame(0xe5, payload)
   └─ Parses action byte, constructs Intent:
        action = "com.sonyericsson.extras.liveware.aef.control.TOUCH_EVENT"
        extras: TOUCH_ACTION=RELEASE, X=..., Y=...

3. MisiAha → Extension App (via BroadcastReceiver or Tunnel)
   └─ ExtensionService.onStartCommand(intent)
   └─ handleIntent() → handleControlIntent()
   └─ Dispatches to ControlExtension.onTouch(ControlTouchEvent)
   └─ ExplorerControl checks mActivDemo != null → calls mActivDemo.onTap()

4. TextDemo.onTap()
   └─ mFontIndex = (mFontIndex + 1) % 4
   └─ Renders new Bitmap (419×138 ARGB_8888) via Canvas API
   └─ Calls pushFrame(bitmap) → utils.showBitmap(bitmap)

5. SmartEyeglassControlUtils.showBitmap(bitmap)
   └─ Converts ARGB → 8-bit monochrome: luma = (R×299 + G×587 + B×114) / 1000
   └─ Constructs Intent:
        action = "com.sonyericsson.extras.liveware.aef.control.DISPLAY_DATA"
        extras: EXTRA_DATA = byte[] (8-bit per pixel), EXTRA_DATA_IS_RAW_FORMAT = 1
   └─ sendToHostApp(intent)  [broadcast or tunnel]

6. MisiAha receives CONTROL_DISPLAY_DATA Intent
   └─ Extracts raw 8-bit image bytes (57,822 bytes for 419×138)
   └─ Builds wire command:
        [0xe7][len_hi][len_lo]
          [0x01][...] PlaceState subcommand
          [0x03][...] PlaceImgObj subcommand (x=0, y=0, w=419, h=138)
          [0x07][...] ImgData subcommand (fmt=1 + DEFLATE compressed pixels)
   └─ Sends LayoutInit(0xe0) if not already initialized
   └─ Sends LayoutPlaceRemoveCommand(0xe7) over active transport

7. Glasses firmware receives [0xe7] frame
   └─ Decompresses DEFLATE payload (raw deflate, wbits=-15)
   └─ Maps 8-bit grayscale → green monochrome PWM
   └─ Updates 419×138 OLED display
```

### 1.3 Layer Responsibilities — What Each Adds/Removes

| Concern | Extension App | Host App (MisiAha) | Glasses FW |
|---------|--------------|-------------------|-----------|
| **Business logic** | ✅ All demo logic | ✗ Pure relay | ✗ Pure render |
| **Rendering** | ✅ Android Canvas → Bitmap | ✗ Passthrough | ✅ Display driver |
| **Image encoding** | ✅ ARGB→8-bit mono | ✅ DEFLATE compression | ✅ Decompression |
| **Transport** | ✗ Unaware | ✅ BT/WiFi/USB mux | ✅ BT+WiFi radio |
| **State machine** | Partial (lifecycle) | ✅ Full protocol SM | ✅ Firmware SM |
| **Framing** | ✗ Unaware | ✅ [cmd][len][payload] | ✅ Frame parsing |
| **Security** | Extension key | Permission checks | ✗ None |
| **Sensor routing** | ✅ Registers listeners | ✅ LocalSocket relay | ✅ IMU driver |
| **Camera pipeline** | ✅ Mode/capture API | ✅ JPEG chunk relay | ✅ CMOS capture |

### 1.4 Android-Specific vs Protocol-Universal

**Android-specific (must be replaced on other platforms):**
- `Intent` broadcasting (action strings, extras bundles)
- `BroadcastReceiver` for 16 event types
- `ContentProvider` for registration/capability discovery
- `ExtensionService` (Android Service lifecycle)
- `AsyncTask` for registration
- `Handler` + `Looper` for thread confinement
- `LocalSocket` (Android abstract UNIX domain sockets) for sensor/camera data
- `Bitmap` / `Canvas` rendering API
- Android permission model

**Protocol-universal (same on every platform):**
- Wire format: `[cmdId:1B][len:2B][payload:varB]`
- Handshake sequence: `0x0a → 0x71 → 0x07 → 0x85 → 0x81 → 0xff → 0x30`
- Display protocol: `0xe0` (LayoutInit) + `0xe7` (LayoutPlaceRemove)
- Camera protocol: `0xce → 0xb4 → 0xb5 → 0xb6+0xf1 → 0xb7`
- Sensor wire format: `0x38` (start) → `0x3a/0xbc/0xbd/0xbb/0x3b` (data)
- WiFi negotiation: `0x92 → 0x91 → 0x94 → 0x95 → 0x96 → 0x97`
- Image encoding: 8-bit grayscale, DEFLATE compressed, row-major
- Touch/input events: `0xe5` (LayoutEventNotify), `0x06` (LevelNotification)
- Heartbeat/keepalive: `0x05` (PING)

### 1.5 IPC Boundary Map

```
Extension App ←──Intent broadcast──→ Host App
               ←──Tunnel Messenger──→ (fast path, bypasses broadcast queue)
               ←──ContentProvider───→ (registration queries only)
               ←──LocalSocket──────→ (sensor data: binary frames)
               ←──LocalSocket──────→ (camera data: JPEG chunks via "CameraImage" socket)
               ←──LocalSocket──────→ (AR animation: PNG frames)

Host App ←──BT RFCOMM SPP──→ Glasses
         ←──WiFi TCP────────→ Glasses (after 0x92→0x94→0x96 upgrade)
         ←──USB/LocalSocket─→ Emulator (debug path)
```

---

## Part 2: "Modern Reimagination" — Three Platform Designs

### 2A: Swift/Apple Actor Model (macOS/iOS)

#### Architecture Overview

The key insight: Sony used `Handler` + `Looper` + synchronized blocks for thread safety. Swift actors provide the same guarantees with compile-time enforcement.

```
┌──────────────────────────────────────────────────────────────────┐
│                      SupervisorActor                             │
│   Owns lifecycle of all child actors                            │
│   Health monitoring, restart policy                              │
│   Exposes ControlAPI (async methods for harness/tests)          │
└──────┬───────────┬──────────────┬───────────────┬───────────────┘
       │           │              │               │
       ▼           ▼              ▼               ▼
┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────────┐
│ Transport  │ │ Display    │ │ Camera     │ │ Sensor         │
│ Actor      │ │ Actor      │ │ Actor      │ │ Actor          │
│            │ │            │ │            │ │                │
│ BT + WiFi  │ │ LayoutInit │ │ SetMode    │ │ Register       │
│ Mux/Demux  │ │ PlaceRemove│ │ Capture    │ │ Stream decode  │
│ rxBuf own  │ │ Compress   │ │ ChunkAccum │ │ Publish values │
│ Frame parse│ │ Rate limit │ │ ACK mgmt  │ │                │
└────────────┘ └────────────┘ └────────────┘ └────────────────┘
                      ▲              ▲               ▲
                      │              │               │
              ┌───────┴──────────────┴───────────────┘
              │         AsyncChannel<WireFrame>
              │   (typed events from TransportActor)
              ▼
        ┌───────────┐
        │ Protocol  │
        │ Actor     │
        │           │
        │ State:    │
        │  .wait    │   Handshake FSM
        │  .settings│   Phase transitions
        │  .version │   Routes decoded frames
        │  .fota    │   to correct subsystem actor
        │  .openapp │
        │  .ready   │
        └───────────┘
```

#### Actor Definitions

```swift
// ── Wire types (shared, Sendable) ──────────────────────────────────

enum Transport: Sendable {
    case bluetooth(IOBluetoothRFCOMMChannel)
    case wifi(FileDescriptor)
    case local(FileDescriptor)
}

struct WireFrame: Sendable {
    let cmdId: UInt8
    let payload: Data
    let transport: Transport
}

enum ProtocolPhase: Sendable {
    case waitProtocolVersion       // phase 0: waiting for 0x0a
    case waitSettingsResponse      // phase 1: sent 0x71, waiting 0x72
    case waitVersionResponse       // phase 2: sent 0x07, waiting 0x08
    case waitFotaStatus            // phase 3: sent 0x85, waiting 0x81
    case waitOpenAppConfirm        // phase 4: sent 0xff/0x30, waiting 0x31/0x06
    case ready                     // phase 5: display operational
}

// ── TransportActor ─────────────────────────────────────────────────

actor TransportActor {
    private var btChannel: IOBluetoothRFCOMMChannel?
    private var wifiClientFd: FileDescriptor?
    private var wifiActive = false

    // Each transport owns its own reassembly buffer — NO shared rxBuf
    private var btRxBuf = Data()
    private var wifiRxBuf = Data()

    // Outbound: parsed frames for ProtocolActor
    let frames: AsyncStream<WireFrame>
    private let framesContinuation: AsyncStream<WireFrame>.Continuation

    init() {
        (frames, framesContinuation) = AsyncStream.makeStream(of: WireFrame.self)
    }

    /// Receive raw bytes from BT RFCOMM callback.
    /// Called from the RFCOMM delegate on an arbitrary thread — actor
    /// serialization guarantees btRxBuf is never accessed concurrently.
    func receiveBT(_ data: Data) {
        btRxBuf.append(data)
        drainFrames(from: &btRxBuf, transport: .bluetooth(btChannel!))
    }

    /// Receive raw bytes from WiFi TCP read loop.
    func receiveWiFi(_ data: Data) {
        wifiRxBuf.append(data)
        drainFrames(from: &wifiRxBuf, transport: .wifi(wifiClientFd!))
    }

    /// Parse complete [cmdId:1B][len:2B][payload] frames from buffer.
    private func drainFrames(from buffer: inout Data, transport: Transport) {
        while buffer.count >= 3 {
            let len = (Int(buffer[1]) << 8) | Int(buffer[2])
            let total = 3 + len
            guard buffer.count >= total else { break }
            let frame = WireFrame(
                cmdId: buffer[0],
                payload: Data(buffer[3..<total]),
                transport: transport
            )
            buffer = Data(buffer[total...])
            framesContinuation.yield(frame)
        }
    }

    /// Send command bytes over the primary transport.
    /// WiFi is primary when wifiActive; BT otherwise.
    func send(_ bytes: [UInt8], label: String) async {
        if wifiActive, let fd = wifiClientFd {
            await sendTCP(bytes, fd: fd, label: label)
        } else if let ch = btChannel {
            await sendRFCOMM(bytes, channel: ch, label: label)
        }
    }

    // Transport-specific send implementations...
    private func sendRFCOMM(_ bytes: [UInt8], channel: IOBluetoothRFCOMMChannel,
                            label: String) async {
        let mtu = Int(channel.getMTU())
        let chunkSize = mtu > 0 ? mtu : 665
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunkSize, bytes.count)
            var chunk = Array(bytes[offset..<end])
            channel.writeSync(&chunk, length: UInt16(chunk.count))
            offset = end
        }
    }

    private func sendTCP(_ bytes: [UInt8], fd: FileDescriptor,
                         label: String) async {
        var buf = bytes
        _ = Darwin.write(fd.rawValue, &buf, buf.count)
    }

    func activateWiFi(clientFd: FileDescriptor) {
        wifiClientFd = clientFd
        wifiActive = true
    }

    func deactivateWiFi() {
        wifiActive = false
    }
}
```

**How actors solve the BT+WiFi rxBuf collision:**

In the monolithic `glasses-tool.swift`, `rxBuf` is a single `Data` buffer shared between BT RFCOMM callbacks and the main RunLoop. When WiFi activates, camera chunks arrive on the WiFi TCP read loop, but BT may still deliver duplicate/stale frames to the same `rxBuf`. The current mitigation is a separate `wifiRxBuf` with manual dispatch.

With actors, this is structurally impossible:

1. **`TransportActor` owns both buffers** — `btRxBuf` and `wifiRxBuf` are private actor state. Actor reentrancy rules guarantee only one method executes at a time.
2. **Each transport calls its own method** — `receiveBT()` touches only `btRxBuf`, `receiveWiFi()` touches only `wifiRxBuf`. No cross-contamination.
3. **Parsed frames are typed** — `WireFrame` carries its `.transport` origin. The `ProtocolActor` can implement dedup: if `wifiActive`, ignore camera frames from `.bluetooth`.
4. **Compile-time enforcement** — Marking buffers as actor-isolated means the compiler rejects any attempt to access them from outside the actor.

```swift
// ── ProtocolActor ──────────────────────────────────────────────────

actor ProtocolActor {
    private var phase: ProtocolPhase = .waitProtocolVersion
    private let transport: TransportActor
    private let display: DisplayActor
    private let camera: CameraActor
    private let sensor: SensorActor

    init(transport: TransportActor, display: DisplayActor,
         camera: CameraActor, sensor: SensorActor) {
        self.transport = transport
        self.display = display
        self.camera = camera
        self.sensor = sensor
    }

    /// Main run loop — consumes frames from TransportActor.
    func run() async {
        for await frame in await transport.frames {
            await handle(frame)
        }
    }

    private func handle(_ frame: WireFrame) async {
        switch (phase, frame.cmdId) {

        // ── Handshake FSM ──────────────────────────────────────────
        case (.waitProtocolVersion, 0x0a):
            phase = .waitSettingsResponse
            await transport.send([0x71, 0x00, 0x00], label: "SettingsStatusReq")

        case (.waitSettingsResponse, 0x72):
            phase = .waitVersionResponse
            await transport.send([0x07, 0x00, 0x01, 0x01], label: "VersionReq")

        case (.waitVersionResponse, 0x08):
            phase = .waitFotaStatus
            await transport.send([0x85, 0x00, 0x04, 0, 0, 0, 0], label: "NewHostApp")

        case (.waitFotaStatus, 0x81):
            phase = .waitOpenAppConfirm
            await transport.send([0xff, 0x00, 0x00], label: "SyncResponse")

        case (.waitOpenAppConfirm, 0x31), (.waitOpenAppConfirm, 0x06):
            phase = .ready
            await display.initialize()

        // ── Ready-state routing ────────────────────────────────────
        case (.ready, 0xe5):  // Touch/tap event
            // Route to active demo controller
            break

        case (.ready, 0xb5):  // CameraCaptureResponse
            await camera.handleCaptureResponse(frame.payload)
        case (.ready, 0xb6):  // CameraCaptureData chunk
            await camera.handleChunk(frame.payload)
            let ack = camera.buildAck(frame.payload)
            await transport.send(ack, label: "CaptureDataAck")
        case (.ready, 0xb7):  // CameraCaptureDataDone
            await camera.handleDone(frame.payload)

        case (.ready, 0x3a):  // Accelerometer
            await sensor.handleAccelerometer(frame.payload)
        case (.ready, 0xbc):  // Gyroscope
            await sensor.handleGyroscope(frame.payload)
        case (.ready, 0xbd):  // Magnetometer
            await sensor.handleMagnetometer(frame.payload)

        // WiFi — handled in any phase
        case (_, 0x91): await handleWiFiStatus(frame.payload)
        case (_, 0x95): await handleWiFiConnectivity(frame.payload)
        case (_, 0x97): await handleWiFiPathSwitch(frame.payload)

        default: break
        }
    }
}
```

```swift
// ── DisplayActor ───────────────────────────────────────────────────

actor DisplayActor {
    private let transport: TransportActor
    private var initialized = false
    private let width = 419
    private let height = 138

    func initialize() async {
        let layoutInit: [UInt8] = [0xe0, 0x00, 0x0a,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        await transport.send(layoutInit, label: "LayoutInit")
        initialized = true
    }

    /// Encode 8-bit grayscale image and send as LayoutPlaceRemoveCommand.
    func showBitmap(_ grayscale: [UInt8]) async {
        guard initialized else { return }
        let compressed = deflateCompress(grayscale)

        var sub1: [UInt8] = [0x01, 0x00, 0x0a]  // PLACE_STATE
        sub1 += [UInt8](repeating: 0, count: 10)

        var sub2: [UInt8] = [0x03, 0x00, 0x18]  // PLACE_IMGOBJ
        sub2 += [0x00, 0x00, 0x00, 0x00]        // objId, layerId
        sub2 += [0x00, 0x00, 0x00, 0x00]        // x=0
        sub2 += [0x00, 0x00, 0x00, 0x00]        // y=0
        sub2 += [0x01, 0xa3]                    // width=419
        sub2 += [0x00, 0x8a]                    // height=138
        sub2 += [UInt8](repeating: 0, count: 8) // flags

        let imgLen = 2 + 1 + compressed.count
        var sub3: [UInt8] = [0x07, UInt8((imgLen >> 8) & 0xff), UInt8(imgLen & 0xff)]
        sub3 += [0x00, 0x00]  // objId=0
        sub3 += [0x01]        // imgFormat=1 (8-bit mono + DEFLATE)
        sub3 += compressed

        let totalPayload = sub1.count + sub2.count + sub3.count
        var cmd: [UInt8] = [0xe7, UInt8((totalPayload >> 8) & 0xff),
                                  UInt8(totalPayload & 0xff)]
        cmd += sub1; cmd += sub2; cmd += sub3
        await transport.send(cmd, label: "LayoutPlaceRemove")
    }
}
```

```swift
// ── CameraActor ────────────────────────────────────────────────────

actor CameraActor {
    private let transport: TransportActor
    private var expectedBytes = 0
    private var accumulator = Data()
    private var capturing = false
    private var nextExpectedSeq = 0

    /// Stream of completed JPEG captures for consumers.
    let captures: AsyncStream<Data>
    private let capturesContinuation: AsyncStream<Data>.Continuation

    init(transport: TransportActor) {
        self.transport = transport
        (captures, capturesContinuation) = AsyncStream.makeStream(of: Data.self)
    }

    func startStillCapture(resolution: UInt8 = 1) async {
        await transport.send([0xce, 0x00, 0x04, 0x00, resolution, 0x01, 0x00],
                             label: "CameraMode(STILL)")
        try? await Task.sleep(for: .milliseconds(300))
        await transport.send([0x38, 0x00, 0x04, 0x13, 0x06, 0x00, 0x00],
                             label: "SensorStart(camera)")
        try? await Task.sleep(for: .milliseconds(500))
        await transport.send([0xb4, 0x00, 0x00], label: "CameraCaptureReq")
    }

    func handleCaptureResponse(_ payload: Data) {
        guard payload.count >= 10 else { return }
        let status = payload[0]
        if status == 0 {
            expectedBytes = Int(payload[2]) | (Int(payload[3]) << 8) |
                           (Int(payload[4]) << 16) | (Int(payload[5]) << 24)
            accumulator = Data()
            nextExpectedSeq = 0
            capturing = true
        }
    }

    func handleChunk(_ payload: Data) {
        guard capturing, payload.count > 3 else { return }
        let seq = Int(payload[0])
        guard seq == nextExpectedSeq else { return }  // dedup
        let jpegData = payload[3...]
        accumulator.append(jpegData)
        nextExpectedSeq += 1
    }

    func buildAck(_ payload: Data) -> [UInt8] {
        [0xf1, 0x00, 0x01, payload[0]]
    }

    func handleDone(_ payload: Data) {
        capturing = false
        if !accumulator.isEmpty {
            capturesContinuation.yield(accumulator)
        }
        accumulator = Data()
    }
}
```

```swift
// ── SensorActor ────────────────────────────────────────────────────

actor SensorActor {
    struct IMUReading: Sendable {
        var accel: SIMD3<Float> = .zero
        var gyro: SIMD3<Float> = .zero
        var mag: SIMD3<Float> = .zero
    }

    /// Continuous sensor stream for UI consumers.
    let readings: AsyncStream<IMUReading>
    private let readingsContinuation: AsyncStream<IMUReading>.Continuation
    private var current = IMUReading()

    init() {
        (readings, readingsContinuation) = AsyncStream.makeStream(of: IMUReading.self)
    }

    func handleAccelerometer(_ payload: Data) {
        guard payload.count >= 12 else { return }
        current.accel = extractSIMD3(payload)
        readingsContinuation.yield(current)
    }

    func handleGyroscope(_ payload: Data) {
        guard payload.count >= 12 else { return }
        current.gyro = extractSIMD3(payload)
        readingsContinuation.yield(current)
    }

    func handleMagnetometer(_ payload: Data) {
        guard payload.count >= 12 else { return }
        current.mag = extractSIMD3(payload)
        readingsContinuation.yield(current)
    }

    private func extractSIMD3(_ data: Data) -> SIMD3<Float> {
        data.withUnsafeBytes { buf in
            SIMD3(buf.load(fromByteOffset: 0, as: Float.self),
                  buf.load(fromByteOffset: 4, as: Float.self),
                  buf.load(fromByteOffset: 8, as: Float.self))
        }
    }
}
```

#### Demo Mapping to SwiftUI / Headless Controllers

```swift
// Each Sony demo becomes a GlassesDemo protocol conformance:

protocol GlassesDemo: Sendable {
    var name: String { get }
    func onEnter(display: DisplayActor, camera: CameraActor,
                 sensor: SensorActor, transport: TransportActor) async
    func onTap() async
    func onSwipe(_ direction: SwipeDirection) async
    func onExit() async
}

// TextDemo — headless, no SwiftUI needed
final class TextDemo: GlassesDemo, @unchecked Sendable {
    let name = "Display: Text"
    private var fontSizeIndex = 2
    private let fontSizes = [16, 20, 24, 28]
    private weak var display: DisplayActor?

    func onEnter(display: DisplayActor, camera: CameraActor,
                 sensor: SensorActor, transport: TransportActor) async {
        self.display = display
        await render()
    }

    func onTap() async {
        fontSizeIndex = (fontSizeIndex + 1) % fontSizes.count
        await render()
    }

    private func render() async {
        let grayscale = renderTextFrame(fontSize: fontSizes[fontSizeIndex])
        await display?.showBitmap(grayscale)
    }

    func onSwipe(_ direction: SwipeDirection) async {}
    func onExit() async {}
}

// AnimationDemo — uses Task for frame loop
final class AnimationDemo: GlassesDemo, @unchecked Sendable {
    let name = "Display: Animate"
    private var frameTask: Task<Void, Never>?
    private var paused = false

    func onEnter(display: DisplayActor, camera: CameraActor,
                 sensor: SensorActor, transport: TransportActor) async {
        frameTask = Task {
            var scanY = 0
            while !Task.isCancelled {
                guard !paused else {
                    try? await Task.sleep(for: .milliseconds(66))
                    continue
                }
                let frame = renderScanLine(y: scanY, width: 419, height: 138)
                await display.showBitmap(frame)
                scanY = (scanY + 3) % 138
                try? await Task.sleep(for: .milliseconds(66))  // ~15fps
            }
        }
    }

    func onTap() async { paused.toggle() }
    func onSwipe(_ direction: SwipeDirection) async {}
    func onExit() async { frameTask?.cancel() }
}

// SensorDemo — consumes AsyncStream
final class SensorDemo: GlassesDemo, @unchecked Sendable {
    let name = "Sensors: Live"
    private var sensorTask: Task<Void, Never>?

    func onEnter(display: DisplayActor, camera: CameraActor,
                 sensor: SensorActor, transport: TransportActor) async {
        sensorTask = Task {
            for await reading in await sensor.readings {
                let frame = renderSensorReadout(
                    accel: reading.accel,
                    gyro: reading.gyro
                )
                await display.showBitmap(frame)
            }
        }
    }

    func onTap() async { /* toggle mock data */ }
    func onSwipe(_ direction: SwipeDirection) async {}
    func onExit() async { sensorTask?.cancel() }
}

// CameraStreamDemo — consumes camera captures
final class CameraStreamDemo: GlassesDemo, @unchecked Sendable {
    let name = "Camera: Stream"
    private var streamTask: Task<Void, Never>?

    func onEnter(display: DisplayActor, camera: CameraActor,
                 sensor: SensorActor, transport: TransportActor) async {
        // Display shows stats, not the actual JPEG
        streamTask = Task {
            var frameCount = 0
            let startTime = ContinuousClock.now
            for await jpegData in await camera.captures {
                frameCount += 1
                let elapsed = ContinuousClock.now - startTime
                let fps = Double(frameCount) / elapsed.seconds
                let frame = renderStreamStats(
                    frameNum: frameCount,
                    fps: fps,
                    bytes: jpegData.count
                )
                await display.showBitmap(frame)
            }
        }
    }

    func onTap() async { /* toggle stream */ }
    func onSwipe(_ direction: SwipeDirection) async {}
    func onExit() async { streamTask?.cancel() }
}
```

#### SwiftUI Integration (optional UI host)

```swift
// For macOS/iOS apps that want to show glasses state in a native UI:

@Observable
final class GlassesViewModel {
    var phase: ProtocolPhase = .waitProtocolVersion
    var wifiActive = false
    var activeDemo: (any GlassesDemo)?
    var sensorReading: SensorActor.IMUReading = .init()
    var lastCapture: Data?

    private var supervisor: SupervisorActor?

    func connect(address: String) async {
        supervisor = SupervisorActor()
        await supervisor?.start(address: address)

        // Observe state changes
        Task {
            guard let sensor = await supervisor?.sensor else { return }
            for await reading in await sensor.readings {
                await MainActor.run { self.sensorReading = reading }
            }
        }
    }
}
```

---

### 2B: Kotlin Multiplatform (Android + Desktop/iOS)

#### Module Structure

```
smarteyeglass-kmp/
├── shared/                          # Kotlin Multiplatform shared module
│   ├── src/commonMain/
│   │   ├── protocol/
│   │   │   ├── WireFrame.kt        # [cmdId, len, payload] parsing
│   │   │   ├── ProtocolStateMachine.kt
│   │   │   ├── Commands.kt         # Command builders (0xe7, 0xce, etc.)
│   │   │   └── ImageEncoder.kt     # ARGB→8bit mono, DEFLATE
│   │   ├── subsystem/
│   │   │   ├── DisplayController.kt
│   │   │   ├── CameraController.kt
│   │   │   └── SensorController.kt
│   │   ├── demo/
│   │   │   ├── Demo.kt             # interface
│   │   │   ├── TextDemo.kt
│   │   │   ├── AnimationDemo.kt
│   │   │   ├── GraphicsDemo.kt
│   │   │   ├── TouchDemo.kt
│   │   │   ├── SensorDemo.kt
│   │   │   ├── CameraCaptureDemo.kt
│   │   │   ├── CameraStreamDemo.kt
│   │   │   └── ARDemo.kt
│   │   └── GlassesViewModel.kt     # Shared ViewModel with StateFlow
│   │
│   ├── src/androidMain/
│   │   └── transport/
│   │       ├── BluetoothTransport.kt  # Android BluetoothSocket
│   │       └── WifiTransport.kt       # Android TCP socket
│   │
│   ├── src/iosMain/
│   │   └── transport/
│   │       └── IOBluetoothTransport.kt  # Delegates to Swift via expect/actual
│   │
│   └── src/desktopMain/
│       └── transport/
│           └── TcpTransport.kt     # JVM TCP for emulator/ADB
│
├── android-app/                     # Android Compose UI
├── ios-app/                         # SwiftUI host (uses shared KMP module)
└── desktop-app/                     # Compose Desktop
```

#### Core Shared Code

```kotlin
// ── Wire protocol types ────────────────────────────────────────────

data class WireFrame(
    val cmdId: UByte,
    val payload: ByteArray,
    val transport: TransportType
)

enum class TransportType { BLUETOOTH, WIFI, LOCAL }

// ── Transport abstraction (expect/actual) ──────────────────────────

// commonMain:
expect class PlatformTransport {
    suspend fun connect(address: String)
    suspend fun send(bytes: ByteArray)
    fun receiveFlow(): Flow<ByteArray>
    suspend fun disconnect()
}

// ── Frame reassembly (shared, replaces Android's LocalSocket) ──────

class FrameReassembler {
    private val buffer = ByteArrayOutputStream()

    fun feed(chunk: ByteArray): List<WireFrame> {
        buffer.write(chunk)
        val frames = mutableListOf<WireFrame>()
        val data = buffer.toByteArray()
        var offset = 0

        while (offset + 3 <= data.size) {
            val cmdId = data[offset].toUByte()
            val len = (data[offset + 1].toInt() and 0xFF shl 8) or
                      (data[offset + 2].toInt() and 0xFF)
            val total = 3 + len
            if (offset + total > data.size) break

            frames.add(WireFrame(
                cmdId = cmdId,
                payload = data.copyOfRange(offset + 3, offset + total),
                transport = TransportType.BLUETOOTH  // set by caller
            ))
            offset += total
        }

        // Keep remainder
        buffer.reset()
        if (offset < data.size) {
            buffer.write(data, offset, data.size - offset)
        }
        return frames
    }
}
```

```kotlin
// ── Protocol State Machine ─────────────────────────────────────────

class ProtocolStateMachine(
    private val transport: PlatformTransport,
    private val display: DisplayController,
    private val camera: CameraController,
    private val sensor: SensorController
) {
    private val _phase = MutableStateFlow(Phase.WAIT_PROTOCOL_VERSION)
    val phase: StateFlow<Phase> = _phase.asStateFlow()

    enum class Phase {
        WAIT_PROTOCOL_VERSION, WAIT_SETTINGS, WAIT_VERSION,
        WAIT_FOTA, WAIT_OPENAPP, READY
    }

    suspend fun handleFrame(frame: WireFrame) {
        when (_phase.value to frame.cmdId.toInt()) {
            Phase.WAIT_PROTOCOL_VERSION to 0x0a -> {
                _phase.value = Phase.WAIT_SETTINGS
                transport.send(byteArrayOf(0x71, 0x00, 0x00))
            }
            Phase.WAIT_SETTINGS to 0x72 -> {
                _phase.value = Phase.WAIT_VERSION
                transport.send(byteArrayOf(0x07, 0x00, 0x01, 0x01))
            }
            Phase.WAIT_VERSION to 0x08 -> {
                _phase.value = Phase.WAIT_FOTA
                transport.send(byteArrayOf(0x85.toByte(), 0x00, 0x04, 0, 0, 0, 0))
            }
            Phase.WAIT_FOTA to 0x81 -> {
                _phase.value = Phase.WAIT_OPENAPP
                transport.send(byteArrayOf(0xff.toByte(), 0x00, 0x00))
            }
            Phase.WAIT_OPENAPP to 0x31,
            Phase.WAIT_OPENAPP to 0x06 -> {
                _phase.value = Phase.READY
                display.initialize()
            }
            // Ready-state routing
            else -> if (_phase.value == Phase.READY) routeReadyFrame(frame)
        }
    }

    private suspend fun routeReadyFrame(frame: WireFrame) {
        when (frame.cmdId.toInt()) {
            0xe5 -> { /* touch event → active demo */ }
            0xb5 -> camera.onCaptureResponse(frame.payload)
            0xb6 -> {
                camera.onChunk(frame.payload)
                val ack = camera.buildAck(frame.payload)
                transport.send(ack)
            }
            0xb7 -> camera.onDone(frame.payload)
            0x3a -> sensor.onAccelerometer(frame.payload)
            0xbc -> sensor.onGyroscope(frame.payload)
            0xbd -> sensor.onMagnetometer(frame.payload)
        }
    }
}
```

```kotlin
// ── Shared ViewModel ───────────────────────────────────────────────
// Replaces Android Intent broadcasting with Kotlin Flows

class GlassesViewModel(
    private val transport: PlatformTransport  // injected per-platform
) : ViewModel() {

    private val btReassembler = FrameReassembler()
    private val wifiReassembler = FrameReassembler()  // separate buffer!

    val display = DisplayController(transport)
    val camera = CameraController(transport)
    val sensor = SensorController()
    val protocol = ProtocolStateMachine(transport, display, camera, sensor)

    // Observable state (replaces Intent extras → BroadcastReceiver)
    val phase: StateFlow<ProtocolStateMachine.Phase> = protocol.phase
    val sensorData: StateFlow<IMUReading> = sensor.readings
    val lastCapture: StateFlow<ByteArray?> = camera.lastCapture

    // Demo management
    private val _activeDemo = MutableStateFlow<Demo?>(null)
    val activeDemo: StateFlow<Demo?> = _activeDemo.asStateFlow()

    private val demos = listOf(
        TextDemo(), AnimationDemo(), GraphicsDemo(), TouchDemo(),
        SensorDemo(), CameraCaptureDemo(), CameraStreamDemo(), ARDemo()
    )

    fun connect(address: String) {
        viewModelScope.launch {
            transport.connect(address)

            // Main receive loop — replaces ExtensionService.handleIntent()
            transport.receiveFlow().collect { chunk ->
                val frames = btReassembler.feed(chunk)
                frames.forEach { protocol.handleFrame(it) }
            }
        }
    }

    fun selectDemo(index: Int) {
        viewModelScope.launch {
            _activeDemo.value?.onExit()
            val demo = demos[index]
            _activeDemo.value = demo
            demo.onEnter(display, camera, sensor)
        }
    }

    fun onTap() {
        viewModelScope.launch { _activeDemo.value?.onTap() }
    }
}
```

#### ContentProvider Replacement

Sony's `ContentProvider` served two purposes: capability discovery and extension registration. In KMP:

```kotlin
// commonMain — replace ContentProvider with DI container

// Koin module replaces ContentProvider capability queries
val glassesModule = module {
    // Device capabilities (was: query Device/Display/Sensor tables)
    single<DeviceCapabilities> {
        DeviceCapabilities(
            displayWidth = 419,
            displayHeight = 138,
            displayColors = 256,  // 8-bit grayscale
            hasTouchpad = true,
            hasCamera = true,
            cameraResolutions = listOf(
                Resolution.THREE_MP, Resolution.SXGA, Resolution.VGA, Resolution.QVGA
            ),
            sensors = listOf(SensorType.ACCELEROMETER, SensorType.GYROSCOPE,
                           SensorType.MAGNETOMETER, SensorType.LIGHT)
        )
    }

    // Transport — platform-specific injection
    single<PlatformTransport> { get() }  // provided by platform module

    // ViewModel — shared
    viewModel { GlassesViewModel(get()) }
}

// androidMain:
val androidTransportModule = module {
    single<PlatformTransport> { AndroidBluetoothTransport(androidContext()) }
}

// desktopMain:
val desktopTransportModule = module {
    single<PlatformTransport> { TcpTransport() }  // for emulator/ADB
}
```

#### Demo → ViewModel Mapping

Each Sony demo maps 1:1 to a shared ViewModel method or sub-state:

```kotlin
// shared/demo/Demo.kt
interface Demo {
    val name: String
    suspend fun onEnter(display: DisplayController, camera: CameraController,
                       sensor: SensorController)
    suspend fun onTap()
    suspend fun onSwipe(direction: SwipeDirection)
    suspend fun onExit()
}

// shared/demo/CameraStreamDemo.kt
class CameraStreamDemo : Demo {
    override val name = "Camera: Stream"
    private var streaming = false
    private var job: Job? = null

    override suspend fun onEnter(display: DisplayController,
                                camera: CameraController,
                                sensor: SensorController) {
        display.showStatus("Tap to start stream", "JPEG frames at high rate")
    }

    override suspend fun onTap() {
        if (!streaming) {
            streaming = true
            camera.startStream(
                quality = CameraQuality.STANDARD,
                resolution = CameraResolution.QVGA,
                mode = CameraMode.JPG_STREAM_HIGH_RATE
            )
        } else {
            streaming = false
            camera.stop()
        }
    }
}
```

---

### 2C: Rust + WebAssembly (Cross-Platform, Maximum Portability)

#### Crate Structure

```
smarteyeglass-rs/
├── crates/
│   ├── seg-protocol/              # Pure Rust, no platform deps, #![no_std] optional
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── frame.rs           # WireFrame parse/build
│   │   │   ├── handshake.rs       # Protocol state machine
│   │   │   ├── display.rs         # LayoutInit + PlaceRemove builders
│   │   │   ├── camera.rs          # Camera command builders + chunk accumulator
│   │   │   ├── sensor.rs          # Sensor data decoders
│   │   │   ├── wifi.rs            # WiFi negotiation (0x92-0x97)
│   │   │   ├── image.rs           # ARGB→8bit mono + DEFLATE
│   │   │   └── constants.rs       # All 0x** command IDs
│   │   └── Cargo.toml             # deps: flate2 (deflate), no async runtime
│   │
│   ├── seg-tokio/                  # Async runtime integration
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── transport.rs       # BT (btleplug) + TCP transport trait
│   │   │   ├── actor.rs           # Tokio actors via mpsc channels
│   │   │   ├── glasses.rs         # GlassesHandle: public API
│   │   │   └── demo.rs            # Demo trait + 8 implementations
│   │   └── Cargo.toml             # deps: tokio, btleplug, seg-protocol
│   │
│   ├── seg-wasm/                   # WASM target (browser control)
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   └── web_transport.rs   # WebSocket → TCP proxy adapter
│   │   └── Cargo.toml             # deps: wasm-bindgen, seg-protocol
│   │
│   └── seg-ffi/                    # C-ABI FFI for Swift/Kotlin callers
│       ├── src/lib.rs
│       ├── seg.h                   # Generated C header
│       └── Cargo.toml             # deps: seg-tokio, cbindgen
│
├── examples/
│   ├── cli-tool/                   # Replaces glasses-tool.swift
│   └── wasm-ui/                    # Browser demo app
│
└── Cargo.toml                      # workspace
```

#### Pure Protocol Crate (no platform deps)

```rust
// crates/seg-protocol/src/frame.rs

/// Wire frame: [cmdId:1B][len:2B][payload:varB]
#[derive(Debug, Clone)]
pub struct WireFrame {
    pub cmd_id: u8,
    pub payload: Vec<u8>,
}

impl WireFrame {
    /// Serialize to wire bytes.
    pub fn to_bytes(&self) -> Vec<u8> {
        let len = self.payload.len();
        let mut buf = Vec::with_capacity(3 + len);
        buf.push(self.cmd_id);
        buf.push((len >> 8) as u8);
        buf.push((len & 0xff) as u8);
        buf.extend_from_slice(&self.payload);
        buf
    }
}

/// Reassembly buffer — feeds raw bytes, yields complete frames.
pub struct FrameReassembler {
    buf: Vec<u8>,
}

impl FrameReassembler {
    pub fn new() -> Self {
        Self { buf: Vec::with_capacity(8192) }
    }

    /// Feed raw bytes from transport. Returns complete frames.
    pub fn feed(&mut self, data: &[u8]) -> Vec<WireFrame> {
        self.buf.extend_from_slice(data);
        let mut frames = Vec::new();
        loop {
            if self.buf.len() < 3 { break; }
            let len = ((self.buf[1] as usize) << 8) | (self.buf[2] as usize);
            let total = 3 + len;
            if self.buf.len() < total { break; }
            let frame = WireFrame {
                cmd_id: self.buf[0],
                payload: self.buf[3..total].to_vec(),
            };
            self.buf.drain(..total);
            frames.push(frame);
        }
        frames
    }
}
```

```rust
// crates/seg-protocol/src/display.rs

use flate2::write::DeflateEncoder;
use flate2::Compression;
use std::io::Write;

pub const DISPLAY_WIDTH: usize = 419;
pub const DISPLAY_HEIGHT: usize = 138;
pub const PIXEL_COUNT: usize = DISPLAY_WIDTH * DISPLAY_HEIGHT;

/// Convert ARGB pixel to 8-bit luma (Sony's formula).
pub fn argb_to_luma(r: u8, g: u8, b: u8, a: u8) -> u8 {
    let luma = (r as u32 * 299 + g as u32 * 587 + b as u32 * 114) / 1000;
    ((luma * a as u32) / 255) as u8
}

/// Build LayoutPlaceRemoveCommand (0xe7) from 8-bit grayscale pixels.
pub fn build_display_command(grayscale: &[u8; PIXEL_COUNT]) -> Vec<u8> {
    let compressed = deflate_compress(grayscale);

    // Sub1: PLACE_STATE
    let mut sub1 = vec![0x01, 0x00, 0x0a];
    sub1.extend_from_slice(&[0u8; 10]);

    // Sub2: PLACE_IMGOBJ (419×138 at 0,0)
    let mut sub2 = vec![0x03, 0x00, 0x18];
    sub2.extend_from_slice(&[0, 0, 0, 0]);      // objId, layerId
    sub2.extend_from_slice(&[0, 0, 0, 0]);      // x=0
    sub2.extend_from_slice(&[0, 0, 0, 0]);      // y=0
    sub2.extend_from_slice(&[0x01, 0xa3]);       // width=419
    sub2.extend_from_slice(&[0x00, 0x8a]);       // height=138
    sub2.extend_from_slice(&[0u8; 8]);           // flags

    // Sub3: IMG_DATA
    let img_len = 2 + 1 + compressed.len();
    let mut sub3 = vec![0x07, (img_len >> 8) as u8, (img_len & 0xff) as u8];
    sub3.extend_from_slice(&[0x00, 0x00]);       // objId=0
    sub3.push(0x01);                              // imgFormat=1 (8-bit + DEFLATE)
    sub3.extend_from_slice(&compressed);

    let total = sub1.len() + sub2.len() + sub3.len();
    let mut cmd = vec![0xe7, (total >> 8) as u8, (total & 0xff) as u8];
    cmd.extend(sub1);
    cmd.extend(sub2);
    cmd.extend(sub3);
    cmd
}

fn deflate_compress(input: &[u8]) -> Vec<u8> {
    let mut encoder = DeflateEncoder::new(Vec::new(), Compression::best());
    encoder.write_all(input).unwrap();
    encoder.finish().unwrap()
}
```

```rust
// crates/seg-protocol/src/handshake.rs

use crate::frame::WireFrame;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Phase {
    WaitProtocolVersion,
    WaitSettingsResponse,
    WaitVersionResponse,
    WaitFotaStatus,
    WaitOpenAppConfirm,
    Ready,
}

pub enum HandshakeAction {
    Send(WireFrame),
    InitDisplay,
    RouteToSubsystem(WireFrame),
    Ignore,
}

pub struct HandshakeStateMachine {
    phase: Phase,
}

impl HandshakeStateMachine {
    pub fn new() -> Self {
        Self { phase: Phase::WaitProtocolVersion }
    }

    pub fn phase(&self) -> Phase { self.phase }

    /// Pure function: given current state + incoming frame, returns action.
    /// No I/O — caller performs the action.
    pub fn handle(&mut self, frame: &WireFrame) -> HandshakeAction {
        match (self.phase, frame.cmd_id) {
            (Phase::WaitProtocolVersion, 0x0a) => {
                self.phase = Phase::WaitSettingsResponse;
                HandshakeAction::Send(WireFrame {
                    cmd_id: 0x71, payload: vec![]
                })
            }
            (Phase::WaitSettingsResponse, 0x72) => {
                self.phase = Phase::WaitVersionResponse;
                HandshakeAction::Send(WireFrame {
                    cmd_id: 0x07, payload: vec![0x01]
                })
            }
            (Phase::WaitVersionResponse, 0x08) => {
                self.phase = Phase::WaitFotaStatus;
                HandshakeAction::Send(WireFrame {
                    cmd_id: 0x85, payload: vec![0x00, 0x00, 0x00, 0x00]
                })
            }
            (Phase::WaitFotaStatus, 0x81) => {
                self.phase = Phase::WaitOpenAppConfirm;
                HandshakeAction::Send(WireFrame {
                    cmd_id: 0xff, payload: vec![]
                })
            }
            (Phase::WaitOpenAppConfirm, 0x31) |
            (Phase::WaitOpenAppConfirm, 0x06) => {
                self.phase = Phase::Ready;
                HandshakeAction::InitDisplay
            }
            (Phase::Ready, _) => {
                HandshakeAction::RouteToSubsystem(frame.clone())
            }
            _ => HandshakeAction::Ignore,
        }
    }
}
```

#### Tokio Actor Runtime

```rust
// crates/seg-tokio/src/actor.rs

use tokio::sync::mpsc;
use seg_protocol::frame::{WireFrame, FrameReassembler};

/// Transport trait — implemented per-platform
#[async_trait::async_trait]
pub trait Transport: Send + Sync + 'static {
    async fn connect(&mut self, address: &str) -> anyhow::Result<()>;
    async fn send(&self, bytes: &[u8]) -> anyhow::Result<()>;
    async fn recv(&self, buf: &mut [u8]) -> anyhow::Result<usize>;
}

/// Actor handles for message passing (replaces Intent system)
pub struct GlassesHandle {
    cmd_tx: mpsc::Sender<GlassesCommand>,
    event_rx: mpsc::Receiver<GlassesEvent>,
}

enum GlassesCommand {
    ShowBitmap([u8; 57822]),
    CameraStill { resolution: u8 },
    CameraStream { start: bool },
    SensorSubscribe { sensor_type: u8 },
    Tap,
    Swipe(SwipeDirection),
    Disconnect,
}

#[derive(Debug, Clone)]
pub enum GlassesEvent {
    PhaseChanged(Phase),
    TouchEvent { action: u8, x: u16, y: u16 },
    SensorData { accel: [f32; 3], gyro: [f32; 3], mag: [f32; 3] },
    CameraFrame(Vec<u8>),
    CameraDone { bytes: usize, path: String },
    WifiStatus { phase: u8, active: bool },
    DisplayAck,
    Error(String),
}

impl GlassesHandle {
    /// Spawn the glasses actor system. Returns a handle for commands + events.
    pub fn spawn(transport: Box<dyn Transport>) -> Self {
        let (cmd_tx, cmd_rx) = mpsc::channel(64);
        let (event_tx, event_rx) = mpsc::channel(256);

        tokio::spawn(glasses_actor_loop(transport, cmd_rx, event_tx));

        Self { cmd_tx, event_rx }
    }

    pub async fn show_bitmap(&self, pixels: [u8; 57822]) -> anyhow::Result<()> {
        self.cmd_tx.send(GlassesCommand::ShowBitmap(pixels)).await?;
        Ok(())
    }

    pub async fn next_event(&mut self) -> Option<GlassesEvent> {
        self.event_rx.recv().await
    }
}

async fn glasses_actor_loop(
    mut transport: Box<dyn Transport>,
    mut cmd_rx: mpsc::Receiver<GlassesCommand>,
    event_tx: mpsc::Sender<GlassesEvent>,
) {
    let mut hsm = HandshakeStateMachine::new();
    let mut reassembler = FrameReassembler::new();
    let mut camera_accum = CameraAccumulator::new();
    let mut buf = vec![0u8; 8192];

    loop {
        tokio::select! {
            // Receive from glasses
            Ok(n) = transport.recv(&mut buf) => {
                let frames = reassembler.feed(&buf[..n]);
                for frame in frames {
                    match hsm.handle(&frame) {
                        HandshakeAction::Send(resp) => {
                            let _ = transport.send(&resp.to_bytes()).await;
                        }
                        HandshakeAction::InitDisplay => {
                            // Send LayoutInit
                            let init = vec![0xe0,0,0x0a,0,0,0,0,0,0,0,0,0,0];
                            let _ = transport.send(&init).await;
                            let _ = event_tx.send(
                                GlassesEvent::PhaseChanged(Phase::Ready)
                            ).await;
                        }
                        HandshakeAction::RouteToSubsystem(f) => {
                            route_frame(&f, &transport, &event_tx,
                                       &mut camera_accum).await;
                        }
                        HandshakeAction::Ignore => {}
                    }
                }
            }
            // Receive commands from caller
            Some(cmd) = cmd_rx.recv() => {
                handle_command(cmd, &transport, &event_tx).await;
            }
        }
    }
}
```

#### WASM Target (Browser)

```rust
// crates/seg-wasm/src/lib.rs

use wasm_bindgen::prelude::*;
use seg_protocol::{
    frame::FrameReassembler,
    handshake::HandshakeStateMachine,
    display::build_display_command,
};

/// Browser-side glasses controller.
/// Communicates via WebSocket to a TCP proxy server.
#[wasm_bindgen]
pub struct GlassesController {
    hsm: HandshakeStateMachine,
    reassembler: FrameReassembler,
    ws: web_sys::WebSocket,
}

#[wasm_bindgen]
impl GlassesController {
    /// Create controller connected to WebSocket proxy.
    /// Proxy bridges: WebSocket ←→ TCP ←→ BT RFCOMM (or ADB forward)
    #[wasm_bindgen(constructor)]
    pub fn new(ws_url: &str) -> Result<GlassesController, JsValue> {
        let ws = web_sys::WebSocket::new(ws_url)?;
        ws.set_binary_type(web_sys::BinaryType::Arraybuffer);
        Ok(Self {
            hsm: HandshakeStateMachine::new(),
            reassembler: FrameReassembler::new(),
            ws,
        })
    }

    /// Feed raw bytes from WebSocket onmessage.
    pub fn on_data(&mut self, data: &[u8]) -> JsValue {
        let frames = self.reassembler.feed(data);
        let events = js_sys::Array::new();
        for frame in frames {
            match self.hsm.handle(&frame) {
                HandshakeAction::Send(resp) => {
                    let bytes = resp.to_bytes();
                    let _ = self.ws.send_with_u8_array(&bytes);
                }
                HandshakeAction::InitDisplay => {
                    let init = vec![0xe0,0,0x0a,0,0,0,0,0,0,0,0,0,0];
                    let _ = self.ws.send_with_u8_array(&init);
                    events.push(&JsValue::from_str("ready"));
                }
                _ => {}
            }
        }
        events.into()
    }

    /// Send a 419×138 grayscale bitmap to glasses.
    pub fn show_bitmap(&self, pixels: &[u8]) -> Result<(), JsValue> {
        if pixels.len() != 57822 {
            return Err(JsValue::from_str("Expected 57822 bytes"));
        }
        let mut arr = [0u8; 57822];
        arr.copy_from_slice(pixels);
        let cmd = build_display_command(&arr);
        self.ws.send_with_u8_array(&cmd)?;
        Ok(())
    }
}
```

#### FFI Bridge for Swift/Kotlin Callers

```rust
// crates/seg-ffi/src/lib.rs

use std::ffi::{c_char, CStr};
use seg_protocol::display::{build_display_command, PIXEL_COUNT};
use seg_protocol::frame::FrameReassembler;

/// Opaque handle for C callers.
pub struct SegHandle {
    reassembler: FrameReassembler,
}

#[no_mangle]
pub extern "C" fn seg_create() -> *mut SegHandle {
    Box::into_raw(Box::new(SegHandle {
        reassembler: FrameReassembler::new(),
    }))
}

#[no_mangle]
pub extern "C" fn seg_destroy(handle: *mut SegHandle) {
    if !handle.is_null() { unsafe { drop(Box::from_raw(handle)); } }
}

/// Build display command from 8-bit grayscale.
/// Returns malloc'd buffer. Caller must free with seg_free_buffer.
#[no_mangle]
pub extern "C" fn seg_build_display_cmd(
    pixels: *const u8,
    pixels_len: usize,
    out_len: *mut usize
) -> *mut u8 {
    if pixels_len != PIXEL_COUNT { return std::ptr::null_mut(); }
    let slice = unsafe { std::slice::from_raw_parts(pixels, pixels_len) };
    let mut arr = [0u8; PIXEL_COUNT];
    arr.copy_from_slice(slice);
    let cmd = build_display_command(&arr);
    unsafe { *out_len = cmd.len(); }
    let ptr = cmd.as_ptr() as *mut u8;
    std::mem::forget(cmd);  // caller frees
    ptr
}

#[no_mangle]
pub extern "C" fn seg_free_buffer(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        unsafe { Vec::from_raw_parts(ptr, len, len); }
    }
}
```

Swift caller (via generated `seg.h`):

```swift
// Use the Rust protocol library from Swift via FFI
import CSegProtocol  // bridging header from seg-ffi/seg.h

func buildDisplayCmd(grayscale: [UInt8]) -> Data {
    var outLen: Int = 0
    let ptr = grayscale.withUnsafeBufferPointer { buf in
        seg_build_display_cmd(buf.baseAddress, buf.count, &outLen)
    }
    guard let ptr else { return Data() }
    let data = Data(bytes: ptr, count: outLen)
    seg_free_buffer(ptr, outLen)
    return data
}
```

---

## Part 3: Demo Parity Matrix

| # | Demo | SDK API Calls | Wire Commands (TX→glasses) | Wire Events (RX←glasses) | Swift Actor API | Kotlin KMP API | Rust API |
|---|------|--------------|---------------------------|-------------------------|----------------|---------------|----------|
| 1 | **TextDemo** | `showBitmap(Bitmap)` | `0xe0` LayoutInit, `0xe7` PlaceRemove | `0xe5` tap, `0xe8` ImgAck | `display.showBitmap([UInt8])` | `display.showBitmap(ByteArray)` | `glasses.show_bitmap(&[u8; 57822])` |
| 2 | **AnimationDemo** | `showBitmap(Bitmap)` @15fps | `0xe7` PlaceRemove ×15/sec | `0xe8` ImgAck | `Task { loop { display.showBitmap(frame); sleep(66ms) } }` | `flow { while(true) { display.showBitmap(frame); delay(66) } }` | `loop { glasses.show_bitmap(&frame).await; sleep(66ms).await; }` |
| 3 | **GraphicsDemo** | `showBitmap(Bitmap)` | `0xe7` PlaceRemove (static or @15fps) | `0xe5` tap, `0xe8` ImgAck | Same as Animation for cube mode | Same as Animation for cube mode | Same as Animation for cube mode |
| 4 | **TouchDemo** | `showBitmap(Bitmap)` | `0xe7` PlaceRemove per event | `0xe5` LayoutEventNotify (press/release/longpress/swipe) | `for await event in protocol.touchEvents` | `protocol.touchEvents.collect { }` | `GlassesEvent::TouchEvent { action, x, y }` |
| 5 | **SensorDemo** | `sensorMgr.getSensor()`, `registerFixedRateListener()`, `showBitmap()` | `0x38` SensorStart (accel type + gyro type) | `0x3a` accel, `0xbc` gyro | `for await reading in sensor.readings` | `sensor.readings.collect { }` | `GlassesEvent::SensorData { accel, gyro, mag }` |
| 6 | **CameraCaptureDemo** | `setCameraMode(STILL)`, `requestCameraCapture()`, `stopCamera()`, `showBitmap()` | `0xce` SetMode, `0x38` SensorStart(cam), `0xb4` CaptureReq | `0xb5` CaptureResp, `0xb6` Data+`0xf1` ACK, `0xb7` Done | `camera.startStillCapture(); for await jpeg in camera.captures` | `camera.captureStill(); camera.lastCapture.collect {}` | `glasses.camera_still().await → GlassesEvent::CameraDone` |
| 7 | **CameraStreamDemo** | `setCameraMode(STREAM_HIGH)`, `startCamera()`, `stopCamera()`, `showBitmap()` | `0xce` SetMode(mode=3), `0xb4` CaptureReq (continuous) | `0xb5`/`0xb6`+`0xf1`/`0xb7` (repeating) | `camera.startStream(); for await jpeg in camera.captures` | `camera.startStream(); camera.frames.collect {}` | `glasses.camera_stream(true).await → stream of CameraFrame` |
| 8 | **ARDemo** | `setRenderMode(AR)`, `registerARObject(Cylindrical)`, `deleteARObject()`, `showBitmap()` | `0xc3` SetRenderMode(1), `0xe7` with AR object data | `0xe5` tap | `display.setRenderMode(.ar); display.registerARObject(...)` | `display.setRenderMode(AR); display.registerARObject(...)` | `glasses.set_render_mode(AR); glasses.register_ar_object(...)` |

### Wire Command Byte Reference (Quick Lookup)

| Cmd ID | Name | Direction | Used By Demos |
|--------|------|-----------|---------------|
| `0x05` | Ping/Heartbeat | Both | All (keepalive) |
| `0x06` | LevelNotification | RX | Handshake |
| `0x07`/`0x08` | VersionReq/Resp | TX/RX | Handshake |
| `0x0a` | ProtocolVersion | RX | Handshake |
| `0x30`/`0x31` | OpenAppStart Req/Resp | TX/RX | Handshake |
| `0x38` | SensorStart | TX | 5, 6, 7 |
| `0x3a` | AccelData | RX | 5 |
| `0x71`/`0x72` | SettingsStatus Req/Resp | TX/RX | Handshake |
| `0x81` | FotaStatus | RX | Handshake |
| `0x85` | NewHostApp | TX | Handshake |
| `0x91` | WifiStatusRes | RX | WiFi upgrade |
| `0x92`/`0x93` | WifiTurnOn/Off | TX | WiFi upgrade |
| `0x94` | WifiConnectReq | TX | WiFi upgrade |
| `0x95` | WifiConnectivityStatus | RX | WiFi upgrade |
| `0x96`/`0x97` | WifiDPSwitchPath Req/Res | Both | WiFi upgrade |
| `0xb4` | CameraCaptureReq | TX | 6, 7 |
| `0xb5` | CameraCaptureResp | RX | 6, 7 |
| `0xb6` | CameraCaptureData | RX | 6, 7 |
| `0xb7` | CameraCaptureDataDone | RX | 6, 7 |
| `0xb8` | CameraCaptureCancel | TX | 7 |
| `0xbb` | RotationVector | RX | 5 (if registered) |
| `0xbc` | GyroData | RX | 5 |
| `0xbd` | MagData | RX | 5 |
| `0xce` | CameraSetMode | TX | 6, 7 |
| `0xe0` | LayoutInit | TX | All (display init) |
| `0xe5` | LayoutEventNotify | RX | 4 (touch), all (tap) |
| `0xe7` | LayoutPlaceRemove | TX | All (frame push) |
| `0xe8` | ImageAck | RX | All (display confirm) |
| `0xe9` | DisplayTurnOn/Off | TX | All |
| `0xf1` | CaptureDataAck | TX | 6, 7 |
| `0xff` | SyncResponse | TX | Handshake |

---

## Part 4: "The Immutable Boundary"

### 4.1 What the Glasses Firmware Expects

The SED-E1 firmware is immutable — no OTA, no modification. Every implementation on every platform must produce **byte-identical wire protocol output** for the same logical operation.

#### Wire Frame Format

```
┌──────────┬──────────┬──────────────────────┐
│ cmdId    │  length  │  payload             │
│  1 byte  │  2 bytes │  0..65535 bytes      │
│          │  big-end │                      │
└──────────┴──────────┴──────────────────────┘

Examples:
  SettingsStatusReq: [0x71][0x00][0x00]           — 3 bytes, no payload
  VersionReq:        [0x07][0x00][0x01][0x01]     — 4 bytes, 1-byte payload
  WifiConnectReq:    [0x94][0x00][0xB8][184B]     — 187 bytes total
  LayoutPlaceRemove: [0xe7][HI][LO][sub1+sub2+sub3]  — variable
```

#### Image Encoding (exact specification)

```
Input:  419×138 pixels, 8-bit grayscale, row-major order
        Byte 0 = top-left pixel, byte 418 = end of row 0
        Total: 57,822 bytes uncompressed

Encoding: DEFLATE raw (zlib wbits=-15, no zlib/gzip header)
          Level: Z_BEST_COMPRESSION (9) — matching Sony's Java Deflater(level=9, nowrap=true)

Wire wrapping:
  Sub3 of 0xe7 command:
    [0x07]           — IMG_DATA subcommand
    [len_hi][len_lo] — length of (objId + fmt + compressed_data)
    [0x00][0x00]     — objId = 0
    [0x01]           — imgFormat = 1 (8-bit mono + DEFLATE)
    [compressed...]  — DEFLATE output bytes
```

#### Display Constraints

| Property | Value | Tolerance |
|----------|-------|-----------|
| Width | 419 pixels | Exact |
| Height | 138 pixels | Exact |
| Color depth | 8-bit grayscale | Values 0–255; firmware maps to green PWM |
| Pixel order | Row-major, top-left origin | Exact |
| Max frame rate (BT) | ~2.5 fps | Limited by RFCOMM MTU ~665B throughput |
| Max frame rate (WiFi) | ~30 fps | Limited by compressed frame size + TCP latency |
| Compression | DEFLATE raw (wbits=-15) | Must match Java Deflater(nowrap=true) |

### 4.2 Protocol State Machine (Required by Every Implementation)

```
                    ┌──────────────────────────┐
                    │  POWER ON / BT CONNECT   │
                    └──────────┬───────────────┘
                               │
                    ┌──────────▼───────────────┐
                    │ Phase 0: Wait for 0x0a   │ ← glasses send ProtocolVersion
                    │  (ProtocolVersion)        │    immediately after RFCOMM open
                    └──────────┬───────────────┘
                               │ RX 0x0a
                    ┌──────────▼───────────────┐
                    │ Phase 1: TX 0x71         │
                    │  SettingsStatusRequest    │ → wait for 0x72
                    └──────────┬───────────────┘
                               │ RX 0x72
                    ┌──────────▼───────────────┐
                    │ Phase 2: TX 0x07 [0x01]  │
                    │  VersionRequest           │ → wait for 0x08
                    └──────────┬───────────────┘
                               │ RX 0x08 (contains FW version string)
                    ┌──────────▼───────────────┐
                    │ Phase 3: TX 0x85 [0,0,0,0]│
                    │  NewHostApp               │ → wait for 0x81
                    │  (timeout: 5s → advance)  │
                    └──────────┬───────────────┘
                               │ RX 0x81 (FotaStatus)
                    ┌──────────▼───────────────┐
                    │ Phase 4: TX 0xff         │
                    │  SyncResponse             │
                    │  TX 0x30                  │
                    │  OpenAppStartRequest      │ → wait for 0x31 or 0x06
                    └──────────┬───────────────┘
                               │ RX 0x31 (OpenAppStartResponse)
                               │   or RX 0x06 (LevelNotification = tap)
                    ┌──────────▼───────────────┐
                    │ Phase 5: READY            │
                    │  TX 0xe0 (LayoutInit)     │
                    │  TX 0xe7 (first frame)    │
                    │  ← bidirectional comms →  │
                    └───────────────────────────┘
```

### 4.3 Camera State Machine

```
    ┌──────────────────────────────────────────┐
    │              CAMERA IDLE                 │
    └──────────┬───────────────────────────────┘
               │ TX 0xce SetMode(quality, resolution, mode)
               │ TX 0x38 SensorStart(sensorType=0x13)
               │ TX 0xb4 CaptureRequest
    ┌──────────▼───────────────────────────────┐
    │          WAITING FOR RESPONSE            │
    └──────────┬───────────────────────────────┘
               │ RX 0xb5 CaptureResponse (status, jpegSize)
               │   if status != 0 → ERROR → back to IDLE
    ┌──────────▼───────────────────────────────┐
    │          RECEIVING CHUNKS                │
    │  RX 0xb6 [seq][len_lo][len_hi][data...]  │
    │  → TX 0xf1 [0x00][0x01][seq] (ACK)       │  ← MUST ACK each chunk
    │  → accumulate JPEG bytes                  │
    │  repeat until:                            │
    └──────────┬───────────────────────────────┘
               │ RX 0xb7 CaptureDataDone (status, frameCount, totalSize)
    ┌──────────▼───────────────────────────────┐
    │          CAPTURE COMPLETE                │
    │  Accumulated bytes == expected from 0xb5  │
    │  → Save/process JPEG                      │
    │  → Back to IDLE (or loop for streaming)   │
    └──────────────────────────────────────────┘
```

**Critical timing constraints for camera:**

1. **ACK required per chunk** — if `0xf1` ACK is not sent for a `0xb6` chunk, the glasses will stall the stream. Next chunk will not be sent.
2. **Sequence numbers** — chunks arrive with incrementing sequence byte starting at 0. Duplicate/OOO chunks must be detected and dropped (but ACK'd anyway on WiFi).
3. **Mode must be set before capture** — `0xce` must precede `0xb4`. Setting mode resets the camera pipeline.
4. **Sensor start** — `0x38` with camera sensor type `0x13` must be sent after `0xce` to enable the camera sensor subsystem.

### 4.4 WiFi Upgrade State Machine

```
    BLUETOOTH ONLY (default)
        │
        │ TX 0x92 WifiTurnOnReq
        │ RX 0x91 status=ENABLED(3)
        │
        │ Host creates TCP ServerSocket (OS-assigned port)
        │ Host starts accept() in background
        │
        │ TX 0x94 WifiConnectReq (184-byte payload):
        │   [SSID:32B][passphrase:32B][reserved:32B]
        │   [goAddr:4B][staAddr:4B][subnetMask:4B]
        │   [dns:4B][gateway:4B]
        │   [channelMHz:2B][port:2B]  ← TCP server port
        │   [PSK_hex:64B]             ← PBKDF2-HMAC-SHA1(pass, ssid, 4096, 32)
        │
        │ RX 0x95 status=CONNECTED(3)
        │ Glasses TCP-connect to host_ip:port
        │ accept() returns client fd
        │
        │ TX 0x96 [0x01] WifiDPSwitchPathReq(WIFI)
        │ RX 0x97 [0x01] WifiDPSwitchPathRes(WIFI)
        │
    WIFI DATA PATH ACTIVE
        │ Camera and display frames now go over TCP
        │ BT remains for control/heartbeat
```

**WiFi constraints:**

1. **2.4GHz only** — glasses WiFi hardware is 802.11b/g/n 2.4GHz. 5GHz networks will not work.
2. **PSK derivation** — `PBKDF2-HMAC-SHA1(passphrase, SSID, 4096, 32)` → 64-char hex string. Must match exactly.
3. **TCP server** — host must be the server; glasses are the client. Port is communicated via `0x94` payload.
4. **Same network** — host and glasses must be on the same WiFi network (same SSID/AP).
5. **Separate reassembly buffer** — WiFi TCP stream has its own frame reassembly. Must NOT share buffer with BT RFCOMM.
6. **Channel ownership after switch** — after `0x97` confirms WiFi path, camera and display data use WiFi TCP. BT carries only control and heartbeat.

### 4.5 Heartbeat/Keepalive

- `0x05` (PING) sent by glasses periodically
- Host should respond to keep connection alive
- If no response within ~15 seconds, glasses may close BT connection
- Heartbeat continues on BT even when WiFi data path is active

### 4.6 What CANNOT Change

Regardless of platform choice, every implementation must:

1. **Speak the exact wire protocol** — byte-for-byte compatible `[cmdId][len][payload]` framing
2. **Complete the handshake in order** — skip a phase and the glasses stop responding
3. **Use raw DEFLATE** — not zlib, not gzip. `wbits=-15` / `nowrap=true`
4. **ACK camera chunks** — miss an ACK, stream stalls
5. **Respect transport boundaries** — WiFi TCP needs its own reassembly buffer
6. **Send LayoutInit before any frame** — `0xe0` must precede `0xe7`
7. **Target 419×138** — any other resolution is silently ignored or corrupts the display
8. **PSK derivation for WiFi** — wrong PSK → glasses fail to join network (silent failure)
9. **Be TCP server for WiFi** — glasses initiate the TCP connection, not the host
10. **Handle FotaStatus timeout** — some firmware versions skip `0x81`; implementation must advance after timeout (~5s)

---

## Part 5: "Recommended Path"

### Given: What We Have Today

| Asset | Status | Lines |
|-------|--------|-------|
| `glasses-tool.swift` | Working BT + WiFi + camera. Monolithic. | 2,080 |
| TypeScript TUI harness | Working event tail, state display | ~500 |
| pytest test suite | 18 tests, hardware-dependent + `--local` | ~300 |
| Protocol documentation | Wire format fully RE'd from DEX bytecode | Complete |
| Sony explorer app digest | All 8 demos fully analyzed | Complete |

### Phase 1: Refactor `glasses-tool.swift` into Actor Architecture

**Goal:** Same functionality, proper structure. No new features yet.

**Timeline guidance:** Medium complexity — foundational refactor.

**Steps:**

1. **Extract `TransportActor`** from the monolithic `cmdConnect()` closure.
   - Move `rxBuf` and `wifiRxBuf` into actor-isolated state
   - Move `sendCmd()` and `sendViaTCP()` into actor methods
   - This immediately fixes the BT+WiFi rxBuf collision at compile time

```swift
// Before (current): 2,080 lines in one file, rxBuf in closure scope
var rxBuf = Data()       // ← accessible from BT callback AND main RunLoop
var wifiRxBuf = Data()   // ← accessible from WiFi thread AND main dispatch

// After: actor isolation prevents cross-buffer access
actor TransportActor {
    private var btRxBuf = Data()     // only accessible via actor methods
    private var wifiRxBuf = Data()   // only accessible via actor methods
}
```

2. **Extract `ProtocolActor`** — pull the handshake state machine out of the 200-line `switch (initPhase, cmdId)`.
   - Make `initPhase` actor-private state
   - Each phase transition is an async actor method

3. **Extract `CameraActor`** — pull camera chunk accumulation out of `processRxData()`.
   - `cameraAccum`, `cameraExpectedBytes`, `cameraCapturing` become actor state
   - JPEG completion yields via `AsyncStream<Data>`

4. **Extract `DisplayActor`** — wrap `buildLayoutDisplayCmd()` + `deflateCompress()`.
   - Rate limiting can be added here later

5. **Keep the REPL** — `handleREPLCommand()` stays as the entry point, but calls `await` on actor methods instead of mutating closure state directly.

**File structure after Phase 1:**

```
macos-middleware/
├── Sources/
│   ├── TransportActor.swift      # BT + WiFi + Local mux/demux
│   ├── ProtocolActor.swift       # Handshake FSM + frame routing
│   ├── DisplayActor.swift        # LayoutInit + PlaceRemove + DEFLATE
│   ├── CameraActor.swift         # Chunk accumulation + JPEG output
│   ├── SensorActor.swift         # IMU data decoding + stream
│   ├── WireFrame.swift           # Shared types
│   ├── REPL.swift                # Interactive commands
│   └── Main.swift                # Entry point, CLI arg parsing
├── Package.swift                  # SPM package (replaces single-file swiftc)
└── glasses-tool.swift             # DEPRECATED — kept for reference
```

**Validation:** All 18 existing pytest tests must still pass. JSON event format unchanged.

### Phase 2: Extract Protocol Layer as Reusable Library

**Goal:** Pure protocol logic in a standalone Swift package (no IOBluetooth dependency).

**Steps:**

1. Create `SEGProtocol` Swift package with:
   - `FrameReassembler` (generic, no transport dependency)
   - `HandshakeStateMachine` (pure state machine, returns actions)
   - `DisplayCommandBuilder` (grayscale → DEFLATE → wire bytes)
   - `CameraAccumulator` (chunk → JPEG)
   - `SensorDecoder` (payload → typed readings)
   - `WireFrame` type definitions

2. This package has zero platform dependencies — works on macOS, iOS, Linux, embedded.

3. `glasses-tool` actors import this package for the protocol logic, provide transport.

```swift
// Package.swift
let package = Package(
    name: "SEGProtocol",
    products: [
        .library(name: "SEGProtocol", targets: ["SEGProtocol"]),
    ],
    dependencies: [],  // no external deps except zlib (system library)
    targets: [
        .target(name: "SEGProtocol"),
        .testTarget(name: "SEGProtocolTests", dependencies: ["SEGProtocol"]),
    ]
)
```

**Validation:** Protocol unit tests that run without any hardware or network — pure byte-in/byte-out.

### Phase 3: Build Demo Parity Apps

**Goal:** Implement all 8 demos from the Sony explorer app.

**Steps:**

1. Implement `GlassesDemo` protocol with the 8 demo classes (see Section 2A).

2. Build `DemoRunner` — equivalent to Sony's `ExplorerControl`:
   - Swipe-navigable menu rendered on glasses
   - Tap enters/exits active demo
   - Routes touch events to active demo

3. Each demo is a standalone, testable unit:
   - `TextDemo` — requires only `DisplayActor`
   - `AnimationDemo` — requires `DisplayActor` + timer
   - `GraphicsDemo` — requires `DisplayActor` + timer + 2D rendering
   - `TouchDemo` — requires `DisplayActor` + touch event stream
   - `SensorDemo` — requires `DisplayActor` + `SensorActor`
   - `CameraCaptureDemo` — requires `DisplayActor` + `CameraActor`
   - `CameraStreamDemo` — requires `DisplayActor` + `CameraActor`
   - `ARDemo` — requires `DisplayActor` + AR command support

4. Add headless 2D rendering (port the `font5x7` bitmap renderer and Canvas-like drawing to pure Swift without AppKit dependency).

**Priority order:**

| Priority | Demo | Why |
|----------|------|-----|
| 1 | TextDemo | Simplest. Validates display pipeline end-to-end. |
| 2 | AnimationDemo | Validates frame rate + timer loop. |
| 3 | TouchDemo | Validates input event routing. |
| 4 | CameraCaptureDemo | Validates camera protocol (already working in tool). |
| 5 | SensorDemo | Validates sensor data stream. |
| 6 | GraphicsDemo | Requires 2D rendering primitives (lines, circles, arcs). |
| 7 | CameraStreamDemo | Extension of CaptureDemo + continuous mode. |
| 8 | ARDemo | Most complex; requires AR render mode + object registration. |

### What to Defer

- **Kotlin Multiplatform port** — defer until Swift protocol library is stable. Then use the Rust FFI path or port protocol logic to KMP `commonMain`.
- **Rust rewrite** — defer unless targeting WASM/Linux/embedded. The protocol crate design (Part 2C) is the roadmap if needed.
- **SwiftUI host app** — defer. The headless actor architecture + REPL + pytest is the right dev loop. UI is a consumer, not a prerequisite.
- **iOS port** — defer until macOS actors are stable. CoreBluetooth replaces IOBluetooth; the protocol layer is identical.
- **AR demo** — lowest priority. AR render mode (`0xc3`) is the least-documented wire protocol area and requires IMU-based head tracking firmware support.

### Decision Framework: When to Cross-Platform

| Signal | Action |
|--------|--------|
| Need Android app talking to glasses | → Kotlin Multiplatform (share protocol layer) |
| Need browser control panel | → Rust + WASM (protocol crate → `seg-wasm`) |
| Need Linux/Windows CLI | → Rust (`seg-tokio` crate) |
| Need iOS app | → Swift (same actors, swap IOBluetooth → CoreBluetooth) |
| Need maximum code reuse | → Rust protocol crate with FFI to Swift/Kotlin |

The practical path is **Swift first** (we have working code), **extract protocol** (makes it portable), **cross-platform only when demanded** by a concrete use case.
