package dev.glasses

import android.content.Context
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** Live sensor data from the glasses. All flows are hot (SharedFlow). */
class Sensors internal constructor(private val ctx: Context) {

    private val _accelerometer = MutableSharedFlow<FloatArray>(extraBufferCapacity = 32)
    private val _gyroscope = MutableSharedFlow<FloatArray>(extraBufferCapacity = 32)
    private val _magnetometer = MutableSharedFlow<FloatArray>(extraBufferCapacity = 32)
    private val _rotation = MutableSharedFlow<FloatArray>(extraBufferCapacity = 32)
    private val _light = MutableSharedFlow<Float>(extraBufferCapacity = 32)

    /** [x, y, z] m/s² */
    val accelerometer: SharedFlow<FloatArray> = _accelerometer.asSharedFlow()

    /** [x, y, z] rad/s */
    val gyroscope: SharedFlow<FloatArray> = _gyroscope.asSharedFlow()

    /** [x, y, z] μT */
    val magnetometer: SharedFlow<FloatArray> = _magnetometer.asSharedFlow()

    /** Rotation vector [x, y, z, w] */
    val rotationVector: SharedFlow<FloatArray> = _rotation.asSharedFlow()

    /** Ambient light in lux */
    val light: SharedFlow<Float> = _light.asSharedFlow()

    internal fun bind(bridge: GlassesBridge) {
        bridge.sensorListener = { type, values ->
            when (type) {
                SensorType.ACCELEROMETER -> _accelerometer.tryEmit(values)
                SensorType.GYROSCOPE     -> _gyroscope.tryEmit(values)
                SensorType.MAGNETOMETER  -> _magnetometer.tryEmit(values)
                SensorType.ROTATION      -> _rotation.tryEmit(values)
                SensorType.LIGHT         -> _light.tryEmit(values[0])
            }
        }
    }

    fun enableAll() = bridge?.enableSensors(SensorType.values().toList())
    fun enable(vararg types: SensorType) = bridge?.enableSensors(types.toList())
    fun disableAll() = bridge?.disableSensors()

    private var bridge: GlassesBridge? = null
    internal fun bindBridge(b: GlassesBridge) { bridge = b; bind(b) }
}

enum class SensorType(val sdkValue: Int) {
    ACCELEROMETER(1),
    GYROSCOPE(13),
    MAGNETOMETER(14),
    ROTATION(12),
    LIGHT(16)
}
