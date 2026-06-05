package dev.glasses

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import dev.glasses.internal.Protocol

/** Push bitmaps to the 419×138 green display. */
class Display internal constructor(private val ctx: Context) {

    companion object {
        const val WIDTH = 419
        const val HEIGHT = 138
    }

    private lateinit var bridge: GlassesBridge

    internal fun bind(b: GlassesBridge) { bridge = b }

    /**
     * Push any bitmap. Auto-scales to fit 419×138 if needed.
     * White pixels → green on device. Draw white-on-black for best results.
     */
    fun show(bitmap: Bitmap) {
        val scaled = if (bitmap.width == WIDTH && bitmap.height == HEIGHT) bitmap
                     else Bitmap.createScaledBitmap(bitmap, WIDTH, HEIGHT, false)
        bridge.sendDisplay(scaled)
    }

    /**
     * Push a bitmap at a specific offset (partial update).
     * Only the given bitmap region is updated; rest of display unchanged.
     */
    fun showAt(bitmap: Bitmap, x: Int, y: Int) {
        bridge.sendDisplayAt(bitmap, x, y)
    }

    /**
     * Clear the display to black.
     */
    fun clear() {
        val bmp = blank()
        show(bmp)
        bmp.recycle()
    }

    /**
     * Convenience: draw text centered on the display.
     */
    fun showText(line1: String, line2: String = "", line3: String = "", line4: String = "") {
        val bmp = blank()
        val c = Canvas(bmp)
        val p = Paint().apply {
            color = Color.WHITE
            textSize = 22f
            isAntiAlias = false
        }
        val lines = listOf(line1, line2, line3, line4).filter { it.isNotEmpty() }
        val startY = when (lines.size) {
            1 -> 80f
            2 -> 56f
            3 -> 40f
            else -> 30f
        }
        lines.forEachIndexed { i, line ->
            c.drawText(line, 8f, startY + i * 30f, p)
        }
        show(bmp)
        bmp.recycle()
    }

    /** Allocate a fresh 419×138 black bitmap. Caller should recycle after use. */
    fun blank(): Bitmap {
        val bmp = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        Canvas(bmp).drawColor(Color.BLACK)
        return bmp
    }

    /**
     * Switch display to AR (cylindrical coordinate) mode.
     * In AR mode use GlassesAR instead of show().
     */
    fun setARMode(enabled: Boolean) {
        bridge.sendIntent(
            if (enabled) Protocol.AR_SET_MODE_INTENT else Protocol.AR_SET_MODE_INTENT,
            mapOf(Protocol.EXTRA_AR_MODE to if (enabled) 1 else 0)
        )
    }
}
