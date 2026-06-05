package dev.glasses

import android.content.Context
import android.graphics.Bitmap
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Main entry point. One instance per app.
 *
 * Usage:
 *   val glasses = Glasses.get(context)
 *   glasses.connect { state -> ... }          // observe connection state
 *   glasses.display.show(bitmap)              // push a frame
 *   glasses.input.events.collect { ... }      // touch/swipe events
 *   glasses.sensors.accelerometer.collect { } // sensor data
 *   glasses.camera.startStream { frame -> }   // camera frames
 */
class Glasses private constructor(private val ctx: Context) {

    val display: Display = Display(ctx)
    val input: Input = Input()
    val sensors: Sensors = Sensors(ctx)
    val camera: Camera = Camera(ctx)

    /** Observable connection state. */
    val connectionState: SharedFlow<ConnectionState> get() = _bridge.connectionState

    /** True if glasses are currently connected. */
    val isConnected: Boolean get() = _bridge.isConnected

    private val _bridge: GlassesBridge = GlassesBridge.getInstance(ctx)

    init {
        display.bind(_bridge)
        input.bind(_bridge)
        sensors.bind(_bridge)
        camera.bind(_bridge)
    }

    companion object {
        @Volatile private var instance: Glasses? = null

        fun get(context: Context): Glasses =
            instance ?: synchronized(this) {
                instance ?: Glasses(context.applicationContext).also { instance = it }
            }
    }
}

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR
}
