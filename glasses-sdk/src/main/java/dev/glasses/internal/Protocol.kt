package dev.glasses.internal

/** All Sony wire-protocol constants in one place. Source of truth. */
internal object Protocol {

    // ── Display ──────────────────────────────────────────────────────────────
    const val DISPLAY_DATA_INTENT           = "com.sony.smarteyeglass.control.DISPLAY_DATA"
    const val DISPLAY_DATA_RESULT_INTENT    = "com.sony.smarteyeglass.control.DISPLAY_DATA_RESULT"
    const val AR_SET_MODE_INTENT            = "com.sony.smarteyeglass.control.AR_SET_MODE"
    const val EXTRA_AR_MODE                 = "ar_mode"
    const val MODE_NORMAL                   = 0
    const val MODE_AR                       = 1

    // ── Camera ───────────────────────────────────────────────────────────────
    const val CAMERA_SET_MODE_INTENT        = "com.sony.smarteyeglass.control.CAMERA_SET_MODE"
    const val CAMERA_START_INTENT           = "com.sony.smarteyeglass.control.CAMERA_START"
    const val CAMERA_STOP_INTENT            = "com.sony.smarteyeglass.control.CAMERA_STOP"
    const val CAMERA_CAPTURE_STILL_INTENT   = "com.sony.smarteyeglass.control.CAMERA_CAPTURE_STILL"
    const val CAMERA_FILE_NOTIFY_INTENT     = "com.sony.smarteyeglass.control.CAMERA_NOTIFY_CAPTURED_FILE_EVENT"
    const val CAMERA_ERROR_INTENT           = "com.sony.smarteyeglass.control.CAMERA_NOTIFY_ERROR_EVENT"

    const val EXTRA_CAMERA_JPEG_QUALITY     = "camera_jpeg_quality"
    const val EXTRA_CAMERA_RESOLUTION       = "camera_resolution"
    const val EXTRA_CAMERA_MODE             = "camera_mode"
    const val EXTRA_CAMERA_FILE_PATH        = "camera_file_path"

    const val CAMERA_JPEG_QUALITY_STANDARD  = 1
    const val CAMERA_JPEG_QUALITY_FINE      = 2
    const val CAMERA_JPEG_QUALITY_SUPER     = 3

    const val CAMERA_RESOLUTION_3M          = 0
    const val CAMERA_RESOLUTION_1M          = 1
    const val CAMERA_RESOLUTION_VGA         = 4
    const val CAMERA_RESOLUTION_QVGA        = 6

    const val CAMERA_MODE_STILL             = 0
    const val CAMERA_MODE_STILL_TO_FILE     = 1
    const val CAMERA_MODE_STREAM_LOW        = 2
    const val CAMERA_MODE_STREAM_HIGH       = 3

    // ── AR ───────────────────────────────────────────────────────────────────
    const val AR_REGISTER_OBJECT_INTENT     = "com.sony.smarteyeglass.control.AR_REGISTER_OBJECT_REQUEST"
    const val AR_MOVE_OBJECT_INTENT         = "com.sony.smarteyeglass.control.AR_MOVE_OBJECT"
    const val AR_DELETE_OBJECT_INTENT       = "com.sony.smarteyeglass.control.AR_DELETE_OBJECT"
    const val AR_CHANGE_VERT_RANGE_INTENT   = "com.sony.smarteyeglass.control.AR_CHANGE_CYLINDRICAL_VERTICAL_RANGE"

    const val EXTRA_AR_OBJECT_ID            = "ar_object_id"
    const val EXTRA_AR_COORDINATE_TYPE      = "ar_coordinate_type"
    const val EXTRA_AR_CYLINDRICAL_H        = "ar_cylindrical_pos_h"
    const val EXTRA_AR_CYLINDRICAL_V        = "ar_cylindrical_pos_v"
    const val EXTRA_AR_OBJECT_TYPE          = "ar_object_type"
    const val EXTRA_AR_ORDER                = "ar_order"
    const val EXTRA_AR_VERTICAL_RANGE       = "ar_cylindrical_vertical_range"

