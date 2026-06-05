# Sony SED-E1 SDK — Full Protocol Map

> Reverse-engineered from source + runtime verification on 2026-06-04.

---

## Architecture: what actually happens

```
Your App
  │  showBitmap(bmp)
  ▼
SmartEyeglassControlUtils          ← thin Intent wrapper, lives in your process
  │  sendBroadcast(DISPLAY_DATA)
  ▼
com.sony.smarteyeglass              ← MisiAha, native BT bridge
  │  Bluetooth RFCOMM / BLE
  ▼
SED-E1 Controller                   ← ARM Cortex, runs Sony firmware
  │  LVDS / proprietary
  ▼
419×138 green waveguide display
```

---

## Wire Protocol: Intent actions

All communication is Android `sendBroadcast()` / `sendOrderedBroadcast()`.
Target: `com.sony.smarteyeglass` package.

### Display
| Intent action | Direction | Key extras |
|---------------|-----------|------------|
| `com.sony.smarteyeglass.control.DISPLAY_DATA` | App → Glasses | `data` byte[] (PNG), `x` int, `y` int |
| `com.sony.smarteyeglass.control.DISPLAY_DATA_RESULT` | Glasses → App | `transaction_number`, `result` |
| `com.sony.smarteyeglass.control.AR_SET_MODE` | App → Glasses | `ar_mode` (0=normal, 1=AR) |

### Camera
| Intent action | Direction | Key extras |
|---------------|-----------|------------|
| `com.sony.smarteyeglass.control.CAMERA_SET_MODE` | App → Glasses | `camera_jpeg_quality`, `camera_resolution`, `camera_mode` |
| `com.sony.smarteyeglass.control.CAMERA_START` | App → Glasses | `camera_file_path` (optional) |
| `com.sony.smarteyeglass.control.CAMERA_CAPTURE_STILL` | App → Glasses | — |
| `com.sony.smarteyeglass.control.CAMERA_STOP` | App → Glasses | — |
| `com.sony.smarteyeglass.control.CAMERA_NOTIFY_CAPTURED_FILE_EVENT` | Glasses → App | `camera_file_path` |
| `com.sony.smarteyeglass.control.CAMERA_NOTIFY_ERROR_EVENT` | Glasses → App | `error_code` |

### Input (received by your app)
| Intent action | Direction | Key extras |
|---------------|-----------|------------|
| `com.sonyericsson.extras.liveware.aef.control.TOUCH_EVENT` | SmartConnect → App | `x`, `y`, `action` (PRESS/RELEASE/LONGPRESS) |
| `com.sonyericsson.extras.liveware.aef.control.SWIPE_EVENT` | SmartConnect → App | `direction` (LEFT=1, RIGHT=2, UP=3, DOWN=4) |

### Sensors
Registered via Smart Connect ContentProvider (`Registration.Sensor.URI`).
Callbacks arrive as broadcasts to your service.

### AR
| Intent action | Extras |
|---------------|--------|
| `CONTROL_AR_REGISTER_OBJECT_REQUEST` | objectId, bitmap, coordinate_type, h, v, order, objectType |
| `CONTROL_AR_MOVE_OBJECT` | objectId, h, v |
| `CONTROL_AR_DELETE_OBJECT` | objectId |
| `CONTROL_AR_CHANGE_CYLINDRICAL_VERTICAL_RANGE` | range (float, degrees) |

---

## Registration: what Smart Connect needs

Three ContentProvider inserts into `com.sonyericsson.extras.liveware`:

1. **`Registration.Extension.URI`** — one row per extension app  
   Columns: `name`, `extension_key` (unique string), `packageName`, `notificationApiVersion`

2. **`Registration.Registration.URI`** (called `registration` table) — links extension ↔ host app  
   Columns: `extensionId`, `hostAppPackageName`, `controlApiVersion`, `sensorApiVersion`

3. **`Registration.Device.URI`** + **`Registration.Display.URI`** — populated by `com.sony.smarteyeglass`, not by your app

The `registration` row is the one that was empty — it gets inserted by `RegistrationHelper.registerApiRegistration()` only when `isSupportedControlAvailable()` returns true, which requires the device row (419×138) to already exist.

**Race condition**: your extension registers before SmartEyeglass host populates the device. Solution: listen for `ACCESSORY_CONNECTION_INTENT` and re-register on each connection.

---

## Permissions model (the old mess)

| Permission | Protection | Who declares | Who needs |
|------------|------------|--------------|-----------|
| `com.sonyericsson.extras.liveware.aef.EXTENSION_PERMISSION` | dangerous | Smart Connect | Extension apps |
| `com.sonyericsson.extras.liveware.aef.HOSTAPP_PERMISSION` | signature | Smart Connect | SmartEyeglass host |
| `com.sonyericsson.extras.liveware.DEVICE_CONFIGURED_PERMISSION` | signature\|system | Smart Connect | SmartEyeglass host |
| `com.sony.smarteyeglass.permission.SMARTEYEGLASS` | — | SmartEyeglass host | Extension apps |

**In the new SDK**: the bridge service holds all Sony permissions. Client apps talk to the bridge. Clients need no Sony permissions.

---

## Display pipeline: bitmap → glasses

```
Bitmap (419×138, ARGB_8888)
  │  bitmap.compress(PNG, 100, baos)  ← SmartEyeglassControlUtils.showBitmap()
  ▼
byte[] png_data
  │  Intent(DISPLAY_DATA).putExtra("data", png_data)
  │  sendBroadcast to com.sony.smarteyeglass
  ▼
MisiAha receives, decodes PNG
  │  converts to 1-bit green (white pixel → green LED on)
  ▼
BT RFCOMM frame to controller
  ▼
419×138 OLED waveguide
```

Key insight: **it's just a PNG over a broadcast Intent**. No SDK required for display.

---

## Minimal extension: what you actually need

```
AndroidManifest.xml:
  <uses-permission android:name="com.sonyericsson.extras.liveware.aef.EXTENSION_PERMISSION"/>
  <uses-permission android:name="com.sony.smarteyeglass.permission.SMARTEYEGLASS"/>
  <service> with action com.sonyericsson.extras.liveware.aef.EXTENSION
  <receiver> for EXTENSION_REGISTER_REQUEST + CAPABILITY_CHANGED
  <meta-data android:name="...EXTENSION_KEY" android:value="your.unique.key"/>

Registration (one-time, on EXTENSION_REGISTER_REQUEST):
  1. Insert into Registration.Extension.URI  
  2. On ACCESSORY_CONNECTION_INTENT: insert into Registration.Registration.URI

Display (per-frame):
  Intent i = new Intent("com.sonyericsson.extras.liveware.aef.control.SHOW_BITMAP");
  i.setPackage("com.sony.smarteyeglass");
  i.putExtra("data", pngBytes);
  context.sendBroadcast(i, "com.sony.smarteyeglass.permission.SMARTEYEGLASS");
```

That's the entire SDK surface for display. ~50 lines, no library needed.
