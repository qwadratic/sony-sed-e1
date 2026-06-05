package dev.glasses

import android.content.Context
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import dev.glasses.internal.Protocol

/**
 * Glasses camera: QVGA JPEG.
 * Still capture or continuous JPEG stream.
 */
class Camera internal constructor(private val ctx: Context) {

    private val _frames = MutableSharedFlow<CameraFrame>(extraBufferCapacity = 8)

    /** Emits each JPEG frame. Collect while streaming. */
    val frames: SharedFlow<CameraFrame> = _frames.asSharedFlow()

    private lateinit var bridge: GlassesBridge
    private var streaming = false

    internal fun bind(b: GlassesBridge) {
        bridge = b
        b.cameraListener = { frame -> _frames.tryEmit(frame) }
    }

    /** Capture a single still. Result arrives via [frames]. */
    fun captureStill(quality: JpegQuality = JpegQuality.FINE) {
        bridge.sendIntent(Protocol.CAMERA_SET_MODE_INTENT, mapOf(
            Protocol.EXTRA_CAMERA_JPEG_QUALITY to quality.value,
            Protocol.EXTRA_CAMERA_RESOLUTION   to Resolution.QVGA.value,
            Protocol.EXTRA_CAMERA_MODE         to Protocol.CAMERA_MODE_STILL
        ))
        bridge.sendIntent(Protocol.CAMERA_CAPTURE_STILL_INTENT, emptyMap())
    }

    /** Start continuous JPEG stream. Frames arrive via [frames]. */
    fun startStream(
        quality: JpegQuality = JpegQuality.STANDARD,
        resolution: Resolution = Resolution.QVGA,
        highRate: Boolean = true
    ) {
        streaming = true
        bridge.sendIntent(Protocol.CAMERA_SET_MODE_INTENT, mapOf(
            Protocol.EXTRA_CAMERA_JPEG_QUALITY to quality.value,
            Protocol.EXTRA_CAMERA_RESOLUTION   to resolution.value,
            Protocol.EXTRA_CAMERA_MODE         to if (highRate)
                                                    Protocol.CAMERA_MODE_STREAM_HIGH
                                                else Protocol.CAMERA_MODE_STREAM_LOW
        ))
        bridge.sendIntent(Protocol.CAMERA_START_INTENT, emptyMap())
    }

    fun stopStream() {
        streaming = false
        bridge.sendIntent(Protocol.CAMERA_STOP_INTENT, emptyMap())
    }
}

data class CameraFrame(
    val jpegData: ByteArray,
    val frameId: Int,
    val timestampMs: Long
) {
    override fun equals(other: Any?) = other is CameraFrame && frameId == other.frameId
    override fun hashCode() = frameId
}

enum class JpegQuality(val value: Int) {
    STANDARD(1), FINE(2), SUPER_FINE(3)
}

enum class Resolution(val value: Int) {
    RES_3M(0), RES_1M(1), VGA(4), QVGA(6)
}
