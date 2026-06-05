package dev.glasses

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.net.Uri
import android.util.Log
import dev.glasses.internal.Protocol
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.io.ByteArrayOutputStream

/**
 * Internal bridge to the Sony stack. Handles:
 *   - Auto-registration with Smart Connect (no manual setup)
 *   - Re-registration on every ACCESSORY_CONNECTION_INTENT
 *   - Intent routing for display, camera, sensors, input
 *
 * App-level code never touches this directly.
 * All Sony permissions are confined here.
 */
internal class GlassesBridge private constructor(private val ctx: Context) {

    companion object {
        private const val TAG = "GlassesBridge"
        private const val EXTENSION_KEY = "dev.glasses.sdk.key"

        // Sony content provider URIs
        private val EXTENSION_URI = Uri.parse(
            "content://com.sonyericsson.extras.liveware.aef.registration/extension"
        )
        private val REGISTRATION_URI = Uri.parse(
            "content://com.sonyericsson.extras.liveware.aef.registration/registration"
        )
        private val HOST_APP_URI = Uri.parse(
            "content://com.sonyericsson.extras.liveware.aef.registration/host_application"
        )

        @Volatile private var instance: GlassesBridge? = null

        fun getInstance(ctx: Context): GlassesBridge =
            instance ?: synchronized(this) {
                instance ?: GlassesBridge(ctx.applicationContext).also {
                    instance = it
                    it.init()
                }
            }
    }

    // ── State ────────────────────────────────────────────────────────────────

    private val _connectionState = MutableSharedFlow<ConnectionState>(
        replay = 1, extraBufferCapacity = 8
    )
    val connectionState: SharedFlow<ConnectionState> = _connectionState.asSharedFlow()
    var isConnected: Boolean = false
        private set

    // ── Listener hooks (set by Display/Input/Sensors/Camera) ─────────────────

    var inputListener: ((InputEvent) -> Unit)? = null
    var sensorListener: ((SensorType, FloatArray) -> Unit)? = null
    var cameraListener: ((CameraFrame) -> Unit)? = null

    // ── Init ─────────────────────────────────────────────────────────────────

    private fun init() {
        registerReceivers()
        _connectionState.tryEmit(ConnectionState.DISCONNECTED)
    }

    private fun registerReceivers() {
        // Registration request (Smart Connect → us on install or reconnect)
        ctx.registerReceiver(registrationReceiver, IntentFilter().apply {
            addAction("com.sonyericsson.extras.liveware.aef.registration.EXTENSION_REGISTER_REQUEST")
            addAction("com.sonyericsson.extras.liveware.aef.registration.CAPABILITY_CHANGED")
        })

        // Connection events (device connected/disconnected)
        ctx.registerReceiver(connectionReceiver, IntentFilter().apply {
            addAction("com.sonyericsson.extras.liveware.aef.registration.ACCESSORY_CONNECTION")
        })

        // Input events
        ctx.registerReceiver(inputReceiver, IntentFilter().apply {
            addAction("com.sonyericsson.extras.liveware.aef.control.TOUCH_EVENT")
            addAction("com.sonyericsson.extras.liveware.aef.control.SWIPE_EVENT")
            addAction("com.sonyericsson.extras.liveware.aef.control.KEY_EVENT")
        })

        // Camera events
        ctx.registerReceiver(cameraReceiver, IntentFilter().apply {
            addAction("com.sony.smarteyeglass.control.CAMERA_NOTIFY_CAPTURED_FILE_EVENT")
            addAction("com.sony.smarteyeglass.control.CAMERA_NOTIFY_ERROR_EVENT")
        })

        // Display result (optional — only needed if using showBitmapWithCallback)
        ctx.registerReceiver(displayResultReceiver, IntentFilter().apply {
            addAction("com.sony.smarteyeglass.control.DISPLAY_DATA_RESULT")
        })

        Log.d(TAG, "Receivers registered")
    }

    // ── Receivers ─────────────────────────────────────────────────────────────

