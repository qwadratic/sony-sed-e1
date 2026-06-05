# Sony SmartEyeglass SED-E1 — Developer Exploration Kit

## What This Is

A complete setup and API exploration project for the **Sony SmartEyeglass SED-E1 Developer Edition** — binocular AR glasses from 2015 with a 419×138 green monochrome see-through display, camera, full sensor suite, mic, and speaker.

Sony discontinued the product and shut down the developer portal. Everything needed to build for these glasses survives on third-party mirrors and GitHub. This project sets up the development environment, then builds a single **API Explorer** app that demonstrates every glasses capability through an interactive menu — so developers can see what's possible and build their own applications on top.

**The entire development and testing flow runs on Mac in an emulator. No glasses, no Android phone, no Bluetooth required.** A physical device setup guide is included at the end for when you're ready to run on real hardware.

---

## Phase 1: Environment Setup (Emulator-Only, Mac)

### Step 1: Clone the SDK

```bash
git clone https://github.com/kaustubhcs/Sony.git
```

The SDK lives at: `Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/`

**Immediately inspect the actual directory structure:**
```bash
find Sony/sony_smarteyeglass_sdk -type f -name "*.jar" -o -name "*.aar" -o -name "*.apk" | head -30
ls Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/
ls Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/apks/
ls Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/samples/
```

Document what you find — the exact jar/project names, sample names, and APK names. The rest of this spec references them generically because the internal layout may vary.

### Step 2: Download companion APKs

You need two Sony apps that the extension framework depends on. Download these from APKMirror before starting the Android project:

1. **Smart Connect** (`com.sonyericsson.extras.liveware`) — the Sony wearable framework host  
   Download page: `https://www.apkmirror.com/apk/sony-mobile-communications/smart-connect/`  
   Get a 2015-2017 era version (5.7.16.312 through 5.7.20.432).

2. **SmartEyeglass host** (`com.sony.smarteyeglass`) — the device-specific bridge  
   Download page: `https://www.apkmirror.com/apk/sony-semiconductor-solutions-corporation/smarteyeglass/`  
   Get version **1.3.17052901** (final build, 2017).  
   SHA-256: `57000a877a4622916067add7f37350038653d5049d299fd5e408c1181d569522`

3. **SmartEyeglass Emulator** — bundled in the SDK:  
   `Sony/sony_smarteyeglass_sdk/sony_smarteyeglass_sdk/apks/SmartEyeglassEmulator.apk`

If APKMirror shows a takedown notice, try APKPure:
- `https://m.apkpure.com/smart-connect/com.sonyericsson.extras.liveware`
- `https://m.apkpure.com/smarteyeglass/com.sony.smarteyeglass`

### Step 3: Create Android Studio AVD

