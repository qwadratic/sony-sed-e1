# glasses-sdk

Modern Kotlin wrapper for the Sony SmartEyeglass SED-E1.  
Zero Sony boilerplate. No permissions in your app. Connect from anywhere.

---

## Before (Sony SDK, 2015)

```java
// 1. Add to AndroidManifest.xml:
//    <uses-permission android:name="com.sony.smarteyeglass.permission.SMARTEYEGLASS" />
//    <uses-permission android:name="com.sonyericsson.extras.liveware.aef.EXTENSION_PERMISSION" />
//    <service android:name=".ExplorerExtensionService">
//        <intent-filter><action android:name="com.sonyericsson.extras.liveware.aef.EXTENSION" /></intent-filter>
//    </service>
//    <receiver android:name=".ExtensionReceiver">
//        <intent-filter><action android:name="...EXTENSION_REGISTER_REQUEST" /></intent-filter>
//    </receiver>
//    <meta-data android:name="...EXTENSION_KEY" android:value="com.myapp.key" />

// 2. Write ExtensionReceiver (routes intent to service)
// 3. Write ExtensionService (extends ExtensionService, creates control)
// 4. Write RegistrationInformation (declares API versions, display size)
// 5. Write ControlExtension (onStart, onResume, onTouch, onSwipe, onDestroy...)

public class MyControl extends ControlExtension {
    private final SmartEyeglassControlUtils utils;

    public MyControl(Context ctx, String hostPkg) {
        super(ctx, hostPkg);
        utils = new SmartEyeglassControlUtils(hostPkg, new SmartEyeglassEventListener() {
            @Override public void onCameraReceived(CameraEvent e) { ... }
        });
        utils.setRequiredApiVersion(1);
        utils.activate(ctx);
    }

    @Override public void onResume() {
        Bitmap bmp = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        c.drawColor(Color.BLACK);
        Paint p = new Paint();
        p.setColor(Color.WHITE);
        p.setTextSize(24);
        c.drawText("Hello", 8, 30, p);
        utils.showBitmap(bmp);
    }

    @Override public void onTouch(ControlTouchEvent event) { ... }
    @Override public void onSwipe(int direction) { ... }
    @Override public void onDestroy() { utils.deactivate(); }
}
// + ~200 more lines across 5 files
```

## After (glasses-sdk)

```kotlin
// 1. Add to build.gradle:
//    implementation 'dev.glasses:glasses-sdk:1.0.0'
// That's it. No manifest changes. No permissions. No boilerplate.

class MyActivity : AppCompatActivity() {
    private val glasses by lazy { Glasses.get(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        lifecycleScope.launch {
            // Observe connection
            glasses.connectionState.collect { state ->
                when (state) {
                    ConnectionState.CONNECTED -> onGlassesConnected()
                    else -> {}
                }
            }
        }

        lifecycleScope.launch {
            // Handle input
            glasses.input.events.collect { event ->
                when (event) {
                    is InputEvent.Tap -> if (event.action == TapAction.RELEASE) onTap()
                    is InputEvent.Swipe -> navigate(event.direction)
                    else -> {}
                }
            }
        }
    }

    private fun onGlassesConnected() {
        glasses.display.showText("Hello!", "SED-E1 connected")

        // Or draw anything:
        val bmp = glasses.display.blank()
        Canvas(bmp).also { c ->
            Paint().apply { color = Color.WHITE; textSize = 22f }
                .also { c.drawText("Custom render", 8f, 30f, it) }
        }
        glasses.display.show(bmp)
    }

    private fun onTap() {
        // Start camera stream
        lifecycleScope.launch {
            glasses.camera.startStream()
            glasses.camera.frames.collect { frame ->
                // frame.jpegData — send to vision API, display thumbnail, etc.
                glasses.display.showText(
                    "Frame #${frame.frameId}",
                    "${frame.jpegData.size} bytes"
                )
            }
        }
    }

    private fun navigate(dir: SwipeDirection) {
        // Handle navigation
    }
}
```

---

## Sensor example

```kotlin
lifecycleScope.launch {
    glasses.sensors.accelerometer.collect { (x, y, z) ->
        glasses.display.showText(
            "Accel",
            "x=${x.format(2)} y=${y.format(2)}",
            "z=${z.format(2)}"
        )
    }
}
```

---

## What the SDK handles automatically

| Task | Old SDK | glasses-sdk |
|------|---------|-------------|
| Manifest permissions | Manual (2 permissions) | Built into SDK manifest ✓ |
| Service + Receiver | Manual (2 classes) | Built into SDK ✓ |
| Registration with Smart Connect | Manual (RegistrationInformation, RegistrationHelper) | Auto on install ✓ |
| Re-registration on reconnect | Manual (ACCESSORY_CONNECTION handler) | Auto ✓ |
| Race condition (device not registered yet) | Manual retry | Auto ✓ |
| Bitmap → PNG → Intent encoding | Manual | `display.show(bitmap)` ✓ |
| Event routing | Manual per-demo | `input.events` Flow ✓ |
| Thread safety | Manual Handler posts | Coroutines ✓ |

---

## Requirements

- **Your app**: minSdk 21, any language (Kotlin/Java)
- **On device**: Smart Connect + SmartEyeglass APKs installed
- **Glasses**: SED-E1 paired via Bluetooth

## Limitations (inherited from hardware)

- Display: 419×138 pixels, green monochrome (white → green)
- Camera: QVGA JPEG only, no audio
- No USB/WiFi direct connection — Bluetooth bridge via `com.sony.smarteyeglass` is required
- The emulator path requires real Bluetooth hardware (no Android emulator support)