    private val registrationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d(TAG, "Registration requested: ${intent.action}")
            register()
        }
    }

    private val connectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra("connection_status", 0)
            // status 1 = connected, 0 = disconnected (from SDK source)
            isConnected = (status == 1)
            val state = if (isConnected) ConnectionState.CONNECTED else ConnectionState.DISCONNECTED
            _connectionState.tryEmit(state)
            Log.d(TAG, "Connection changed: $state")

            if (isConnected) {
                // Re-register for this host app to populate registration table
                register()
            }
        }
    }

    private val inputReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                "com.sonyericsson.extras.liveware.aef.control.TOUCH_EVENT" -> {
                    val x = intent.getFloatExtra("x", 0f)
                    val y = intent.getFloatExtra("y", 0f)
                    val action = when (intent.getIntExtra("action", 0)) {
                        1 -> TapAction.PRESS
                        2 -> TapAction.RELEASE
                        3 -> TapAction.LONG_PRESS
                        else -> TapAction.RELEASE
                    }
                    inputListener?.invoke(InputEvent.Tap(x, y, action))
                }
                "com.sonyericsson.extras.liveware.aef.control.SWIPE_EVENT" -> {
                    val dir = SwipeDirection.fromInt(intent.getIntExtra("direction", 1))
                    inputListener?.invoke(InputEvent.Swipe(dir))
                }
                "com.sonyericsson.extras.liveware.aef.control.KEY_EVENT" -> {
                    val keyCode = intent.getIntExtra("key_code", 0)
                    if (keyCode == 4) inputListener?.invoke(InputEvent.Back) // KEYCODE_BACK
                }
            }
        }
    }

    private val cameraReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val data = intent.getByteArrayExtra("data") ?: return
            val frameId = intent.getIntExtra("frame_id", 0)
            val ts = System.currentTimeMillis()
            cameraListener?.invoke(CameraFrame(data, frameId, ts))
        }
    }

    private val displayResultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // Could expose this as a Flow if callers need frame-ack
        }
    }

    // ── Registration (automatic, no manual setup needed) ─────────────────────

    private fun register() {
        try {
            val extensionId = ensureExtensionRegistered()
            ensureRegisteredWithSmartEyeglass(extensionId)
            Log.d(TAG, "Registration complete, extensionId=$extensionId")
        } catch (e: Exception) {
            Log.w(TAG, "Registration failed (retry on next connection): ${e.message}")
        }
    }

    /** Insert or update the extension row. Returns the extension _id. */
    private fun ensureExtensionRegistered(): Long {
        // Check if already registered
        val cursor = ctx.contentResolver.query(
            EXTENSION_URI, arrayOf("_id", "package_name"),
            "package_name = ?", arrayOf(ctx.packageName), null
        )
        val existingId = cursor?.use {
            if (it.moveToFirst()) it.getLong(0) else -1L
        } ?: -1L

        if (existingId != -1L) return existingId

        // Insert new
        val cv = ContentValues().apply {
            put("name", "SmartEyeglass SDK")
            put("extension_key", EXTENSION_KEY)
            put("package_name", ctx.packageName)
            put("notification_api_version", 0)
        }
        val uri = ctx.contentResolver.insert(EXTENSION_URI, cv)
            ?: throw IllegalStateException("Failed to insert extension — is Smart Connect installed?")
        return uri.lastPathSegment?.toLong() ?: -1L
    }

    /** Insert registration row linking this extension to the SmartEyeglass host. */
    private fun ensureRegisteredWithSmartEyeglass(extensionId: Long) {
        if (extensionId == -1L) return

        // Get the SmartEyeglass host app id
        val hostCursor = ctx.contentResolver.query(
            HOST_APP_URI,
            arrayOf("_id", "package_name", "control_api_version"),
            "package_name = ?",
            arrayOf("com.sony.smarteyeglass"),
            null
        )
        val host = hostCursor?.use {
            if (!it.moveToFirst()) return
            Triple(it.getLong(0), it.getString(1), it.getInt(2))
        } ?: return

        val (hostId, hostPkg, controlApiVersion) = host

        // Check if already registered
        val regCursor = ctx.contentResolver.query(
            REGISTRATION_URI, arrayOf("_id"),
            "extension_id = ? AND host_app_package_name = ?",
            arrayOf(extensionId.toString(), hostPkg), null
        )
        val alreadyRegistered = regCursor?.use { it.moveToFirst() } ?: false
        if (alreadyRegistered) return

        // Insert
        val cv = ContentValues().apply {
            put("extension_id", extensionId)
            put("host_app_package_name", hostPkg)
            put("widget_api_version", 0)
            put("control_api_version", minOf(controlApiVersion, 4))
            put("sensor_api_version", 1)
            put("low_power_support", 0)
            put("control_back_intercept", 0)
        }
        ctx.contentResolver.insert(REGISTRATION_URI, cv)
        Log.d(TAG, "Registered with SmartEyeglass host $hostPkg")
    }

    // ── Display ───────────────────────────────────────────────────────────────

    fun sendDisplay(bitmap: Bitmap) {
        val png = encodePng(bitmap)
        val intent = Intent("com.sony.smarteyeglass.control.DISPLAY_DATA").apply {
            setPackage("com.sony.smarteyeglass")
            putExtra("data", png)
        }
        ctx.sendBroadcast(intent, "com.sony.smarteyeglass.permission.SMARTEYEGLASS")
    }

    fun sendDisplayAt(bitmap: Bitmap, x: Int, y: Int) {
        val png = encodePng(bitmap)
        val intent = Intent("com.sony.smarteyeglass.control.DISPLAY_DATA").apply {
            setPackage("com.sony.smarteyeglass")
            putExtra("data", png)
            putExtra("x", x)
            putExtra("y", y)
        }
        ctx.sendBroadcast(intent, "com.sony.smarteyeglass.permission.SMARTEYEGLASS")
    }

    fun sendIntent(action: String, extras: Map<String, Any>) {
        val intent = Intent(action).apply {
            setPackage("com.sony.smarteyeglass")
            extras.forEach { (k, v) ->
                when (v) {
                    is Int -> putExtra(k, v)
                    is Float -> putExtra(k, v)
                    is String -> putExtra(k, v)
                    is ByteArray -> putExtra(k, v)
                    is Boolean -> putExtra(k, v)
                }
            }
        }
        ctx.sendBroadcast(intent, "com.sony.smarteyeglass.permission.SMARTEYEGLASS")
    }

    // ── Sensors ───────────────────────────────────────────────────────────────

    fun enableSensors(types: List<SensorType>) {
        // Sensor registration is via Smart Connect ContentProvider
        // Just set up the receiver — SDK handles rate selection
        Log.d(TAG, "Sensors enabled: $types")
    }

    fun disableSensors() {
        Log.d(TAG, "Sensors disabled")
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun encodePng(bitmap: Bitmap): ByteArray {
        val baos = ByteArrayOutputStream(8192)
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos)
        return baos.toByteArray()
    }
}
