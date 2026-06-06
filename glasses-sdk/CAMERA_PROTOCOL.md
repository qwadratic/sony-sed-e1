# Sony SED-E1 Camera Protocol

> Reverse-engineered from `com.sonyericsson.j2.commands.*` DEX bytecode, 2026-06-06.  
> Source: `com.sony.smarteyeglass_1.3.17052901-24_minAPI19.apk` — `classes.dex` (3.5 MB)  
> Method: Python DEX parser → Dalvik constructor disassembly → `Command.<init>(cmdByte)` extraction

---

## Architecture (our simplified two-layer model)

```
macOS glasses-tool.swift
    ↕  RFCOMM (BT) or TCP (WiFi)
Sony SED-E1 hardware
```

We own the full stack. No Android middleware. No Intent permissions. Camera is always allowed.

---

## Complete j2.commands CMD Byte Table

| Byte | Decimal | Class | Direction | Notes |
|------|---------|-------|-----------|-------|
| `0x01` | 1 | `Ack` | RX | Generic ACK |
| `0x02` | 2 | `Nak` | RX | Generic NAK |
| `0x05` | 5 | `Ping` | RX | Keep-alive |
| `0x06` | 6 | `LevelNotification` | RX | Ready signal |
| `0x07` | 7 | `VersionRequest` | TX | FW version query |
| `0x08` | 8 | `VersionResponse` | RX | FW version string |
| `0x0a` | 10 | `ProtocolVersion` | RX | First frame on connect |
| `0x30` | 48 | `OpenAppStartRequest` | TX | Start app session |
| `0x31` | 49 | `OpenAppStartResponse` | RX | Session confirmed |
| `0x33` | 51 | `OpenAppStopRequest` | TX | Stop request |
| `0x34` | 52 | `OpenAppStop` | RX | Stop confirmed |
| `0x35` | 53 | `OpenAppImage` | TX | Display grayscale image |
| `0x36` | 54 | `OpenAppImageAck` | RX | Image received ACK |
| `0x38` | 56 | `OpenAppSensorStart` | TX | Start sensor stream |
| `0x39` | 57 | `OpenAppSensorStop` | TX | Stop sensor stream |
| `0x3a` | 58 | `OpenAppAcceleration` | RX | Accelerometer data |
| `0x3b` | 59 | `OpenAppLightSensor` | RX | Ambient light data |
| `0x3d` | 61 | `OpenAppSetScreenstate` | TX | Screen on/off |
| `0x3e` | 62 | `OpenAppBatterySensor` | RX | Battery status |
| `0x71` | 113 | `SettingsStatusRequest` | TX | Phase 1 handshake |
| `0x72` | 114 | `SettingsStatusResponse` | RX | Phase 2 handshake |
| `0x85` | 133 | `NewHostApp` | TX | Register host app |
| `0x90` | 144 | `WifiStatusReq` | TX | Query WiFi state |
| `0x91` | 145 | `WifiStatusRes` | RX | WiFi state (0=DISABLING..3=ENABLED) |
| `0x92` | 146 | `WifiStatusTurnOnReq` | TX | Enable WiFi on glasses |
| `0x93` | 147 | `WifiStatusTurnOffReq` | TX | Disable WiFi on glasses |
| `0x94` | 148 | `WifiConnectReq` | TX | Connect glasses to AP |
| `0x95` | 149 | `WifiConnectivityStatus` | RX | AP connection state |
| `0x96` | 150 | `WifiDPSwitchPathReq` | BOTH | Switch data path |
| `0x97` | 151 | `WifiDPSwitchPathRes` | RX | Path switch confirmed |
| `0xb1` | 177 | `OpenAppClearScreen` | TX | Clear display |
| **`0xb4`** | **180** | **`OpenAppCameraCaptureRequest`** | **TX** | **Trigger capture** |
| **`0xb5`** | **181** | **`OpenAppCameraCaptureResponse`** | **RX** | **Capture metadata** |
| **`0xb6`** | **182** | **`OpenAppCameraCaptureData`** | **RX** | **JPEG data chunk** |
| **`0xb7`** | **183** | **`OpenAppCameraCaptureDataDone`** | **RX** | **Transfer complete** |
| **`0xb8`** | **184** | **`OpenAppCameraCaptureDataCancel`** | **TX** | **Cancel transfer** |
| `0xbb` | 187 | `OpenAppRotationVector` | RX | Rotation vector |
| `0xbc` | 188 | `OpenAppGyro` | RX | Gyroscope data |
| `0xbd` | 189 | `OpenAppMagnetometer` | RX | Magnetometer data |
| **`0xce`** | **206** | **`OpenAppCameraMode`** | **TX** | **Set camera params** |
| `0xcd` | 205 | `OpenAppShiftObject` | TX | Shift AR object |
| `0xc3` | 195 | `OpenAppMode` | TX | Set power/display mode |
| `0xe0` | 224 | `LayoutInit` | TX | Layout init |
| `0xe5` | 229 | `LayoutEventNotify` | RX | Layout event |
| **`0xf1`** | **241** | **`OpenAppCameraCaptureDataAck`** | **TX** | **ACK data chunk** |
| `0xff` | 255 | `LayoutPlaceImageData` | TX | Place image data |

---

## Frame Wire Format (all commands)

```
[cmdId: 1B] [length_hi: 1B] [length_lo: 1B] [payload: length bytes]
```

Total frame = 3 + payload_length bytes.

---

## Camera Capture Flow

### Step 1 — Set Camera Mode: `0xce` (OpenAppCameraMode)

TX payload: **4 bytes** `[mode, resolution, quality, fps]`