    const val AR_COORDINATE_CYLINDRICAL     = 1
    const val AR_OBJECT_TYPE_STATIC         = 0
    const val AR_OBJECT_TYPE_ANIMATED       = 1

    // ── Input ────────────────────────────────────────────────────────────────
    const val TOUCH_EVENT_INTENT            = "com.sonyericsson.extras.liveware.aef.control.TOUCH_EVENT"
    const val SWIPE_EVENT_INTENT            = "com.sonyericsson.extras.liveware.aef.control.SWIPE_EVENT"
    const val KEY_EVENT_INTENT              = "com.sonyericsson.extras.liveware.aef.control.KEY_EVENT"

    const val EXTRA_TOUCH_X                 = "x"
    const val EXTRA_TOUCH_Y                 = "y"
    const val EXTRA_TOUCH_ACTION            = "action"
    const val EXTRA_SWIPE_DIRECTION         = "direction"

    const val TOUCH_ACTION_PRESS            = 1
    const val TOUCH_ACTION_RELEASE          = 2
    const val TOUCH_ACTION_LONG_PRESS       = 3

    const val SWIPE_LEFT                    = 1
    const val SWIPE_RIGHT                   = 2
    const val SWIPE_UP                      = 3
    const val SWIPE_DOWN                    = 4

    // ── Power / Settings ─────────────────────────────────────────────────────
    const val POWER_MODE_INTENT             = "com.sony.smarteyeglass.control.POWER_MODE_SET_MODE"
    const val SCREEN_DEPTH_INTENT           = "com.sony.smarteyeglass.control.SCREEN_DEPTH_SET_DEPTH"
    const val STANDBY_REQUEST_INTENT        = "com.sony.smarteyeglass.control.STANDBY_CONFIRM_REQUEST"
    const val BATTERY_REQUEST_INTENT        = "com.sony.smarteyeglass.control.BATTERY_GET_LEVEL_REQUEST"
    const val BATTERY_RESPONSE_INTENT       = "com.sony.smarteyeglass.control.BATTERY_GET_LEVEL_RESPONSE"

    const val EXTRA_POWER_MODE              = "power_mode"
    const val EXTRA_SCREEN_DEPTH            = "screen_depth"
    const val EXTRA_BATTERY_LEVEL          = "battery_level"

    const val POWER_MODE_HIGH               = 0
    const val POWER_MODE_NORMAL             = 1

    // ── Registration (Smart Connect ContentProvider) ─────────────────────────
    const val REGISTER_REQUEST_ACTION       = "com.sonyericsson.extras.liveware.aef.registration.EXTENSION_REGISTER_REQUEST"
    const val CAPABILITY_CHANGED_ACTION     = "com.sonyericsson.extras.liveware.aef.registration.CAPABILITY_CHANGED"
    const val ACCESSORY_CONNECTION_ACTION   = "com.sonyericsson.extras.liveware.aef.registration.ACCESSORY_CONNECTION"

    const val SEG_HOST_PACKAGE              = "com.sony.smarteyeglass"
    const val SEG_HOST_PERMISSION           = "com.sony.smarteyeglass.permission.SMARTEYEGLASS"
    const val SMARTCONNECT_PACKAGE          = "com.sonyericsson.extras.liveware"

    // ── Sensor type values (from Registration.SensorTypeValue) ───────────────
    const val SENSOR_TYPE_ACCELEROMETER     = 1
    const val SENSOR_TYPE_MAGNETIC_FIELD    = 2
    const val SENSOR_TYPE_GYROSCOPE         = 13
    const val SENSOR_TYPE_ROTATION_VECTOR   = 12
    const val SENSOR_TYPE_LIGHT             = 16
}
