# Sony SED-E1 Dev Environment Log

> Machine: macOS (Apple Silicon / x86 TBD), Homebrew 5.1.14  
> Goal: Full emulator-only dev loop for Sony SmartEyeglass SED-E1  
> Started: 2026-06-04

---

## Inventory (pre-setup state)

### Already present in project dir

| File | Notes |
|------|-------|
| `Sony/sony_smarteyeglass_sdk/` | SDK cloned from github.com/kaustubhcs/Sony |
| `com.sony.smarteyeglass_1.3.17052901-...apk` | SmartEyeglass host APK (final 2017 build) ✓ |
| `com.sonyericsson.extras.liveware_5.7.36.0001-...apk` | Smart Connect APK — **version 5.7.36, NOT the 5.7.20 recommended in master.md** |
| `Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/apks/SmartEyeglassEmulator.apk` | Emulator APK bundled in SDK ✓ |

### SDK structure (actual, verified)

```
sony_smarteyeglass_sdk/
├── apks/
│   ├── SmartEyeglassEmulator.apk
│   └── samples/
│       ├── HelloWorld.apk
│       ├── HelloLayouts.apk
│       ├── HelloEvents.apk
│       ├── HelloSensors.apk
│       ├── HelloStandbyMode.apk
│       ├── HelloWidget.apk
│       ├── HelloNotification.apk
│       ├── AdvancedLayouts.apk
│       ├── SampleARAnimationExtension.apk
│       ├── SampleARConvertCoordinateSystemExtension.apk
│       ├── SampleARCylindricalExtension.apk   ← AR API confirmed present!
│       ├── SampleCameraExtension.apk
│       ├── SampleDialogExtension.apk
│       ├── SampleDisplaySettingExtension.apk
│       ├── SamplePowerModeExtension.apk
│       ├── SampleSoundEffectSettingExtension.apk
│       └── SampleVoiceTextInputExtension.apk
├── samples/
│   ├── SmartExtensionAPI/     ← source library
│   ├── SmartExtensionUtils/   ← source library
│   ├── SmartEyeglassAPI/      ← source library (main glasses API)
│   ├── HelloLayouts/
│   ├── HelloSensors/
│   ├── SampleCameraExtension/
│   ├── SampleARCylindricalExtension/
│   └── ... (all others)
├── docs/
└── source.properties
```

### Confirmed API facts (from source inspection)

| Fact | Detail |
|------|--------|
| Display method | `SmartEyeglassControlUtils.showBitmap(Bitmap)` — confirmed ✓ |
| Render modes | `SmartEyeglassControl.Intents.MODE_NORMAL = 0`, `MODE_AR = 1` — confirmed ✓ |
| Set render mode | `utils.setRenderMode(int)` — confirmed ✓ |
| Camera modes | `CAMERA_MODE_STILL=0`, `CAMERA_MODE_STILL_TO_FILE=1`, `CAMERA_MODE_JPG_STREAM_LOW_RATE=2`, `CAMERA_MODE_JPG_STREAM_HIGH_RATE=3` |
| Camera trigger | `utils.requestCameraCapture()` and `utils.startCamera()` / `utils.startCamera(String filePath)` — confirmed ✓ |
| Build system | Old Eclipse Ant-based projects. Library references via `project.properties`. Target: `android-19` |
| HelloLayouts dep chain | `→ SmartEyeglassAPI → SmartExtensionUtils → SmartExtensionAPI` |

### Missing / needs installation

- [ ] Java JDK (none found — macOS stub only)
- [ ] Android SDK (no `sdkmanager`, `adb`, `emulator` found)
- [ ] Android Studio (not installed)

---

## Step 1: Install Java JDK

**Problem:** macOS has a `/usr/bin/java` stub that says "install Java" — no actual JDK present.  
**Plan:** Install OpenJDK 17 via Homebrew (Android Studio 2023+ bundles its own JDK, but we need javac for the CLI path too).

```bash
brew install openjdk@17
```

