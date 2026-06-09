# Roadmap — Planned Features

## Priority 1: WiFi Camera Streaming

Camera streaming over BT is bandwidth-limited (1 frame max). WiFi TCP transport is required for continuous JPEG streaming at 7.5fps or 15fps.

**Blockers**: WiFi connect reliability (see STATUS.md). Glasses authenticate on some networks but not others.

**Plan**: 
1. Deep RE of WiFi connect flow from smali (exact WPA2 handshake)
2. Test with WiFi Direct mode (glasses as Group Owner) vs infrastructure mode
3. Verify PSK encoding: 64-char hex string vs raw 32 bytes
4. Once WiFi TCP connected: send `0x96 [0x01]` to switch data path, test camera stream

## Priority 2: AR Cylindrical Rendering

Full AR object system from the Java SDK. Approximately 800 lines of new code.

### Wire Protocol
| CMD | Name | Direction | Purpose |
|-----|------|-----------|---------|
| `0xc3` | SetRenderMode | TX | Switch between normal (0) and AR (1) mode |
| `0xc4` | RegisterARObject | TX | Register object with ID, bitmap, position, draw order |
| `0xc6` | ARBitmapRequest | RX | Glasses request bitmap for registered object |
| `0xc7` | ARBitmapResponse | TX | Send bitmap data back to glasses |
| `0xcd` | MoveARObject | TX | Update object position |

### Coordinate Systems

**Glasses coordinates** (`AR_COORDINATE_TYPE_GLASSES = 0`)
- Pixel positions: x ∈ [0, 419), y ∈ [0, 138)
- For static overlays pinned to display location

**Cylindrical coordinates** (`AR_COORDINATE_TYPE_CYLINDRICAL = 1`)
- `h` = compass heading in degrees: 0° = North, 90° = East, 180° = South, 270° = West
- `v` = elevation angle: positive = up, negative = down, range [-90°, +90°]
- Vertical range limit: `changeARCylindricalVerticalRange(max 60°)`
- Objects positioned in world space — move as user turns head

**World-to-cylindrical conversion** (from Java `SmartEyeglassControlUtils`):
```
azimuth = atan2(sin(Δlon) × cos(lat2),
                cos(lat1) × sin(lat2) - sin(lat1) × cos(lat2) × cos(Δlon))
elevation = atan2(altitude_diff, distance)
```

### Object Lifecycle
1. `setRenderMode(.ar)` → glasses switch to AR display mode
2. `registerARObject(id, bitmap, position, order)` → `0xc4` sent
3. Glasses respond with `onARRegistrationResult(result, objectId)`
4. Glasses request bitmap via `0xc6` → we respond with `0xc7`
5. `moveARObject(id, newPosition)` → updates position
6. `deleteARObject(id)` → removes object (id=0 = delete all)

### AR Object Types
- `STATIC_IMAGE (0)` — requested once via `onARObjectRequest`
- `ANIMATED_IMAGE (1)` — continuous frames via LocalSocket/TCP

### Result Codes
- `AR_RESULT_OK (0)`
- `AR_RESULT_ERROR_PARAMETER_ERROR (1)`
- `AR_RESULT_ERROR_MEMORY_SHORTAGE (2)`
- `AR_RESULT_ERROR_SYSTEM (3)`

## Priority 3: Sensor Recording & MCAP Export

