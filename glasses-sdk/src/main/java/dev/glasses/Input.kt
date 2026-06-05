package dev.glasses

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** Receives touch and swipe input from the glasses controller. */
class Input internal constructor() {

    private val _events = MutableSharedFlow<InputEvent>(extraBufferCapacity = 64)

    /** Hot flow of all input events. Collect in your coroutine scope. */
    val events: SharedFlow<InputEvent> = _events.asSharedFlow()

    internal fun bind(bridge: GlassesBridge) {
        bridge.inputListener = { event -> _events.tryEmit(event) }
    }

    /** Convenience: filter only taps */
    fun taps(): SharedFlow<InputEvent.Tap> =
        // Callers can filter: events.filterIsInstance<InputEvent.Tap>()
        throw UnsupportedOperationException("Use events.filterIsInstance<InputEvent.Tap>()")
}

sealed class InputEvent {
    data class Tap(val x: Float, val y: Float, val action: TapAction) : InputEvent()
    data class Swipe(val direction: SwipeDirection) : InputEvent()
    object LongPress : InputEvent()
    object Back : InputEvent()  // back button on controller
}

enum class TapAction { PRESS, RELEASE, LONG_PRESS }

enum class SwipeDirection {
    LEFT, RIGHT, UP, DOWN;

    companion object {
        fun fromInt(v: Int) = when (v) {
            1 -> LEFT; 2 -> RIGHT; 3 -> UP; 4 -> DOWN
            else -> LEFT
        }
    }
}