> **Workaround noted:** Android Gradle for API 19 projects originally required JDK 8. Modern Android Gradle Plugin (AGP 8.x) requires JDK 17+. We'll use JDK 17 and target a matching AGP version.

---

## Step 2: Install Android Studio

Android Studio bundles: Android SDK, AVD manager, build tools, emulator.  
Installs via Homebrew cask.

```bash
brew install --cask android-studio
```

---

## Step 3: Configure Android SDK

After Android Studio installs, via SDK Manager:
- Install **Android 4.4 (API 19)** platform  
- Install **Android Emulator**  
- Install **Android SDK Build-Tools 34** (or latest)  
- Install **Intel x86 Emulator Accelerator (HAXM)** — or Apple Silicon uses built-in virtualization

---

## Step 4: Create AVD

- Name: `nexus5_api19`
- Device: Nexus 5
- System image: API 19, x86 (or x86_64 if API 19 x86 unavailable on ARM Mac — see workaround)
- RAM: 2048 MB

> **Potential ARM Mac workaround:** API 19 x86 system images may not run under Apple Silicon Rosetta. If so, use API 19 arm64 image or fall back to API 21 (Lollipop) — Smart Connect still works on API 21 since SmartEyeglass only requires API 16+.

---

## Step 5: Install APKs in emulator

```bash
# Order matters: Smart Connect first
adb install com.sonyericsson.extras.liveware_5.7.36.0001-...apk
adb install com.sony.smarteyeglass_1.3.17052901-...apk
adb install Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/apks/SmartEyeglassEmulator.apk
```

> **Version mismatch note:** We have Smart Connect 5.7.36 (newer than the 5.7.20 recommended in master.md). This should still work — the protocol is backward compatible — but log any issues.

---

## Step 6: Gradle Project Setup

The SDK samples use **Eclipse Ant** build system (no `build.gradle` in samples, uses `ant.xml` + `project.properties`). We'll create a **new Gradle project** that imports the three library source trees:

- `SmartExtensionAPI` → as `:SmartExtensionAPI` library module  
- `SmartExtensionUtils` → as `:SmartExtensionUtils` library module  
- `SmartEyeglassAPI` → as `:SmartEyeglassAPI` library module  

App module `app` depends on all three.

**Key constraint:** API 19, Java source compatibility 7 (no lambdas), `compileSdk 19`, `minSdk 19`.

---

## Workarounds & Issues Log

| # | Issue | Workaround | Status |
|---|-------|------------|--------|
| 1 | Java not installed | `brew install openjdk@17` | ⏳ pending |
| 2 | Android Studio not installed | `brew install --cask android-studio` | ⏳ pending |
| 3 | Smart Connect version 5.7.36 (newer than recommended 5.7.20) | Try it; if emulator handshake fails, find 5.7.20 | ⏳ pending |
| 4 | SDK samples are Ant/Eclipse projects (no Gradle) | Create new Gradle project, copy SDK source as library modules | ⏳ pending |
| 5 | API 19 x86 image may not exist for ARM Mac | Fall back to API 21 ARM or use x86_64 with Rosetta | ⏳ pending |

---

---

## What Was Accomplished (emulator session)

### ✅ Fully working

| Item | State |
|------|-------|
| Java 17 (OpenJDK via Homebrew) | Installed ✓ |
| Android SDK (cmdline-tools 36.6.11) | Installed ✓ |
| Android Studio | Installed ✓ |
| `platforms;android-19` | Installed ✓ |
| `platforms;android-21` | Installed ✓ |
| `build-tools;34.0.0` | Installed ✓ |
| AVD `nexus5_api21_arm64` | Created, boots ✓ |
| Gradle project `smarteyeglass-explorer/` | Builds clean ✓ |
| All 3 SDK libraries as Gradle modules | Compiles ✓ |
| Explorer app (8 demos) | Builds, installs ✓ |
| Smart Connect 5.7.36 (BT-patched) | Installed, initializes ✓ |
| SmartEyeglassEmulator | Installed, UI renders ✓ |
| SmartEyeglass host (arm64-stub repack) | Installs, MisiAha starts ✓ |
| Extension registers in SC database | `com.explorer` in `extension` table ✓ |
| SmartEyeglass device in SC database | 419×138 display, all sensors ✓ |
| SDK `RegistrationHelper` flow | Verified via smali + logcat ✓ |