Capture all sensor streams + camera into industry-standard [MCAP](https://mcap.dev/) files for offline analysis, replay, and integration with tools like Foxglove Studio.

### Streams to record
| Channel | Source | Format | Rate |
|---------|--------|--------|------|
| `/imu/accel` | Accelerometer (0x3a) | 3× float32 (x,y,z) m/s² | up to ~100Hz |
| `/imu/gyro` | Gyroscope (0xbc) | 3× float32 (x,y,z) rad/s | up to ~100Hz |
| `/imu/mag` | Magnetometer (0xbd) | 3× float32 (x,y,z) μT | up to ~100Hz |
| `/imu/rotation` | Rotation vector (0xbb) | 3-4× float32 | up to ~100Hz |
| `/sensor/light` | Ambient light (0x3b) | 1× float32 lux | ~10Hz |
| `/sensor/battery` | Battery (0x3e) | level % + timestamp | ~1Hz |
| `/camera/jpeg` | Camera capture/stream | JPEG frames | 7.5–15fps (theoretical) |
| `/input/events` | Touch, swipe, buttons | event type + timestamp | on-demand |
| `/display/frames` | Outgoing display bitmaps | 419×138 grayscale | on-demand |

### Camera video pipeline
- JPEG frames from camera stream → pipe through `ffmpeg` for:
  - H.264/H.265 MP4 recording
  - Real-time preview via named pipe
  - Frame rate measurement (actual vs theoretical 15fps limit)
- **Benchmark real FPS** — the 15fps limit is from the Java SDK constant `CAMERA_MODE_JPG_STREAM_HIGH_RATE`. Actual throughput over WiFi TCP may be higher or lower. Need to measure with timestamps on each `0xb6` frame.

### MCAP file format
- One `.mcap` file per recording session
- All channels time-synchronized via glasses timestamps
- Schema: Protobuf or JSON schema per channel
- Playback: Foxglove Studio, custom Python readers
- Goal: record 5-minute walks with full IMU + camera for SLAM/VIO research

## Priority 4: Sensor Completeness

| Feature | Detail |
|---------|--------|
| Fix rotation vector handler | `0xbb` currently calls `handleAccelerometer()` — data corruption |
| Battery ACK | Send `[0x01,0x00,0x00]` after `0x3e` (missing, all other sensors have it) |
| Accuracy tracking | Parse first 4 bytes of sensor payload as accuracy enum |
| Rate control | Rate byte in `0x38` SensorStart: fastest(1), game(2), normal(3), ui(4) |
| Sensor visualization | Real-time IMU display on glasses — react to head movement |
| Calibration | Magnetometer calibration dance (figure-8 motion detection) |

## Priority 5: Voice & Audio

The glasses have a microphone and speaker accessible via Bluetooth HFP (Hands-Free Profile) on RFCOMM channel 1.

### Push-to-Talk (PTT)
- Hardware PTT button sends `0x0b` (press) and `0x0c` (release) via `0xe5`
- Hold PTT → stream microphone audio over BT HFP channel
- Release PTT → stop recording
- Audio format: likely SCO 8kHz/16kHz PCM (standard HFP)

### Voice-to-Text
- Java SDK has `VOICE_TEXT_INPUT_ENABLE` / `VOICE_TEXT_INPUT_NOTIFY_RECOGNIZED_TEXT_EVENT`
- Sony's original flow: PTT → record → send audio to phone → phone does STT → result back to glasses
- Our flow: PTT → record via HFP SCO → pipe to Whisper/local STT → display result on glasses
- Result codes: `VOICE_TEXT_INPUT_RESULT_OK (0)`, `FAILED (1)`, `CANCEL (2)`

### Text-to-Speech (TTS)
- Reverse path: text → macOS `say` or system TTS → audio over HFP SCO → glasses speaker
- Could enable AI assistant responses audible through glasses

### Audio Recording
- Current `AudioDemo` uses `ffmpeg` to capture from system mic
- Need to route HFP SCO channel specifically (glasses mic, not Mac mic)
- BT HFP channel 1 confirmed present in SDP (`[7, 1, 7, 4]` — ch1 sends AT commands)
- Need to establish SCO link for actual audio data

### Integration Ideas
- PTT → Whisper STT → LLM → TTS → glasses speaker (full voice assistant loop)
- PTT → record → save as WAV alongside MCAP sensor data
- Live audio level meter displayed on glasses while recording

## Priority 6: Display Enhancements

| Feature | Wire Details |
|---------|-------------|
| Partial screen updates | x,y offset in 0x35/0xe7 header — update only changed region |
| Screen depth | -4 (far, ~10m) to 6 (near) — apparent display distance |
| Safe display mode | Renders only bottom half — less obstruction to field of view |
| Layer transitions | moveLowerLayer / moveUpperLayer — slide animations |
| Display callbacks | Transaction number in 0xe8 ACK — confirms which frame rendered |

## Priority 7: Input & Lifecycle

| Feature | Notes |
|---------|-------|
| Touch coordinates | `0xe5` payload contains x,y — currently not parsed |
| Double/triple tap | Tap count byte in payload |
| Pause/resume | displayOff → pause rendering, displayOn → resume |
| Screen state control | `0x3d` — on/off/dim/auto |

## Priority 8: Firmware Exploration

### DFU Mode
- `ENTER_DFU_MODE` command exists in the APK DEX
- Puts glasses into bootloader expecting firmware image
- **HIGH RISK** — could brick device if wrong firmware
- We have 4 devices to experiment with

### Initialize Function
- Glasses built-in menu has "Initialize" option
- Accessible when BT pairing fails → back button → navigate menu
- May be factory reset — needs testing

### NFC Quick Pairing
- URI format: `semc://liveware/B1/6/SmartEyeglass/AC:9B:0A:37:A6:XX/BAEf`
- Plan: scan NFC with iPhone → extract MAC → auto-connect via SEGKit
- Enables seamless first-time pairing UX