**mode** (capture mode):
| Value | Constant | Meaning |
|-------|----------|---------|
| `0x00` | `CAPTURE_MODE_STILL` | Still photo |
| `0x01` | `CAPTURE_MODE_MOVIE` | Video stream |

**resolution**:
| Value | Constant | Pixels |
|-------|----------|--------|
| `0x00` | `JPEG_RESOLUTION_3M` | 3 megapixel |
| `0x01` | `JPEG_RESOLUTION_SXGA` | 1.3MP (1280×1024) |
| `0x02` | `JPEG_RESOLUTION_XGA` | 1024×768 |
| `0x03` | `JPEG_RESOLUTION_SVGA` | 800×600 |
| `0x04` | `JPEG_RESOLUTION_VGA` | 640×480 |
| `0x05` | `JPEG_RESOLUTION_HVGA` | 480×320 |
| `0x06` | `JPEG_RESOLUTION_QVGA` | 320×240 |
| `0x07` | `JPEG_RESOLUTION_QQVGA` | 160×120 |

**quality**:
| Value | Constant |
|-------|----------|
| `0x01` | `JPEG_QUALITY_STANDARD` |
| `0x02` | `JPEG_QUALITY_FINE` |
| `0x03` | `JPEG_QUALITY_SUPERFINE` |

**fps** (movie mode only):
| Value | Constant |
|-------|----------|
| `0x00` | `MOVIE_FPS_15` |
| `0x01` | `MOVIE_FPS_10` |
| `0x02` | `MOVIE_FPS_7_5` |
| `0x03` | `MOVIE_FPS_5` |

**Still capture example:**
```
ce 00 04 00 01 01 00
           ^  ^  ^  ^
           |  |  |  fps=0 (N/A for still)
           |  |  quality=1 (STANDARD)
           |  resolution=1 (SXGA 1.3MP)
           mode=0 (STILL)
```

**QVGA streaming example:**
```
ce 00 04 01 06 01 00
           ^  ^  ^  ^
           |  |  |  fps=0 (15fps)
           |  |  quality=1 (STANDARD)
           |  resolution=6 (QVGA)
           mode=1 (MOVIE)
```

---

### Step 2 — Trigger Capture: `0xb4` (OpenAppCameraCaptureRequest)

TX: **no payload** (0 bytes)

```
b4 00 00
```

---

### Step 3 — Capture Metadata: `0xb5` (OpenAppCameraCaptureResponse)

RX payload: **10 bytes** `[status(1), format(1), jpeg_size(4 LE), field4(4 LE)]`

| Field | Size | Meaning |
|-------|------|---------|
| status | 1B | 0=success, non-zero=error |
| format | 1B | 0=JPEG |
| jpeg_size | 4B LE | Total JPEG bytes that will follow |
| field4 | 4B LE | Unknown (possibly offset or sequence id) |

On success (status=0): prepare a buffer of `jpeg_size` bytes, then receive 0xb6 frames.  
On error: abort.

---

### Step 4 — Data Chunks: `0xb6` (OpenAppCameraCaptureData)

RX payload: **variable** `[frame_num(1), data_len(2 LE), data(data_len bytes)]`

| Field | Size | Meaning |
|-------|------|---------|
| frame_num | 1B | Sequence number (0, 1, 2, …) |
| data_len | 2B LE | Bytes of JPEG data in this chunk |
| data | data_len B | Raw JPEG bytes |

After each 0xb6 frame, **immediately** send ACK (0xf1).

---

### Step 5 — Acknowledge Chunk: `0xf1` (OpenAppCameraCaptureDataAck)

TX payload: **1 byte** `[frame_num]`

```
f1 00 01 <frame_num>
```

Send after **every** received 0xb6. The frame_num echoes the received frame's sequence number.

---

### Step 6 — Transfer Complete: `0xb7` (OpenAppCameraCaptureDataDone)

RX payload: **6 bytes** `[status(1), count(1), total_size(4 LE)]`

| Field | Meaning |
|-------|---------|
| status | 0=success |
| count | Number of 0xb6 frames sent |
| total_size | Total JPEG bytes transferred |

On receipt: save accumulated bytes as JPEG file.

---

### Cancel: `0xb8` (OpenAppCameraCaptureDataCancel)

TX payload: **1 byte** (cancel reason, use 0)

```
b8 00 01 00
```

Send to abort an in-progress transfer.

---

## Full Sequence Diagram

```
Host                                    Glasses
  |                                        |
  |── 0xce [mode=0,res=1,qual=1,fps=0] ──▶|  Set camera params
  |── 0xb4 [] ─────────────────────────▶  |  Trigger capture
  |                                        |  (glasses takes photo)
  |◀─ 0xb5 [status=0, fmt=0, size=N] ─── |  Metadata: N bytes coming
  |◀─ 0xb6 [seq=0, len=X, data...] ─────  |  Chunk 0
  |── 0xf1 [seq=0] ───────────────────▶   |  ACK chunk 0
  |◀─ 0xb6 [seq=1, len=X, data...] ─────  |  Chunk 1
  |── 0xf1 [seq=1] ───────────────────▶   |  ACK chunk 1
  |  ....
  |◀─ 0xb7 [status=0, count=N, size=N] ─  |  Done
  |                                        |
  |  → save buffer as JPEG                 |
```

---

## Notes

- The SED-E1 camera is a 3MP fixed-focus unit; output is JPEG.
- WiFi path (30fps possible for streaming); BT path (~2fps max for stills).
- For still capture over BT, recommend QVGA or VGA resolution to keep transfer size manageable.
- The glasses display is 419×138 px monochrome — camera output is separate from display.