### ❌ Blocked: Emulator Bluetooth wall

**Root cause:** The entire Sony Smart Extension stack requires Bluetooth to complete the host-app pairing handshake between Smart Connect and the SmartEyeglass device. Specifically:

1. `SmartEyeglassEmulator` starts → sends `com.sony.smarteyeglass.EMULATOR` intent
2. `com.sony.smarteyeglass` (MisiAha) starts → calls `reqRegisterAHA` in a retry loop
3. `reqRegisterAHA` broadcasts `HOST_PERMISSION_QUERY` to Smart Connect
4. Smart Connect registers the device (419×138 display confirms this worked)
5. **BUT** Smart Connect then waits for a Bluetooth connection event to mark the device as "connected" and begin routing extensions to it
6. Without Bluetooth, the emulator display panel stays black — Smart Connect never transitions the device from "registered" to "connected"

**Why this affects Apple Silicon specifically:**
- `master.md` was written for Intel Mac + API 19 x86 emulator
- API 19 x86 images have a software Bluetooth HAL that satisfies Smart Connect's BT check
- Apple Silicon can only run `arm64-v8a` system images (API 21+)
- API 21 arm64 images have NO Bluetooth HAL at all — `BluetoothAdapter.getDefaultAdapter()` returns null
- Android Emulator's `BluetoothEmulation` feature requires `virtio-serial-bus` which exists only in API 30+ images

**Things tried that don't work:**
- `hw.bluetooth=yes` in AVD config — no HAL in API 21 arm64 image
- `-feature BluetoothEmulation` emulator flag — QEMU crashes: `No 'virtio-serial-bus' bus found`
- macOS Bluetooth passthrough — same virtio requirement
- Patching Smart Connect to skip BT null checks — fixed startup crash but BT is structurally required for device state machine

---

## Step 6: APK patches & workarounds log