- Device: Nexus 5 (or any ~5" phone profile)
- System image: **API 19 (KitKat), x86** — this matches the SDK target exactly
- RAM: 2 GB is sufficient
- Enable keyboard input and host GPU

### Step 4: Install APKs in the emulator

**Order matters.** Smart Connect must be first — it's the framework everything else plugs into.

```bash
adb install SmartConnect-5.7.20.432.apk
adb install SmartEyeglass-1.3.17052901.apk
adb install SmartEyeglassEmulator.apk
```

### Step 5: Verify the emulator works

1. Open the **SmartEyeglassEmulator** app in the AVD
2. You should see a black rectangle (the glasses display simulation) with a green area
3. If the green area is blank — force-stop and restart the emulator app
4. Swipe left/right on the green area to see any pre-installed sample extensions
5. If you also installed sample APKs from the SDK (`apks/samples/HelloLayouts.apk` etc.), they should appear here

**This is your development loop:** write code → build → `adb install` → switch to emulator → swipe to your app → tap touch sensor → see result on green display.

---

## Phase 2: SmartExtension Architecture (understand before coding)

Every SmartEyeglass app is a standard Android app that registers as a Sony "Smart Extension." It runs entirely on the phone — the glasses are a remote display/sensor peripheral.

### Three mandatory components

**1. ExtensionReceiver** — a BroadcastReceiver that tells Smart Connect your extension exists.

**2. ExtensionService** — an Android Service that Smart Connect binds to. Its job: create a ControlExtension instance when the user launches your app from the glasses menu.

**3. ControlExtension** — your main class. Receives lifecycle callbacks (`onStart`, `onStop`, `onResume`, `onPause`), input events (`onTouch`, `onSwipe`), and sensor/camera data. You push content to the glasses display from here.

### The display push model

You create a standard Android `Bitmap` (419×138, `ARGB_8888`), draw on it using `Canvas` + `Paint`, and push it to the glasses via `SmartEyeglassControlUtils.showBitmap()` (or equivalent — verify the exact method name in the SDK Javadoc in `docs/`).

The SDK converts your bitmap to 8-bit monochrome green internally. Draw **white on black** for maximum contrast.

### Key SDK classes

- `SmartEyeglassControlUtils` — the main utility. Call `activate(context)` to start, `deactivate()` to stop. Methods for display, camera, sensors.
- `SmartEyeglassControl.Intents` — constants for display modes, camera modes, sensor types.
- `SmartEyeglassEventListener` — callback interface for camera frames, sensor data, voice input.
- `ControlExtension` (from SmartExtensionUtils) — base class you extend.
- `RegistrationInformation` (from SmartExtensionUtils) — declares capabilities and API versions.

**Study the `HelloLayouts` sample first** — it's the minimal working extension. Then study `HelloSensors` and the camera/AR samples for sensor and camera APIs.

### AndroidManifest template

```xml
<uses-permission android:name="com.sony.smarteyeglass.permission.SMARTEYEGLASS" />
<uses-permission android:name="com.sonyericsson.extras.liveware.aef.EXTENSION_PERMISSION" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<application ...>
    <service android:name=".ExplorerExtensionService">
        <intent-filter>
            <action android:name="com.sonyericsson.extras.liveware.aef.EXTENSION" />
        </intent-filter>
    </service>
    
    <receiver android:name=".ExtensionReceiver">
        <intent-filter>
            <action android:name="com.sonyericsson.extras.liveware.aef.registration.EXTENSION_REGISTER_REQUEST" />
        </intent-filter>
    </receiver>
    
    <meta-data
        android:name="com.sonyericsson.extras.liveware.aef.registration.EXTENSION_KEY"
        android:value="com.smarteyeglass.explorer.key" />
</application>
```

---

## Phase 3: Build the API Explorer App

A single extension app with an interactive menu on the glasses display. Each menu item demonstrates a different hardware capability. Navigate by swiping left/right, select by tapping the touch sensor.

### Display: 419 × 138 px, 8-bit monochrome green

Design every screen for this canvas:
- ~25-30 characters per line at font size 22-24 (monospace)
- 4-5 visible lines
- White on black (SDK converts to green)
- `setAntiAlias(false)` — crisp pixels beat blurry on 8-bit mono
- **Target API 19 — no Java 8 features, no lambdas, no streams.** Use anonymous inner classes.

### Main menu structure

```
┌─────────────────────────────────┐
│  SmartEyeglass Explorer    1/7  │
│                                 │
│  ▸ Display Demos                │
│                                 │
│  [tap] select  [swipe] next     │
└─────────────────────────────────┘
```

Swiping cycles through menu items. Tapping enters the selected demo. Back button returns to menu.

### Demo 1: Display — Text Rendering

Push multi-line text to the display. Show character limits, font sizes, and the scrolling behavior. Cycle through font sizes (16, 20, 24, 28) on each tap to show legibility tradeoffs.

```java
// Core display push pattern — use throughout all demos
Bitmap bmp = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
Canvas canvas = new Canvas(bmp);
canvas.drawColor(Color.BLACK);

Paint paint = new Paint();
paint.setColor(Color.WHITE);
paint.setTextSize(24);
paint.setTypeface(Typeface.MONOSPACE);
paint.setAntiAlias(false);

canvas.drawText("Line 1: Hello SmartEyeglass", 8, 30, paint);
canvas.drawText("Line 2: 419×138 green mono", 8, 58, paint);
canvas.drawText("Line 3: Font size 24px", 8, 86, paint);
canvas.drawText("Line 4: Tap to cycle size", 8, 114, paint);

utils.showBitmap(bmp);
// verify exact method name — may be showBitmap(Bitmap), 
// sendBitmap(), or updateDisplay()
```

### Demo 2: Display — Animations / Real-Time Mode

Switch to real-time rendering mode and push frames in a loop. Show a simple animation: a horizontal line scanning top-to-bottom, or a bouncing dot. This demonstrates the continuous bitmap streaming capability (~15 fps).

```java
// Switch to real-time mode
// Check SmartEyeglassControl.Intents for the exact constant:
// likely MODE_NORMAL vs MODE_AR or a setRenderMode() call
utils.setRenderMode(SmartEyeglassControl.Intents.MODE_NORMAL);

// Timer-based frame push
Timer timer = new Timer();
timer.scheduleAtFixedRate(new TimerTask() {
    int y = 0;
    public void run() {
        Bitmap bmp = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bmp);
        canvas.drawColor(Color.BLACK);
        canvas.drawLine(0, y, 419, y, linePaint);
        y = (y + 2) % 138;
        utils.showBitmap(bmp);
    }
}, 0, 66); // ~15 fps
```

### Demo 3: Display — Graphics & Shapes

Draw geometric primitives: rectangles, circles, lines, arcs. Show what the monochrome display can render. Include a simple wireframe 3D cube (rotating on timer) to demonstrate the aesthetic possibilities.

### Demo 4: Touch & Input

Display current touch state in real time. Show swipe direction, tap events, and button presses as they happen. Display an event log that scrolls as new input arrives.

```java
@Override
public void onTouch(ControlTouchEvent event) {
    String action = "";
    switch (event.getAction()) {
        case Control.TapActions.SINGLE_TAP: action = "TAP"; break;
        case Control.TapActions.LONG_PRESS: action = "LONG"; break;
        // check SDK for exact swipe constants
    }
    addEventToLog("Touch: " + action + " x=" + event.getX());
    renderEventLog();
}

@Override
public void onSwipe(int direction) {
    // direction constants from Control.Intents
    addEventToLog("Swipe: " + directionName(direction));
    renderEventLog();
}
```

### Demo 5: Sensors — Live Readout

Register for accelerometer, gyroscope, and compass data. Display live numeric readouts updating in real time. Show all three sensor readings simultaneously:

```
┌─────────────────────────────────┐
│  Sensors (live)                 │
│  Accel: x=0.12 y=9.81 z=0.34   │
│  Gyro:  x=0.01 y=-0.02 z=0.00  │
│  Compass: 247° WSW              │
│  Bright: 412 lux                │
└─────────────────────────────────┘
```

Use `SmartEyeglassControlUtils` sensor registration methods and `SmartEyeglassEventListener` callbacks. Check the `HelloSensors` sample for the exact API.

### Demo 6: Camera — Still Capture

Trigger a camera capture on tap. Display a text confirmation ("Captured!") and the image dimensions. The camera returns JPEG data via callback — log the byte size to show it worked.

On emulator: the SDK camera uses the host machine's webcam (if available) or returns test data. Check SDK behavior.

```java
// Trigger capture
utils.requestCameraCapture(); 
// or equivalent — check SmartEyeglassControlUtils camera methods

// In SmartEyeglassEventListener:
@Override
public void onCameraReceived(CameraEvent event) {
    byte[] jpegData = event.getData();
    int size = jpegData.length;
    drawText("Captured: " + size + " bytes");
}
```

### Demo 7: Camera — JPEG Video Stream

Start the continuous JPEG stream (QVGA ~320×240, no audio). Show frame count and estimated FPS on the display. This demonstrates the real-time vision pipeline capability — a developer could feed these frames to a vision model.

```java
// Start JPEG stream
utils.startCamera(); // or requestCameraStream() — verify in Javadoc

// In listener:
@Override 
public void onCameraReceived(CameraEvent event) {
    frameCount++;
    long now = System.currentTimeMillis();
    float fps = frameCount / ((now - startTime) / 1000f);
    drawText("Stream: frame #" + frameCount + " | " + String.format("%.1f", fps) + " fps");
    // The JPEG bytes are in event.getData() — 
    // a developer would send these to a vision API
}
```

### Demo 8 (if AR API exists in SDK): AR Coordinate Rendering

The SDK included an AR rendering API with cylindrical and world coordinate systems. If the `SampleARCylindricalExtension` sample exists, replicate its approach: place a simple marker at a fixed heading and show how it moves as you rotate the glasses (gyro/compass-driven).

This demo may only be meaningful on real hardware — on emulator, mock the sensor data.

---

## Phase 4: Project Structure

```
smarteyeglass-explorer/
├── build.gradle                          # minSdk 19, targetSdk 19, Java
├── libs/                                 # populated from SDK — inspect actual names
│   └── (SmartExtensionAPI / Utils / EyeglassAPI jars or source projects)
├── src/main/
│   ├── AndroidManifest.xml
│   └── java/com/explorer/
│       ├── ExplorerRegistrationInformation.java   # extension metadata
│       ├── ExplorerExtensionService.java          # service, creates control
│       ├── ExplorerControl.java                   # main menu + demo router
│       ├── ExtensionReceiver.java                 # broadcast receiver
│       ├── demos/
│       │   ├── TextDemo.java                      # Demo 1: text rendering
│       │   ├── AnimationDemo.java                 # Demo 2: real-time frames
│       │   ├── GraphicsDemo.java                  # Demo 3: shapes & wireframe
│       │   ├── TouchDemo.java                     # Demo 4: input event log
│       │   ├── SensorDemo.java                    # Demo 5: live sensor readout
│       │   ├── CameraCaptureDemo.java             # Demo 6: still capture
│       │   ├── CameraStreamDemo.java              # Demo 7: JPEG stream
│       │   └── ARDemo.java                        # Demo 8: AR coordinates (if available)
│       └── util/
│           ├── DisplayRenderer.java               # shared bitmap/canvas helpers
│           └── MenuRenderer.java                  # main menu drawing logic
└── src/main/res/
    ├── drawable/
    │   └── ic_extension.png                       # 48×48 icon
    └── values/
        └── strings.xml
```

### DisplayRenderer — shared utility

```java
public class DisplayRenderer {
    public static final int WIDTH = 419;
    public static final int HEIGHT = 138;
    
    private static Paint defaultPaint;
    
    static {
        defaultPaint = new Paint();
        defaultPaint.setColor(Color.WHITE);
        defaultPaint.setTextSize(22);
        defaultPaint.setTypeface(Typeface.MONOSPACE);
        defaultPaint.setAntiAlias(false);
    }
    
    public static Bitmap createFrame() {
        Bitmap bmp = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
        new Canvas(bmp).drawColor(Color.BLACK);
        return bmp;
    }
    
    public static Canvas drawHeader(Bitmap bmp, String title, String pageInfo) {
        Canvas c = new Canvas(bmp);
        Paint header = new Paint(defaultPaint);
        header.setTextSize(18);
        c.drawText(title, 8, 18, header);
        float w = header.measureText(pageInfo);
        c.drawText(pageInfo, WIDTH - w - 8, 18, header);
        c.drawLine(0, 24, WIDTH, 24, header);
        return c;
    }
    
    public static void drawBody(Canvas c, String[] lines, int startY) {
        int y = startY;
        for (String line : lines) {
            if (line == null) continue;
            c.drawText(line, 8, y, defaultPaint);
            y += 28;
        }
    }
    
    public static void drawFooter(Canvas c, String hint) {
        Paint footer = new Paint(defaultPaint);
        footer.setTextSize(14);
        footer.setColor(Color.GRAY);
        c.drawText(hint, 8, HEIGHT - 6, footer);
    }
}
```

### Demo base pattern

Each demo class follows the same interface:

```java
public abstract class BaseDemo {
    protected SmartEyeglassControlUtils utils;
    protected Context context;
    
    public BaseDemo(SmartEyeglassControlUtils utils, Context context) {
        this.utils = utils;
        this.context = context;
    }
    
    public abstract void onEnter();     // called when user selects this demo
    public abstract void onExit();      // called when user presses back
    public abstract void onTap();       // tap inside the demo
    public abstract void onSwipe(int direction);  // swipe inside the demo
    
    protected void pushFrame(Bitmap bmp) {
        utils.showBitmap(bmp); // verify exact method
    }
}
```

---

## Phase 5: Build & Test Checklist

Work through these in order. Do not skip ahead.

- [ ] Clone SDK, inspect contents, document actual jar/project names
- [ ] Create Android Studio project (API 19, Java, no Kotlin)
- [ ] Import SDK library into project (follow HelloLayouts sample's approach)
- [ ] Implement the three framework components (Receiver, Service, RegistrationInfo)
- [ ] Build a minimal ControlExtension that pushes one hardcoded bitmap
- [ ] Install in AVD + SmartEyeglassEmulator, verify green text appears
- [ ] **STOP and verify everything above works before continuing**
- [ ] Build DisplayRenderer utility
- [ ] Build MenuRenderer with swipe navigation
- [ ] Implement Demo 1 (text rendering, font cycling)
- [ ] Implement Demo 2 (animation loop / real-time mode)
- [ ] Implement Demo 3 (graphics primitives)
- [ ] Implement Demo 4 (touch event log)
- [ ] Implement Demo 5 (sensor readout — may need mock data in emulator)
- [ ] Implement Demo 6 (camera still)
- [ ] Implement Demo 7 (camera stream)
- [ ] Implement Demo 8 (AR — only if SDK has the API)
- [ ] Full test pass in emulator

---

## Critical Constraints

1. **API level 19.** No Java 8 lambdas, no streams, no try-with-resources. Use anonymous inner classes everywhere. Do not set targetSdk above 19.

2. **SDK method names are approximate.** The code samples above use likely method names (`showBitmap`, `startCamera`, `requestCameraCapture`, `setRenderMode`). The actual method signatures MUST be verified by reading the SDK Javadoc in the `docs/` folder and inspecting the sample source code. **This is your first task after cloning the repo.**

3. **Render mode constants.** The exact constants for switching between normal/card mode and real-time/continuous mode live in `SmartEyeglassControl.Intents`. Find and document them before implementing Demo 2.

4. **Threading.** Bitmap push to glasses must happen on the extension's handler thread. Sensor/camera callbacks may arrive on different threads. Use `Handler` to post updates.

5. **Emulator limitations.** The SmartEyeglassEmulator simulates the green display and touch sensor. Camera and sensor data may not be available in emulator — implement mock/fallback data for demos 5-8 so they always show something meaningful.

6. **Bitmap memory.** The 419×138 ARGB_8888 bitmap is tiny (~231 KB), but if you're pushing at 15 fps, reuse the Bitmap object instead of allocating new ones each frame. Use `Canvas` on the same `Bitmap` instance, call `canvas.drawColor(Color.BLACK)` to clear between frames.

7. **Smart Connect dependency.** If Smart Connect crashes or doesn't detect your extension: uninstall all three apps, reinstall in order (Smart Connect → SmartEyeglass → your APK), restart the emulator.

---

## Appendix: Real Hardware Setup (Android Phone + Physical Glasses)

Follow this only after the emulator flow is fully working.

### What you need

- Android phone running **4.4 to 5.1** (KitKat/Lollipop). Cheap used options: Samsung Galaxy S4/S5, Nexus 5, Sony Xperia Z1/Z2/Z3. Modern Android (6+) breaks the Sony stack — runtime permissions, background service limits, and Bluetooth API changes cause silent failures.
- USB cable for `adb install`
- Micro-USB cable to charge the glasses controller

### Glasses hardware

Two pieces connected by a 63 cm cable:
- **Eyewear** (77 g) — the display lenses, nose pad
- **Controller** (45 g) — battery, speaker, mic, touch sensor, TALK button, BACK button, micro-USB charge port, camera shutter button, NFC tag, clip for clothing

### Power on

1. Charge the controller via micro-USB for **1-2 hours** (mandatory if device has been stored — battery will be completely dead)
2. Look for charging indicator LED on the controller
3. **Slide and HOLD the POWER switch toward ON/OFF for 4+ seconds** — a brief slide only toggles the display, not the power
4. If nothing happens after charging: disconnect and reconnect the USB cable, then retry the 4-second hold
5. When powered on, text appears on the lenses (visible only when wearing the glasses and looking through them — the holographic waveguide display is not visible from the side)

### Pair with phone

1. Install Smart Connect → SmartEyeglass (same APKs as emulator, same order)
2. Power on the glasses
3. **NFC path:** touch phone's NFC area to controller's rear N-mark, hold until `[SONY]` appears on lenses
4. **Manual path:** turn on phone Bluetooth → glasses show pairing prompt → tap touch sensor on controller → select "SmartEyeglass" in phone Bluetooth list → confirm matching passkey → tap touch sensor → tap "Pairing" on phone
5. Connection-complete screen appears for ~5 seconds

### Screen alignment check

After first pairing, the glasses show an alignment test: three vertical lines should intersect one horizontal line when you look straight ahead. If misaligned, adjust the nose pad (spare small pad included in box).

### Deploy your app

```bash
adb install -r app-debug.apk
```

Open Smart Connect on the phone → your extension appears in the list → launch it → it runs on the glasses.

### Troubleshooting

- **Glasses won't power on:** charge longer (2+ hours), try a different micro-USB cable, check that the cable connects to the controller (not the eyewear)
- **Pairing fails:** ensure Smart Connect is installed BEFORE attempting Bluetooth pairing; restart both devices; remove any existing "SmartEyeglass" Bluetooth pairing and re-pair
- **Extension not visible in Smart Connect:** uninstall and reinstall all apps in order; check that your manifest has the correct intent-filter and meta-data
- **Connection drops during use:** battery optimization on the phone may be killing Smart Connect in background — disable battery optimization for both Sony apps in phone settings
- **Display shows nothing but glasses are paired:** your extension may have crashed — check `adb logcat` filtered to your package name

### If you want to attempt modern Android (6+)

This is experimental and may not work. Try before buying an old phone:

```bash
# Grant permissions that the old apps can't request at runtime
adb shell pm grant com.sony.smarteyeglass android.permission.BLUETOOTH_CONNECT
adb shell pm grant com.sony.smarteyeglass android.permission.BLUETOOTH_SCAN
adb shell pm grant com.sonyericsson.extras.liveware android.permission.BLUETOOTH_CONNECT
adb shell pm grant com.sonyericsson.extras.liveware android.permission.BLUETOOTH_SCAN
```

Disable battery optimization for both Sony apps. If pairing succeeds but the connection is unstable, the background service restrictions on Android 8+ are likely killing the Bluetooth bridge — fall back to a KitKat/Lollipop device.
