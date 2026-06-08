# Sony SmartEyeglass Java SDK — Complete Reference Summary

> Auto-generated from 61K lines of Java source + 179 HTML Javadoc files + wire protocol RE docs.
> Source: `_dev/smarteyeglass-explorer/` (4 library projects) + `Sony/sony_smarteyeglass_sdk/docs/`
> Date: 2026-06-08

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Display Pipeline](#2-display-pipeline)
3. [Camera System](#3-camera-system)
4. [Sensor System](#4-sensor-system)
5. [AR Rendering System](#5-ar-rendering-system)
6. [Input Events](#6-input-events)
7. [Control Lifecycle](#7-control-lifecycle)
8. [WiFi / Power Modes / Telephony](#8-wifi--power-modes--telephony)
9. [Registration Flow](#9-registration-flow)
10. [Tunnel Protocol](#10-tunnel-protocol)
11. [All Intent Constants](#11-all-intent-constants)
12. [All Numeric Constants](#12-all-numeric-constants)
13. [Wire Protocol CMD Bytes](#13-wire-protocol-cmd-bytes)
14. [Key Implementation Insights from Comments](#14-key-implementation-insights-from-comments)
15. [AI Navigation Strategy](#15-ai-navigation-strategy)

---

## 1. Architecture Overview

The Sony SmartEyeglass SDK is a **4-layer stack** built on top of the generic Sony SmartExtension framework. Each layer has a distinct role:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Extension App  (com.explorer.*)                   │
│  Your app: demos, UI, business logic                        │
│  Key class: ExplorerControl extends ControlExtension        │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: SmartEyeglassAPI  (com.sony.smarteyeglass.*)      │
│  Eyeglass-specific: camera, AR, display utils, dialogs      │
│  Key classes: SmartEyeglassControlUtils,                    │
│               SmartEyeglassEventListener,                   │
│               SmartEyeglassControl.Intents,                 │
│               ar/CylindricalRenderObject,                   │
│               ar/GlassesRenderObject                        │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: SmartExtensionUtils  (com.sonyericsson...util.*)  │
│  Generic accessory utilities: ControlExtension,             │
│  ExtensionService, sensor managers, registration helpers,   │
│  widget framework                                           │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: SmartExtensionAPI  (com.sonyericsson...aef.*)     │
│  Pure constants & intent definitions:                       │
│  Control.java, Sensor.java, Registration.java,              │
│  Tunnel.java, Widget.java, Notification.java                │
│  NO LOGIC — only static final String/int constants          │
└─────────────────────────────────────────────────────────────┘
         ↕ Android Intents / BroadcastReceiver
┌─────────────────────────────────────────────────────────────┐
│  HostApp  (com.sony.smarteyeglass — the APK on phone)       │
│  Translates intents → wire protocol bytes → BT/WiFi         │
│  THIS IS THE PIECE WE REPLACE WITH SEGKit                   │
└─────────────────────────────────────────────────────────────┘
         ↕ RFCOMM / WiFi P2P TCP
┌─────────────────────────────────────────────────────────────┐
│  SED-E1 Hardware  (immutable firmware)                      │
└─────────────────────────────────────────────────────────────┘
```

### SDK/Extension Boundary Rule

**Extension apps NEVER see wire protocol bytes.** They speak only Android Intents.
The HostApp (com.sony.smarteyeglass) is the sole translator between Intent-world and wire-protocol-world.

In our Swift reimplementation:
- **SEGKit** = HostApp equivalent (owns wire protocol, DEFLATE, transport)
- **SEGExplorer** = Extension app equivalent (uses only public SEGKit API)

### File Counts by Project

| Project | Java Files | Lines | Role |
|---------|-----------|-------|------|
| SmartExtensionAPI | 12 | ~8,500 | Pure constants (Layer 1) |
| SmartExtensionUtils | 36 | ~12,000 | Generic utilities (Layer 2) |
| SmartEyeglassAPI | 14 | ~4,800 | Eyeglass-specific API (Layer 3) |
| Explorer App | 15 | ~1,800 | Demo extension (Layer 4) |
| **Total** | **77** | **~27,100** | |

---

## 2. Display Pipeline

### Display Specifications

| Property | Value |
|----------|-------|
| Width | **419 px** |
| Height | **138 px** |
| Max pixels per frame | **57,822** (419 × 138) |
| Color depth | **8-bit monochrome** (grayscale) |
| Widget width | 380 px |
| Widget height | 60 px |
| Text sizes | 18px (small), 20px (normal), 40px (large) |
| API version | 3 |

### Image Encoding: `EightBitMonochromeImageEncoder`

This is a **critical inner class** in `SmartEyeglassControlUtils` that converts Android Bitmaps to the wire format:

```java
// Luma-corrected monochrome conversion (from source comments)
// Input: ARGB_8888 or RGB_565 bitmap
// Output: byte[] where each byte = one pixel's luminance (0-255)
// Formula: value = (R*299 + G*587 + B*114) / 1000  (ITU-R BT.601 luma)
// Alpha pre-multiplication: value = (value * alpha) / 255

byte[] buffer = EightBitMonochromeImageEncoder.convert(bitmap, rowOffset, rowCount);
```

**Key insight**: The raw format flag `EXTRA_DATA_IS_RAW_FORMAT = 1` tells the HostApp the data is already in 8-bit-per-pixel grayscale format, NOT a standard image format. This is what gets DEFLATE-compressed and sent over the wire as `0x35` (OpenAppImage).

### Display Methods (SmartEyeglassControlUtils)

| Method | Description | Notes |
|--------|-------------|-------|
| `showBitmap(Bitmap)` | Full-screen bitmap | Converts via EightBitMonochromeImageEncoder |
| `showBitmap(Bitmap, x, y)` | Partial screen update | Upper-left corner at (x,y) |
| `showBitmapWithCallback(Bitmap, txn)` | Full screen + completion callback | Returns via `onResultShowBitmap` |
| `showBitmapWithCallback(Bitmap, x, y, txn)` | Partial + callback | |
| `showImage(resourceId)` | From Android resource | Decodes then converts |
| `showImageWithCallback(resourceId, txn)` | Resource + callback | Returns via `onResultShowImage` |
| `moveLowerLayer(Bitmap)` | Transition animation (down) | Layer transition effect |
| `moveUpperLayer(Bitmap)` | Transition animation (up) | Layer transition effect |
| `moveLowerLayer(layoutId, layoutData)` | Layout + transition | |
| `moveUpperLayer(layoutId, layoutData)` | Layout + transition | |

### Display Data Intent Flow

```
Extension calls showBitmap(bitmap)
  → EightBitMonochromeImageEncoder.convert(bitmap) → byte[] (419×138 bytes)
  → Intent(CONTROL_DISPLAY_DATA_INTENT)
    EXTRA_DATA = byte[]
    EXTRA_IMAGE_WIDTH = 419
    EXTRA_IMAGE_HEIGHT = 138
    EXTRA_DATA_IS_RAW_FORMAT = 1
    [optional] EXTRA_X_OFFSET, EXTRA_Y_OFFSET for partial updates
  → sendToHostApp(intent)
  → HostApp compresses + sends 0x35 frame to glasses
```

### Display Data Result (Async Callback)

When using `WithCallback` variants:
```
HostApp → CONTROL_DISPLAY_DATA_RESULT_INTENT
  EXTRA_DISPLAY_DATA_TRANSACTION_NUMBER = txn
  EXTRA_DISPLAY_DATA_RESULT = DISPLAY_DATA_RESULT_OK (0) or DISPLAY_DATA_RESULT_CANNOT_DRAW (1)
  EXTRA_DISPLAY_DATA_TYPE = DISPLAY_DATA_TYPE_SHOW_BITMAP (0) or DISPLAY_DATA_TYPE_SHOW_IMAGE (1)
```

### Safe Display Mode

Limits rendering to the **bottom half** of the display to minimize interference with the user's field of view:
- `enableSafeDisplayMode()` → SAFE_DISPLAY_MODE_1
- `disableSafeDisplayMode()` → SAFE_DISPLAY_MODE_NONE

### Screen Depth

Controls the apparent distance of the display plane from the user's eyes:
- Range: **-4 to 6**
- Default (0): approximately 5 meters
- 6: nearest
- -4: approximately 10 meters or more
- `setScreenDepth(depth)`

---

## 3. Camera System

### Camera Modes

| Mode | Value | Description | Trigger |
|------|-------|-------------|---------|
| `CAMERA_MODE_STILL` | 0 | Still to socket | `requestCameraCapture()` |
| `CAMERA_MODE_STILL_TO_FILE` | 1 | Still to file URI | `requestCameraCapture()` |
| `CAMERA_MODE_JPG_STREAM_LOW_RATE` | 2 | JPEG stream at 7.5fps | Auto on `startCamera()` |
| `CAMERA_MODE_JPG_STREAM_HIGH_RATE` | 3 | JPEG stream at 15fps | Auto on `startCamera()` |

### Camera Resolution

| Constant | Value | Resolution |
|----------|-------|-----------|
| `CAMERA_RESOLUTION_3M` | 0 | 3 Megapixel |
| `CAMERA_RESOLUTION_1M` | 1 | 1.3 MP (1280×1024) |
| `CAMERA_RESOLUTION_VGA` | 4 | 640×480 |
| `CAMERA_RESOLUTION_QVGA` | 6 | 320×240 |

**Critical constraint from comments**: JPEG streaming modes (`JPG_STREAM_LOW_RATE`, `JPG_STREAM_HIGH_RATE`) support **only QVGA** resolution. Still modes support all resolutions.

### JPEG Quality

| Constant | Value |
|----------|-------|
| `CAMERA_JPEG_QUALITY_STANDARD` | 1 |
| `CAMERA_JPEG_QUALITY_FINE` | 2 |
| `CAMERA_JPEG_QUALITY_SUPER_FINE` | 3 |

### Camera API Flow

```java
// 1. Configure camera mode
utils.setCameraMode(CAMERA_JPEG_QUALITY_FINE, CAMERA_RESOLUTION_QVGA, CAMERA_MODE_STILL);

// 2. Start camera (opens LocalSocket for data)
utils.startCamera();  // or startCamera(filePath) for STILL_TO_FILE

// 3. Trigger capture (still modes only)
utils.requestCameraCapture();

// 4. Receive data via SmartEyeglassEventListener
//    onCameraReceived(CameraEvent event) — for socket modes
//    onCameraReceivedFile(String filePath) — for STILL_TO_FILE

// 5. Stop camera
utils.stopCamera();
```

### CameraEvent Data Format (Socket Protocol)

The HostApp sends camera data over a `LocalSocket` with this format:

```
[totalLength: 4B int] [frameId: 4B int] [timestamp: 8B long] [dataSize: 4B int] [data: dataSize bytes]
```

If `dataSize == 0`, then instead of `data`:
```
[status: 4B int]  // error status (0 = success, non-zero = error)
```

### Camera Permissions

Requires `com.sony.smarteyeglass.permission.CAMERA` in AndroidManifest.

### Camera Error Codes

| Constant | Value | Description |
|----------|-------|-------------|
| `ERROR_INVALID_PARAMETER` | -1 | Invalid camera parameter |
| `ERROR_FILE_ACCESS` | -2 | File path invalid/inaccessible |
| `ERROR_CAPTURE` | -3 | Capture operation failed |

---

## 4. Sensor System

### Sensor Types

| Type String | Constant | Data Format | Unit |
|-------------|----------|-------------|------|
| `"Accelerometer"` | `SensorTypeValue.ACCELEROMETER` | 3 floats (x, y, z) | m/s² |
| `"Light"` | `SensorTypeValue.LIGHT` | 1 float | SI lux |
| `"MagneticField"` | `SensorTypeValue.MAGNETIC_FIELD` | 3 floats (x, y, z) | μT |
| `"RotationVector"` | `SensorTypeValue.ROTATION_VECTOR` | 3-4 floats | unitless |
| `"Gyroscope"` | `SensorTypeValue.GYROSCOPE` | 3 floats (x, y, z) | rad/s |

**Note**: MagneticField and RotationVector were added in API v2.0, Gyroscope in v6.0.

### Wire Protocol Sensor IDs (from smali RE)

These are the **actual byte values** sent in `0x38` (SensorStart) commands:

| Wire ID | Sensor | Wire CMD (RX) |
|---------|--------|---------------|
| `0x03` | Battery | `0x3e` |
| `0x0d` | Gyroscope | `0xbc` |
| `0x0e` | Magnetometer | `0xbd` |
| `0x10` | Light | `0x3b` |
| — | Accelerometer | `0x3a` |
| — | Rotation Vector | `0xbb` |

### Sensor Data Wire Format (LocalSocket)

```
Byte  0-3:   Total length of data package (int, big-endian)
Byte  4-7:   Accuracy (int, see SensorAccuracy constants)
Byte  8-15:  Timestamp in nanoseconds since epoch (long)
Byte 16-19:  Length of sensor values in bytes (int)
Byte 20-nn:  Sensor values as float array (each float = 4 bytes)
```

**Comment insight**: "The data format is identical to a standard Android SensorEvent."

### Sensor Rates

| Constant | Value | Description |
|----------|-------|-------------|
| `SENSOR_DELAY_FASTEST` | 1 | As fast as possible |
| `SENSOR_DELAY_GAME` | 2 | Suitable for games |
| `SENSOR_DELAY_NORMAL` | 3 | Suitable for orientation changes |
| `SENSOR_DELAY_UI` | 4 | Suitable for UI updates |

### Sensor Accuracy

| Constant | Value | Description |
|----------|-------|-------------|
| `SENSOR_STATUS_UNRELIABLE` | 0 | Cannot be trusted |
| `SENSOR_STATUS_ACCURACY_LOW` | 1 | Low accuracy |
| `SENSOR_STATUS_ACCURACY_MEDIUM` | 2 | Average accuracy |
| `SENSOR_STATUS_ACCURACY_HIGH` | 3 | Maximum accuracy |

### Sensor Interrupt Mode

| Constant | Value | Description |
|----------|-------|-------------|
| `SENSOR_INTERRUPT_DISABLED` | 0 | Continuous data streaming |
| `SENSOR_INTERRUPT_ENABLED` | 1 | Only on new data available |

### Sensor Registration Flow

```
Extension:
  1. Create LocalServerSocket (one per sensor)
  2. Send SENSOR_REGISTER_LISTENER_INTENT with:
     - EXTRA_SENSOR_ID = sensor database ID
     - EXTRA_SENSOR_LOCAL_SERVER_SOCKET_NAME = socket name
     - EXTRA_SENSOR_REQUESTED_RATE = SENSOR_DELAY_*
     - EXTRA_SENSOR_INTERRUPT_MODE = 0 or 1
  3. HostApp connects to the LocalServerSocket
  4. HostApp streams sensor data over the socket connection
  5. To stop: send SENSOR_UNREGISTER_LISTENER_INTENT
```

### Sensor ACK Requirement (from smali RE)

**Critical finding**: The glasses stop sending IMU data without `[0x01, 0x00, 0x00]` ACK after each sensor frame. This is NOT documented in the SDK — discovered from decompiled smali bytecode.

---

## 5. AR Rendering System

### Rendering Modes

| Mode | Value | Description |
|------|-------|-------------|
| `MODE_NORMAL` | 0 | Standard full-screen/partial rendering |
| `MODE_AR` | 1 | AR mode with registered objects at world positions |

Switch with: `utils.setRenderMode(MODE_AR)` → sends `0xc3` on wire

### Coordinate Systems

| Type | Value | Description |
|------|-------|-------------|
| `AR_COORDINATE_TYPE_GLASSES` | 0 | Pixel coordinates (0,0)-(419,138) on display |
| `AR_COORDINATE_TYPE_CYLINDRICAL` | 1 | Compass degrees (0-360) + vertical angle (-90 to +90) |

### AR Object Types

| Type | Value | Description |
|------|-------|-------------|
| `AR_OBJECT_TYPE_STATIC_IMAGE` | 0 | Static image, requested once via `onARObjectRequest` |
| `AR_OBJECT_TYPE_ANIMATED_IMAGE` | 1 | Animated image, data sent via LocalSocket |

### RenderObject Hierarchy

```
RenderObject (abstract)
├── GlassesRenderObject      — pixel coordinates (x, y integers)
└── CylindricalRenderObject  — compass coordinates (h degrees, v degrees)
```

### CylindricalRenderObject Position

- **h** (horizontal): Compass heading in degrees. 0.0 = North, 90.0 = East, 180.0 = South, 270.0 = West
- **v** (vertical): Elevation angle. Positive = up, negative = down. Range -90.0 to +90.0.
- Vertical range can be limited with `changeARCylindricalVerticalRange(float range)` — max 60 degrees

### AR Object Lifecycle

```
1. setRenderMode(MODE_AR)                      // Switch to AR mode
2. registerARObject(renderObject)              // Register object with ID, bitmap, position, order
   → async → onARRegistrationResult(result, objectId)
3. HostApp sends onARObjectRequest(objectId)   // Requests bitmap data
4. sendARObjectResponse(object, result)        // Send bitmap back
   OR sendARAnimationObject(objectId, bitmap)  // For animated objects
5. moveARObject(object)                        // Update position
6. changeARObjectOrder(object)                 // Change z-order
7. deleteARObject(object)                      // Remove object (objectId=0 deletes ALL)
```

### AR Animation via LocalSocket

For animated objects, a separate LocalSocket channel is used:

```
// Animation socket data format (from source):
[objectId: 4B int] [transactionNumber: 4B int] [imageLength: 4B int] [PNG_data: imageLength bytes]
```

The animation is enabled/disabled with:
- `enableARAnimationRequest()` → HostApp responds with socket name → auto-connect
- `disableARAnimationRequest()` → close socket

### AR Result Codes

| Constant | Value | Description |
|----------|-------|-------------|
| `AR_RESULT_OK` | 0 | Success |
| `AR_RESULT_ERROR_PARAMETER_ERROR` | 1 | Bad parameters |
| `AR_RESULT_ERROR_MEMORY_SHORTAGE` | 2 | Out of memory on glasses |
| `AR_RESULT_ERROR_SYSTEM` | 3 | System error |

### World-to-Cylindrical Coordinate Conversion

`SmartEyeglassControlUtils` includes a utility for converting GPS coordinates to cylindrical AR coordinates:

```java
PointF cylindrical = SmartEyeglassControlUtils.convertCoordinateSystemFromWorldToCylindrical(
    viewingLocation,    // PointInWorldCoordinate (lat, lon, alt)
    targetLocation      // PointInWorldCoordinate (lat, lon, alt)
);
// cylindrical.x = compass heading in degrees (azimuth)
// cylindrical.y = elevation angle in degrees
```

The azimuth calculation uses the standard bearing formula with `atan2`.

### AR Wire Protocol Commands (from RE)

| CMD | Name | Direction | Description |
|-----|------|-----------|-------------|
| `0xc3` | OpenAppMode | TX | Set rendering mode (normal/AR) |
| `0xc4` | — | TX | Register AR object |
| `0xc6` | — | RX | Bitmap request from glasses |
| `0xc7` | — | TX | Bitmap response to glasses |
| `0xcd` | OpenAppShiftObject | TX | Move/shift AR object position |

---

## 6. Input Events

### Key Codes (Control.KeyCodes)

| Constant | Value | Physical Button |
|----------|-------|-----------------|
| `KEYCODE_PLAY` | 1 | Play button |
| `KEYCODE_NEXT` | 2 | Next button |
| `KEYCODE_PREVIOUS` | 3 | Previous button |
| `KEYCODE_ACTION` | 4 | Action button |
| `KEYCODE_VOLUME_DOWN` | 5 | Volume down |
| `KEYCODE_VOLUME_UP` | 6 | Volume up |
| `KEYCODE_BACK` | 7 | Back button |
| `KEYCODE_OPTIONS` | 8 | Options/menu button |
| `KEYCODE_PTT` | 9 | Push-to-talk button (API v4+) |
| `KEYCODE_CAMERA` | 10 | Camera button (API v4+) |

### Key Actions

| Constant | Value | Description |
|----------|-------|-------------|
| `KEY_ACTION_PRESS` | 0 | Key pressed down |
| `KEY_ACTION_RELEASE` | 1 | Key released |
| `KEY_ACTION_REPEAT` | 2 | Key held (repeat event) |

### Touch Events

| Constant | Value | Description |
|----------|-------|-------------|
| `TOUCH_ACTION_PRESS` | 0 | Touch press |
| `TOUCH_ACTION_LONGPRESS` | 1 | Long press |
| `TOUCH_ACTION_RELEASE` | 2 | Touch release |

Touch events carry `EXTRA_X_POS` and `EXTRA_Y_POS` coordinates.

### Swipe Directions

| Constant | Value | Description |
|----------|-------|-------------|
| `SWIPE_DIRECTION_UP` | 0 | Swipe up |
| `SWIPE_DIRECTION_DOWN` | 1 | Swipe down |
| `SWIPE_DIRECTION_LEFT` | 2 | Swipe left |
| `SWIPE_DIRECTION_RIGHT` | 3 | Swipe right |

### Tap Actions (API v3+)

| Constant | Value | Description |
|----------|-------|-------------|
| `SINGLE_TAP` | 0 | Single tap |
| `DOUBLE_TAP` | 1 | Double tap |
| `TRIPLE_TAP` | 2 | Triple tap |

### SmartEyeglass Controller Input Summary

The SmartEyeglass controller has:
- **Touchpad**: generates touch events (press/longpress/release with x,y), swipe events (up/down/left/right), and tap events (single/double/triple)
- **Back button**: KEYCODE_BACK (7)
- **Camera button**: KEYCODE_CAMERA (10)
- **PTT button**: KEYCODE_PTT (9) — push-to-talk for voice input
- **Jog wheel**: Generates KEYCODE_NEXT (2) / KEYCODE_PREVIOUS (3) on rotation — clockwise/counterclockwise

### Input Event Intent Flow

```
User presses Back → Glasses send wire event
  → HostApp → CONTROL_KEY_EVENT_INTENT
    EXTRA_KEY_ACTION = KEY_ACTION_PRESS (0)
    EXTRA_KEY_CODE = KEYCODE_BACK (7)
    EXTRA_TIMESTAMP = <time>

User swipes left on touchpad → Glasses send wire event
  → HostApp → CONTROL_SWIPE_EVENT_INTENT
    EXTRA_SWIPE_DIRECTION = SWIPE_DIRECTION_LEFT (2)

User taps touchpad → Glasses send wire event
  → HostApp → CONTROL_TAP_EVENT_INTENT
    EXTRA_TAP_ACTION = SINGLE_TAP (0)
```

---

## 7. Control Lifecycle

### State Machine

```
                ┌──────────┐
                │ CREATED  │
                └─────┬────┘
    START_REQUEST     │     START (from HostApp)
                      ▼
                ┌──────────┐
                │ STARTED  │
                └─────┬────┘
                      │     RESUME
                      ▼
                ┌──────────┐
    ◄─── PAUSE ─│FOREGROUND│─ PAUSE ───►
                └─────┬────┘
                      │     STOP
                      ▼
                ┌──────────┐
                │ STOPPED  │
                └──────────┘
```

### Lifecycle Intents

| Intent | Direction | Description |
|--------|-----------|-------------|
| `CONTROL_START_REQUEST` | App→Host | Request to take control |
| `CONTROL_START` | Host→App | Control granted |
| `CONTROL_RESUME` | Host→App | Extension visible on display |
| `CONTROL_PAUSE` | Host→App | Extension hidden/display off |
| `CONTROL_STOP` | Host→App | Control revoked |
| `CONTROL_STOP_REQUEST` | App→Host | Extension wants to stop |
| `CONTROL_ERROR` | Host→App | Error occurred |

### Error Codes (from CONTROL_ERROR)

| Value | Description |
|-------|-------------|
| 0 | Registration information missing |
| 1 | Accessory not connected |
| 2 | Host Application busy |

### Key Comment Insights

> "Since an extension implementing this API takes complete control over the accessory, only one extension can run at a time."

> "When possible, let the Host Application take control of the display state. The accessory has a much smaller battery than the phone."

> "When the extension is in a paused state, it no longer has control over the display/LEDs/vibrator/key events."

---

## 8. WiFi / Power Modes / Telephony

### Power Modes

| Mode | Value | Transport | Description |
|------|-------|-----------|-------------|
| `POWER_MODE_NORMAL` | 1 | Bluetooth only | Default, lower power |
| `POWER_MODE_HIGH` | 0 | WiFi + Bluetooth | Higher bandwidth |

**Key comment**: "Power mode constant value for normal bandwidth (Bluetooth is used). This value is used by default when starting an app."

WiFi is automatically engaged when `POWER_MODE_HIGH` is set. BT remains connected for control/sensor data even in WiFi mode.

### WiFi Wire Protocol

| CMD | Name | Direction | Description |
|-----|------|-----------|-------------|
| `0x90` | WifiStatusReq | TX | Query WiFi state |
| `0x91` | WifiStatusRes | RX | WiFi state response |
| `0x92` | WifiStatusTurnOnReq | TX | Enable WiFi |
| `0x93` | WifiStatusTurnOffReq | TX | Disable WiFi |
| `0x94` | WifiConnectReq | TX | Connect to AP |
| `0x95` | WifiConnectivityStatus | RX | Connection state |
| `0x96` | WifiDPSwitchPathReq | BOTH | Switch data path BT↔WiFi |
| `0x97` | WifiDPSwitchPathRes | RX | Path switch confirmed |

### WiFi States (from WifiStatusRes)

| Value | State |
|-------|-------|
| 0 | DISABLING |
| 1 | DISABLED |
| 2 | ENABLING |
| 3 | ENABLED |

### WiFi P2P Architecture

The glasses act as WiFi Direct **Group Owner** (GO). The passphrase is derived via PBKDF2-HMAC-SHA1 from a device secret. SSID format: `DIRECT-XX-SmartEyeglass`.

### Telephony

The SmartEyeglass includes Bluetooth headset functionality (HFP profile). The telephony API queries/controls BT headset mode:

| Constant | Value | Description |
|----------|-------|-------------|
| `TELEPHONY_MODE_BT_HEADSET_DISABLE` | 0 | Headset disabled |
| `TELEPHONY_MODE_BT_HEADSET_ENABLE` | 1 | Headset enabled |

### Standby Mode

Extensions can enter standby mode to conserve power. Standby terminates when the user presses any button or touches the touch sensor.

| Constant | Value |
|----------|-------|
| `STANDBY_MODE_OFF` | 0 |
| `STANDBY_MODE_ON` | 1 |
| `STANDBY_CONFIRMED_RESULT_NG` | 0 |
| `STANDBY_CONFIRMED_RESULT_OK` | 1 |

### Sound Effects

Controller button press feedback can be enabled/disabled:
- `enableSoundEffect()` / `disableSoundEffect()`
- `SOUND_EFFECT_OFF = 0`, `SOUND_EFFECT_ON = 1`

---

## 9. Registration Flow

### Content Provider Architecture

The Registration API uses an Android ContentProvider backed by SQLite:

```
Authority: com.sonyericsson.extras.liveware.aef.registration
Base URI:  content://com.sonyericsson.extras.liveware.aef.registration
```

### Database Tables

| Table | URI Path | Description |
|-------|----------|-------------|
| HostApp | `host_app` | One record per accessory's host app |
| Device | `device` | Physical devices per host app |
| Display | `display` | Display capabilities per device |
| Sensor | `sensor` | Sensor capabilities per device |
| SensorType | `sensor_type` | Sensor type definitions |
| Input | `input` | Input capabilities per device |
| KeyPad | `keypad` | Keypad details per input |
| Tap | `tap` | Tap gesture support |
| Led | `led` | LED capabilities |
| Widget | `widget` | Widget capabilities |
| Extension | `extensions` | Registered extensions |
| ApiRegistration | `api_registration` | Per-host-app API registrations |
| WidgetRegistration | `widget_registration` | Widget registrations |

### Extension Registration Steps

```
1. Listen for EXTENSION_REGISTER_REQUEST_INTENT broadcast
2. Insert record into Extension table (name, config activity, icon, etc.)
3. Query HostApp table to discover available accessories
4. For each host app: insert ApiRegistration record indicating which APIs used
5. Extension is now ready to receive Control/Sensor/Widget intents
```

### Security

- Extensions must declare `com.sonyericsson.extras.liveware.aef.EXTENSION_PERMISSION`
- HostApps require `com.sonyericsson.extras.liveware.aef.HOSTAPP_PERMISSION`
- Extension key mechanism prevents intent spoofing

### Accessory Connection

```
HostApp broadcasts ACCESSORY_CONNECTION_INTENT:
  EXTRA_CONNECTION_STATUS = STATUS_CONNECTED (1) or STATUS_DISCONNECTED (0)
  EXTRA_AHA_PACKAGE_NAME = host app package
```

---

## 10. Tunnel Protocol

The Tunnel API provides a **low-latency IPC bypass** that avoids the Android broadcast queue. This is critical for time-sensitive operations (real-time sensor data, camera streaming, AR animation).

### Architecture

```
Extension Service
  ↕ Messenger (Android IPC)
Host Application
  ↕ Wire protocol
Glasses hardware
```

### Tunnel Messages (Message.what values)

| Constant | Value | Description |
|----------|-------|-------------|
| `SETUP_MESSENGER` | 0 | First message: host→ext, carries Messenger reference |
| `SETUP_FAILED` | 1 | Ext→host: unrecoverable setup failure |
| `DISCONNECT` | 2 | Ext→host: request tunnel closure |
| `TUNNEL_INTENT` | 3 | Either direction: tunneled intent (obj = Intent) |

### Enabling Tunnel in Manifest

```xml
<service android:name="com.sonyericsson.extras.liveware.extension.util.TunnelService">
  <intent-filter>
    <action android:name="com.sonyericsson.extras.liveware.aef.tunnel.action.BIND" />
  </intent-filter>
</service>
```

### Key Comment Insight

> "For all time sensitive user interactions extensions need to communicate with the accessory with foreground priority. This API enables a host application to bind to an extension service and exchange a pair of Messenger objects allowing for a two way communication using a simple intent tunneling protocol."

> "The extension service will have foreground priority as long as a host application is bound to it."

---

## 11. All Intent Constants

### SmartEyeglassControl.Intents (com.sony.smarteyeglass.control.*)

| Intent | Direction | Category |
|--------|-----------|----------|
| `API_VERSION_CONFIRM` | App→Host | Setup |
| `TEXT_SHOW` | App→Host | Display |
| `DIALOG_OPEN` | App→Host | UI |
| `DIALOG_CLOSED_EVENT` | Host→App | UI |
| `VOICE_TEXT_INPUT_ENABLE` | App→Host | Audio |
| `VOICE_TEXT_INPUT_NOTIFY_RECOGNIZED_TEXT_EVENT` | Host→App | Audio |
| `POWER_MODE_SET_MODE` | App→Host | Config |
| `POWER_MODE_NOTIFY_MODE_EVENT` | Host→App | Config |
| `SAFE_DISPLAY_MODE_SET_MODE` | App→Host | Display |
| `SCREEN_DEPTH_SET_DEPTH` | App→Host | Display |
| `CAMERA_SET_MODE` | App→Host | Camera |
| `CAMERA_START` | App→Host | Camera |
| `CAMERA_CAPTURE_STILL` | App→Host | Camera |
| `CAMERA_STOP` | App→Host | Camera |
| `CAMERA_NOTIFY_CAPTURED_FILE_EVENT` | Host→App | Camera |
| `CAMERA_NOTIFY_ERROR_EVENT` | Host→App | Camera |
| `AR_SET_MODE` | App→Host | AR |
| `AR_CHANGE_CYLINDRICAL_VERTICAL_RANGE` | App→Host | AR |
| `AR_ENABLE_ANIMATION_REQUEST` | App→Host | AR |
| `AR_ENABLE_ANIMATION_RESPONSE` | Host→App | AR |
| `AR_DISABLE_ANIMATION_REQUEST` | App→Host | AR |
| `AR_DISABLE_ANIMATION_RESPONSE` | Host→App | AR |
| `AR_REGISTER_OBJECT_REQUEST` | App→Host | AR |
| `AR_REGISTER_OBJECT_RESPONSE` | Host→App | AR |
| `AR_GET_OBJECT_REQUEST` | Host→App | AR |
| `AR_GET_OBJECT_RESPONSE` | App→Host | AR |
| `AR_CHANGE_OBJECT_ORDER` | App→Host | AR |
| `AR_MOVE_OBJECT` | App→Host | AR |
| `AR_DELETE_OBJECT` | App→Host | AR |
| `DISPLAY_NOTIFY_STATUS_EVENT` | Host→App | Display |
| `DISPLAY_DATA_RESULT` | Host→App | Display |
| `AR_ANIMATION_RESULT` | Host→App | AR |
| `BATTERY_GET_LEVEL_REQUEST` | App→Host | Status |
| `BATTERY_GET_LEVEL_RESPONSE` | Host→App | Status |
| `TELEPHONY_GET_MODE_REQUEST` | App→Host | Telephony |
| `TELEPHONY_GET_MODE_RESPONSE` | Host→App | Telephony |
| `SOUND_EFFECT_SET_MODE` | App→Host | Config |
| `STANDBY_CONFIRM_REQUEST` | Host→App | Power |
| `STANDBY_CONFIRM_RESPONSE` | App→Host | Power |
| `STANDBY_NOTIFY_CONDITION_EVENT` | Host→App | Power |
| `STANDBY_ENTER` | App→Host | Power |

### Control.Intents (com.sonyericsson.extras.aef.control.*)

| Intent | Direction | Category |
|--------|-----------|----------|
| `START_REQUEST` | App→Host | Lifecycle |
| `STOP_REQUEST` | App→Host | Lifecycle |
| `START` | Host→App | Lifecycle |
| `STOP` | Host→App | Lifecycle |
| `PAUSE` | Host→App | Lifecycle |
| `RESUME` | Host→App | Lifecycle |
| `ERROR` | Host→App | Lifecycle |
| `SET_SCREEN_STATE` | App→Host | Display |
| `LED` | App→Host | Hardware |
| `STOP_LED` | App→Host | Hardware |
| `VIBRATE` | App→Host | Hardware |
| `STOP_VIBRATE` | App→Host | Hardware |
| `DISPLAY_DATA` | App→Host | Display |
| `CLEAR_DISPLAY` | App→Host | Display |
| `KEY_EVENT` | Host→App | Input |
| `TAP_EVENT` | Host→App | Input |
| `TOUCH_EVENT` | Host→App | Input |
| `SWIPE_EVENT` | Host→App | Input |
| `PROCESS_LAYOUT` | App→Host | Display |
| `SEND_IMAGE` | App→Host | Display |
| `SEND_TEXT` | App→Host | Display |
| `ACTIVE_POWER_SAVE_MODE_STATUS_CHANGED` | Host→App | Power |
| `OBJECT_CLICK_EVENT` | Host→App | Input |
| `LIST_COUNT` | App→Host | List |
| `LIST_MOVE` | App→Host | List |
| `LIST_REQUEST_ITEM` | Host→App | List |
| `LIST_ITEM` | App→Host | List |
| `LIST_ITEM_CLICK` | Host→App | List |
| `LIST_ITEM_SELECTED` | Host→App | List |
| `LIST_REFRESH_REQUEST` | Host→App | List |
| `MENU_SHOW` | App→Host | Menu |
| `MENU_ITEM_SELECTED` | Host→App | Menu |

### Sensor.Intents

| Intent | Direction |
|--------|-----------|
| `SENSOR_REGISTER_LISTENER` | App→Host |
| `SENSOR_UNREGISTER_LISTENER` | App→Host |
| `SENSOR_ERROR_MESSAGE` | Host→App |

---

## 12. All Numeric Constants

### Screen States

| Constant | Value |
|----------|-------|
| `SCREEN_STATE_OFF` | 0 |
| `SCREEN_STATE_DIM` | 1 |
| `SCREEN_STATE_ON` | 2 |
| `SCREEN_STATE_AUTO` | 3 |

### Voice-to-Text Results

| Constant | Value |
|----------|-------|
| `VOICE_TEXT_INPUT_RESULT_OK` | 0 |
| `VOICE_TEXT_INPUT_RESULT_FAILED` | 1 |
| `VOICE_TEXT_INPUT_RESULT_CANCEL` | 2 |

### Dialog Modes

| Constant | Value | Description |
|----------|-------|-------------|
| `DIALOG_MODE_TIMEOUT` | 1 | Auto-close after 5 seconds |
| `DIALOG_MODE_OK` | 2 | Requires OK confirmation |
| `DIALOG_MODE_USER_DEFINED` | 3 | Custom buttons (max 3) |

---

## 13. Wire Protocol CMD Bytes

Complete table from DEX bytecode reverse engineering:

| Byte | Name | Dir | Payload | Description |
|------|------|-----|---------|-------------|
| `0x01` | Ack | RX | — | Generic ACK |
| `0x02` | Nak | RX | — | Generic NAK |
| `0x05` | Ping | RX | — | Keep-alive |
| `0x06` | LevelNotification | RX | — | Ready signal |
| `0x07` | VersionRequest | TX | — | FW version query |
| `0x08` | VersionResponse | RX | string | FW version string |
| `0x0a` | ProtocolVersion | RX | — | First frame on connect |
| `0x30` | OpenAppStartRequest | TX | — | Start app session |
| `0x31` | OpenAppStartResponse | RX | — | Session confirmed |
| `0x33` | OpenAppStopRequest | TX | — | Stop request |
| `0x34` | OpenAppStop | RX | — | Stop confirmed |
| `0x35` | OpenAppImage | TX | DEFLATE'd 8-bit pixels | Display grayscale image |
| `0x36` | OpenAppImageAck | RX | — | Image received ACK |
| `0x38` | OpenAppSensorStart | TX | sensor_id, rate | Start sensor stream |
| `0x39` | OpenAppSensorStop | TX | sensor_id | Stop sensor stream |
| `0x3a` | OpenAppAcceleration | RX | 3 × float32 BE | Accelerometer data |
| `0x3b` | OpenAppLightSensor | RX | 1 × float32 BE | Ambient light |
| `0x3d` | OpenAppSetScreenstate | TX | on/off | Screen on/off |
| `0x3e` | OpenAppBatterySensor | RX | battery data | Battery status |
| `0x71` | SettingsStatusRequest | TX | — | Phase 1 handshake |
| `0x72` | SettingsStatusResponse | RX | — | Phase 2 handshake |
| `0x81` | FotaStatus | RX | — | Firmware OTA status |
| `0x85` | NewHostApp | TX | — | Register host app |
| `0x90` | WifiStatusReq | TX | — | Query WiFi state |
| `0x91` | WifiStatusRes | RX | state byte | WiFi state |
| `0x92` | WifiStatusTurnOnReq | TX | — | Enable WiFi |
| `0x93` | WifiStatusTurnOffReq | TX | — | Disable WiFi |
| `0x94` | WifiConnectReq | TX | SSID, PSK | Connect to AP |
| `0x95` | WifiConnectivityStatus | RX | status | AP connection state |
| `0x96` | WifiDPSwitchPathReq | BOTH | — | Switch data path |
| `0x97` | WifiDPSwitchPathRes | RX | — | Path switch confirmed |
| `0xb1` | OpenAppClearScreen | TX | — | Clear display |
| `0xb4` | CameraCaptureRequest | TX | — | Trigger capture |
| `0xb5` | CameraCaptureResponse | RX | status, fmt, size | Capture metadata |
| `0xb6` | CameraCaptureData | RX | seq, len, data | JPEG chunk |
| `0xb7` | CameraCaptureDataDone | RX | status, count, size | Transfer complete |
| `0xb8` | CameraCaptureDataCancel | TX | reason | Cancel transfer |
| `0xbb` | OpenAppRotationVector | RX | 3-4 × float32 BE | Rotation vector |
| `0xbc` | OpenAppGyro | RX | 3 × float32 BE | Gyroscope data |
| `0xbd` | OpenAppMagnetometer | RX | 3 × float32 BE | Magnetometer data |
| `0xc3` | OpenAppMode | TX | mode byte | Set power/display/AR mode |
| `0xcd` | OpenAppShiftObject | TX | object data | Move AR object |
| `0xce` | OpenAppCameraMode | TX | mode, res, quality, fps | Set camera params |
| `0xe0` | LayoutInit | TX | layout data | Layout init |
| `0xe5` | LayoutEventNotify | RX | event data | Layout event |
| `0xf1` | CameraCaptureDataAck | TX | seq_num | ACK camera data chunk |
| `0xff` | LayoutPlaceImageData | TX | image data | Place image in layout |

### Frame Wire Format

```
[cmdId: 1B] [length_hi: 1B] [length_lo: 1B] [payload: length bytes]
```

All multi-byte values are **big-endian** (Java ByteBuffer default).

---

## 14. Key Implementation Insights from Comments

### From SmartEyeglassControlUtils.java

1. **Image size limit**: `IMAGE_PIXEL_SIZE_MAX = 57822` — images exceeding this throw `IllegalArgumentException`
2. **PNG compression quality**: `PNG_COMPLESS_QUALITY = 100` (lossless) — used for AR animation objects
3. **Vertical range**: AR cylindrical vertical range max is 60.0 degrees, min is 0.0
4. **JPEG streaming resolution**: Only QVGA is supported for streaming modes (`CAMERA_JPEG_STREAM_SUPPORT_RESOLUTION`)
5. **Display state comment**: "Keep in mind that we are not showing the images on the phone, but on the accessory" — sets `inDensity = DENSITY_DEFAULT` to avoid scaling
6. **Socket naming**: Camera socket is named `"CameraImage"`, AR animation socket name comes from HostApp response
7. **BroadcastReceiver pattern**: SmartEyeglassControlUtils IS a BroadcastReceiver — registers for 16 intent filters on `activate()`
8. **Handler/Looper pattern**: All intent callbacks are posted via `Handler.post()` to ensure main-thread execution
9. **Camera socket protocol**: Uses `DataInputStream` with `readInt()` calls — Java big-endian by default

### From Control.java

10. **Exclusivity**: "Since an extension implementing this API takes complete control over the accessory, only one extension can run at a time"
11. **Display state default**: "By default when your extension starts the display state will be set to 'Auto'"
12. **Power consciousness**: "It is important that you program your extension so that it consumes as little power as possible"
13. **Hidden API annotations**: Several `@hide` comments indicate this was a protected/partner API, not public
14. **Layout support**: Limited subset — only AbsoluteLayout, FrameLayout, LinearLayout, RelativeLayout + View, ImageView, TextView, ListView, Gallery
15. **Only `px` dimensions**: "The px dimensions is the only dimension supported" in layouts

### From Sensor.java

16. **Data format**: "The data format is identical to a standard Android SensorEvent"
17. **One socket per sensor**: "If multiple sensors are used, multiple LocalServerSocket objects must also be used since one sensor is bound to exactly one LocalServerSocket"

### From Registration.java

18. **Registration prerequisite**: "Before an application can register itself as an extension, there must be at least one host application installed"
19. **Configuration activity**: Extensions provide their own settings Activity via `CONFIGURATION_ACTIVITY` column

### From Tunnel.java

20. **Priority boost**: "The extension service will have foreground priority as long as a host application is bound to it"
21. **Connection intent override**: Adding `ACCESSORY_CONNECTION` to tunnel service filter gives immediate priority — "should only be used when really necessary" (example: incoming call)

### From CylindricalRenderObject.java

22. **Javadoc error**: The `@param v` says "angle in radians" but the actual coordinate system uses degrees (-90 to +90). The Intents documentation says degrees. This is a documentation bug in the source.

### From EightBitMonochromeImageEncoder (inner class)

23. **Luma formula**: Uses ITU-R BT.601: `(R*299 + G*587 + B*114) / 1000`
24. **Alpha handling**: Pre-multiplied alpha: `value = (value * alpha) / 255`
25. **Config support**: Only handles `ARGB_8888` and `RGB_565` — throws for other configs
26. **RGB_565 note**: "the RGB_565 type images also returns RGB8888 format when using getPixels" — Android pixel API normalizes

---

## 15. AI Navigation Strategy

### How to Approach These Java Projects

#### Quick Reference Lookup

1. **"What constant/intent for X?"** → Start with `SmartEyeglassControl.java` (eyeglass-specific) then `Control.java` (generic). Constants are exhaustively documented with Javadoc.

2. **"How does feature X work?"** → Read `SmartEyeglassControlUtils.java` — it's the **central hub** (1645 lines) containing ALL eyeglass feature implementations. Methods are well-commented with param descriptions.

3. **"What events does X produce?"** → Check `SmartEyeglassEventListener.java` — 18 callback methods, each with a description of when it fires.

4. **"What wire bytes for X?"** → Check `glasses-sdk/CAMERA_PROTOCOL.md` (complete CMD table) then `glasses-sdk/PROTOCOL_MAP.md` (transport architecture).

#### File Priority Order

When reverse-engineering a feature, read in this order:

```
1. SmartEyeglassControl.java         — constants & intent names
2. SmartEyeglassControlUtils.java    — implementation methods & socket protocols
3. SmartEyeglassEventListener.java   — callback signatures
4. Control.java                      — generic control constants
5. Sensor.java                       — sensor constants & data format
6. Registration.java                 — capability database schema
7. Tunnel.java                       — low-latency IPC (simple)
8. ar/RenderObject.java              — AR object base class
9. ar/CylindricalRenderObject.java   — cylindrical coords
10. ar/GlassesRenderObject.java      — pixel coords
```

#### Pattern Recognition

All Sony APIs follow this pattern:
```
Extension sends Intent with EXTRA_* params
  → HostApp processes, sends wire bytes to glasses
  → Glasses respond with wire bytes
  → HostApp converts to Intent, broadcasts to extension
  → Extension's EventListener callback fires
```

To RE a new feature:
1. Find the Intent constant in `SmartEyeglassControl.Intents`
2. Find the method in `SmartEyeglassControlUtils` that creates that Intent
3. Read the EXTRA_* parameters to understand the data model
4. Find the corresponding EventListener callback for the response
5. Map to wire protocol CMD bytes using the PROTOCOL_MAP

#### Grepping Strategy

```bash
# Find all uses of a CMD byte
grep -rn "0xce\|0xCE\|206" --include="*.java" --include="*.swift" --include="*.md"

# Find all camera-related code
grep -rn "CAMERA\|camera\|Camera" --include="*.java" _dev/smarteyeglass-explorer/

# Find all sensor types
grep -rn "SensorType\|ACCELEROMETER\|GYROSCOPE\|MAGNETOMETER\|LIGHT\|ROTATION" --include="*.java"

# Find all intent actions
grep -rn "static final String.*INTENT\b" --include="*.java" | grep -v "build/"

# Find hidden API hints
grep -rn "@hide\|TODO\|FIXME\|HACK\|workaround" --include="*.java"
```

#### Key Gotchas for AI Agents

1. **Build directories**: Always exclude `*/build/*` from searches — contains duplicated generated code
2. **Byte ordering**: All wire protocol values are **big-endian** — Java's default ByteBuffer order
3. **QVGA-only streaming**: Camera streaming supports ONLY QVGA (320×240) — not documented prominently but enforced in code
4. **Sensor ACK**: Undocumented requirement — glasses stop sending IMU data without `[0x01, 0x00, 0x00]` ACK
5. **Image size check**: Both width×height and individual dimension checks against display size — easy to hit limits
6. **AR mode prerequisite**: Must call `setRenderMode(MODE_AR)` before ANY AR object operations — throws IllegalStateException
7. **Object ID 0 = delete all**: `deleteARObject` with objectId=0 deletes ALL registered objects
8. **CylindricalRenderObject v parameter**: Javadoc says "radians" but API uses degrees — trust the Intents documentation
9. **Safe display mode**: SAFE_DISPLAY_MODE_1 renders only the bottom half — important for safety-critical apps
10. **Extension key security**: Always verify `EXTRA_EXTENSION_KEY` in received Intents — prevents spoofing

#### The One File That Matters Most

**`SmartEyeglassControlUtils.java`** (1645 lines) is the Rosetta Stone. It contains:
- Every feature's implementation method
- All socket protocols (camera data format, AR animation format)
- The `EightBitMonochromeImageEncoder` (display pixel format)
- All validation logic (supported resolutions, quality levels, size limits)
- The BroadcastReceiver routing table (which intents go to which callbacks)
- World-to-cylindrical coordinate conversion math

When in doubt, start there.