| # | Issue | Workaround | File |
|---|-------|------------|------|
| 1 | Java not installed | `brew install openjdk@17` | — |
| 2 | Android Studio not installed | `brew install --cask android-studio` | — |
| 3 | `android-commandlinetools` not in PATH | `brew install android-commandlinetools android-platform-tools` | — |
| 4 | API 19 x86 → FATAL on arm64 host | Use API 21 arm64-v8a instead | AVD config |
| 5 | API 19 armeabi-v7a → FATAL (QEMU2 dropped 32-bit ARM) | Same — API 21 arm64-v8a | AVD config |
| 6 | SDK samples are Ant/Eclipse (no Gradle) | Created new Gradle project, SDK source as library modules | `smarteyeglass-explorer/` |
| 7 | `SmartExtensionAPI`: `TimeView`/`TimeLayout` import SmartWatch 2 SDK | Deleted those two files — not needed for SmartEyeglass | `libs/SmartExtensionAPI/` |
| 8 | AGP manifest merger: SmartEyeglassAPI has `android:label` conflict | Added `tools:replace="android:label"` to app manifest | `AndroidManifest.xml` |
| 9 | `setCameraMode` takes 3 args (jpegQuality, resolution, mode) not 1 | Fixed call sites in CameraCaptureDemo, CameraStreamDemo | demos/*.java |
| 10 | `CylindricalRenderObject` takes 6 args not 5 | Fixed constructor call in ARDemo | ARDemo.java |
| 11 | `RegistrationAdapter` is not a BroadcastReceiver | Rewrote ExtensionReceiver as plain BroadcastReceiver that startService()s | ExtensionReceiver.java |
| 12 | `SmartEyeglassControlUtils` listener is constructor-only (no setEventListener) | Added delegating `SmartEyeglassEventListener` in ExplorerControl, `DemoEventListener` interface | ExplorerControl.java |
| 13 | `CameraEvent` has no `getWidth()`/`getHeight()` | Removed those calls, use `getFrameId()` instead | CameraCaptureDemo.java |
| 14 | `SensorDemo` used `getSensors()` (doesn't exist) | Use `getSensor(SensorTypeValue.ACCELEROMETER)` pattern from HelloSensors sample | SensorDemo.java |
| 15 | Smart Connect 5.7.36 crashes: `BluetoothAdapter.getDefaultAdapter().isEnabled()` NPE | Decompiled with apktool, patched 2 smali null-guards, re-signed with debug key | `/tmp/sc2.apk` |
| 16 | SC 5.7.36 EULA dialog: checkbox coords in logical landscape, screencap in physical portrait | Dumped UI via uiautomator, got exact bounds `[123,930][231,1051]`, tapped center | — |
| 17 | SmartEyeglass host APK `armeabi-v7a` only → `INSTALL_FAILED_NO_MATCHING_ABIS` | Injected minimal arm64 ELF stub `.so` files via Python zipfile append, re-signed | `/tmp/seg_arm64.apk` |
| 18 | Repacking APK with `zip -r` breaks resource table | Use Python `zipfile` append-to-original instead of full repack | same |
| 19 | Smart Connect EULA consent prefs: invalid XML written via `echo` | Used Python to write properly-quoted XML, pushed with `adb push` | shared_prefs |
| 20 | Extension registered in SC db but `registration` table stays empty | `registerWithAllHostApps` ran before SmartEyeglass device wrote its 419×138 display to db | timing issue |

---

## Confirmed API facts (from source + runtime)

| Fact | Detail |
|------|--------|
| `showBitmap(Bitmap)` | Confirmed method name ✓ |
| `setRenderMode(int)` | Confirmed — `MODE_NORMAL=0`, `MODE_AR=1` |
| `setCameraMode(int, int, int)` | 3 params: jpegQuality, resolution, recordingMode |
| `CAMERA_JPEG_QUALITY_STANDARD=1`, `_FINE=2`, `_SUPER_FINE=3` | Confirmed |
| `CAMERA_RESOLUTION_QVGA=6`, `_VGA=4`, `_1M=1`, `_3M=0` | Confirmed |
| `CAMERA_MODE_STILL=0`, `_STILL_TO_FILE=1`, `_JPG_STREAM_LOW_RATE=2`, `_HIGH_RATE=3` | Confirmed |
| `CylindricalRenderObject(id, bitmap, order, objectType, h, v)` | 6 params ✓ |
| `AR_OBJECT_TYPE_STATIC_IMAGE=0`, `_ANIMATED_IMAGE=1` | Confirmed |
| `AR_COORDINATE_TYPE_CYLINDRICAL=1` | Confirmed |
| `SmartEyeglassEventListener` is a class (not interface), override methods | Confirmed |
| `AccessorySensorManager.getSensor(SensorTypeValue.X)` | Correct pattern |
| `AccessorySensor.registerFixedRateListener(listener, Sensor.SensorRates.SENSOR_DELAY_UI)` | Confirmed |
| SC `registration.db` → extension: `{_id=2, packageName=com.explorer}` | Registered ✓ |
| SC `registration.db` → device: `{419×138, allSensors, controlApiVersion=4}` | Present ✓ |

---

## API 24 Emulator Test (Android 7 / Nougat)

**Result: Same wall. Logged.**

| Check | API 21 | API 24 |
|-------|--------|--------|
| Boots | ✓ | ✓ |
| Smart Connect installs | ✓ (patched) | ✓ (patched) |
| SC survives BT null (patched) | ✓ | ✓ |
| SmartEyeglass host installs | ✓ (arm64 stub) | ✓ (arm64 stub) |
| SmartEyeglassEmulator installs | ✓ | ✓ |
| Explorer app installs | ✓ | ✓ |
| Extension registers in SC DB | ✓ | ✓ |
| `adb shell service check bluetooth` | `not found` | `not found` |
| MisiAha / `reqRegisterAHA` | loops | loops |
| Glasses display green | ✗ BLACK | ✗ BLACK |
| `/data/data/` readable | ✓ (API 21) | ✗ SELinux enforcing (API 24+) |

**Root cause is identical**: `Service bluetooth: not found` on both API levels. No Android emulator arm64 image below API 30 has a Bluetooth HAL. Smart Connect's device state machine needs a BT connection event to transition `registered → connected`. Without it, display stays black on all emulator versions.

**API 24-specific notes:**
- SELinux enforcing blocks `/data/data/` access — can't read registration DB directly
- Background service limits introduced in API 26+ don't apply here yet (API 24 still allows background services)
- Runtime permissions (API 23+) are not an issue — BLUETOOTH/BLUETOOTH_ADMIN are `normal` permissions, auto-granted
- Smart Connect 5.7.36 (targetSdk 28) runs fine on API 24

**Conclusion**: Any emulator on Apple Silicon hits this wall at any API level ≤ 29. API 30+ emulators have BT via netsim/rootcanal but SmartEyeglass stack is EOL and won't run on Android 11+.

---

## Decision: Pivot to Real Hardware

**Physical SED-E1 device is available.** The emulator path is structurally blocked on Apple Silicon due to Bluetooth.

### What you need
- Android phone running **API 16–21** (Android 4.1–5.1) with Bluetooth
- USB cable
- The glasses + controller

### Install order on phone
```bash
# 1. Uninstall any test APKs from emulator session (different signing key)
adb uninstall com.sonyericsson.extras.liveware
adb uninstall com.sony.smarteyeglass

# 2. Install ORIGINALS (not the patched/re-signed versions) in order:
adb install com.sonyericsson.extras.liveware_5.7.36.0001-...apk  # Smart Connect
adb install com.sony.smarteyeglass_1.3.17052901-...apk             # SmartEyeglass host

# 3. Install our app (debug-signed is fine for development)
adb install smarteyeglass-explorer/app/build/outputs/apk/debug/app-debug.apk
```

> **Note:** On a real phone, Smart Connect WON'T crash on Bluetooth (real BT hardware present). The BT null-guard patches are not needed. Use original unpatched APKs.

### Known issue: Smart Connect 5.7.36 on real phone
Version 5.7.36 targets Android 9 (API 28). On a KitKat/Lollipop phone it installs but BT pairing behavior may differ. If pairing fails, find Smart Connect 5.7.20 or earlier.

### Build for real device
The project already compiles. For a real `armeabi-v7a` phone:
- Change AVD to use armeabi-v7a system image, OR
- Just `adb install` directly to the phone

```bash
cd smarteyeglass-explorer
/tmp/gradle-install/gradle-7.5/bin/gradle assembleDebug
# then:
adb install app/build/outputs/apk/debug/app-debug.apk
```

---

---

## Protocol RE Findings (from APK string extraction)

### WiFi architecture — NOT a regular AP

| Finding | Detail |
|---------|--------|
| WiFi type | **WiFi Direct (P2P)**, NOT a standard AP |
| Glasses role | Group Owner (GO) — creates the P2P group |
| Phone role | P2P client |
| Key classes | `WifiP2pManager`, `startGroupOwner`, `WifiDPSwitchPathBTReq` |
| Passphrase | Derived with `PKCS5PBKDF2HMACSHA1` from device secret |
| Port | TCP socket over P2P link — `[Wifi] listen port number: %d` |
| Can skip BT? | **Conditionally** — need passphrase once; if deterministic → skip BT forever |

### Connection paths (4 total)

```
BluetoothConnectionController  ← POWER_MODE_NORMAL
WifiConnectionController        ← POWER_MODE_HIGH  
USBConnectionController         ← wired dev mode
LocalSocketConnectionController ← SmartEyeglassEmulator (UNIX domain sockets)
```

### Local sockets (key finding for macOS bridge)

The emulator uses Android UNIX domain sockets:
- `com.sony.smarteyeglass.MONITOR_SOCKET`
- `EXTRA_SENSOR_LOCAL_SERVER_SOCKET_NAME`
- `EXTRA_CAMERA_VIDEO_SOCKET_NAME`
- `EXTRA_AR_ANIMATION_SOCKET_NAME`

`adb forward tcp:PORT localabstract:SOCKET_NAME` exposes these to macOS TODAY — no BT RE needed.

### NFC

Contains **BT MAC address only** (for pairing bootstrap). NOT WiFi credentials.
Format: NDEF record with BT MAC → phone initiates SPP connection.

### libnativesupport.so exports

- `Java_com_sony_wifi_bttriggeredwifitest_NativeSupport_PKCS5PBKDF2HMACSHA1` — WPA key derivation
- `Java_com_sony_wifi_bttriggeredwifitest_NativeSupport_getIwFreq` — WiFi frequency scan
- SHA1 implementation (standard)

Package `com.sony.wifi.bttriggeredwifitest` = internal test harness for BT-triggered WiFi setup.

---

## macOS / iOS feasibility

| Platform | Transport | Status | Path |
|----------|-----------|--------|------|
| macOS | ADB socket bridge | ✅ **Works now** | `adb forward` → TCP → `GlassesMiddleware.swift` |
| macOS | BT SPP | ✅ After RE | `IOBluetooth.framework` RFCOMM |
| macOS | WiFi P2P | ⚠️ Restricted | `NetworkExtension` — limited API |
| iOS | BT Classic (SPP) | ❌ | Apple blocks Classic BT for 3rd party |
| iOS | via Android bridge | ✅ | Companion app → BLE/WebSocket to iOS |

---

*Log continues below as steps are executed...*

---

## 🎉 DISPLAY RENDERING CONFIRMED — Game of Life on SED-E1

### Working Protocol (from macOS, no Android)

**Handshake sequence:**
1. RX `0x0a` ProtocolVersion (v3)
2. TX `0x71` SettingsStatusRequest
3. RX `0x72` SettingsStatusResponse
4. TX `0x07` VersionRequest
5. RX `0x08` VersionResponse (FW 01.001.15041001)
6. TX `0x85` NewHostApp(0)
7. RX `0x81` FotaStatus (×2)
8. **TX `0xFF` SyncResponse** ← CRITICAL, unblocks command processing
9. User taps touch sensor → RX `0x06` LevelNotification
10. TX `0x30` OpenAppStartRequest
11. TX `0xe0` LayoutInit(x=0, y=0, state=0)
12. TX `0xe7` LayoutPlaceRemoveCommand (image data)
13. RX `0xe8` LayoutPlaceRemoveAck ← **image rendered!**

**Image format (LayoutPlaceRemoveCommand 0xe7):**
- 3 subcommands: PLACE_STATE(0x01) + PLACE_IMGOBJ(0x03) + PLACE_IMAGEDATA(0x07)
- State ID = 0, Object ID = 0
- PLACE_IMGOBJ: x=0, y=0, w=419, h=138
- Image data: 8-bit grayscale (1 byte/pixel), DEFLATE compressed (raw, level 9, wbits=-15)
- imgFormat = 1

**Key discoveries:**
- `0xFF` SyncResponse after FotaStatus is mandatory — without it, glasses ignore all commands
- Touch sensor tap sends LevelNotification (0x06) which activates command processing
- LayoutInit x/y are VIEWPORT SCROLL POSITION, not dimensions (419,138 = off-screen!)
- Display sleeps after ~5s inactivity; continuous frame sends prevent this
- ~2.4 fps over BT SPP (DEFLATE compression: 57KB → 70-300 bytes per frame)
- 126+ frames rendered in Game of Life demo

### Frame rate analysis
- BT SPP MTU: 666 bytes
- Compressed frame: 70-300 bytes (depending on content)
- Round-trip: ~400ms (send + ACK)
- Effective: ~2.4 fps

