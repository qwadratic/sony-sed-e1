package com.explorer;

import android.content.ContentValues;
import android.content.Context;

import com.sonyericsson.extras.liveware.aef.registration.Registration.ExtensionColumns;
import com.sonyericsson.extras.liveware.extension.util.ExtensionUtils;
import com.sonyericsson.extras.liveware.extension.util.registration.RegistrationInformation;

/**
 * Declares the SmartEyeglass Explorer extension capabilities to Smart Connect.
 * Uses control API version 4 (matches HelloLayouts baseline).
 * Requests sensor API to support Demo 5.
 */
public class ExplorerRegistrationInformation extends RegistrationInformation {

    static final String EXTENSION_KEY = "com.smarteyeglass.explorer.key";

    /** Control API version — must match what the SmartEyeglass host supports. */
    private static final int CONTROL_API_VERSION = 4;

    /** Sensor API version for accelerometer/gyro demos. */
    private static final int SENSOR_API_VERSION = 1;

    private final Context mContext;

    public ExplorerRegistrationInformation(Context context) {
        this.mContext = context;
    }

    @Override
    public int getRequiredControlApiVersion() {
        return CONTROL_API_VERSION;
    }

    @Override
    public int getTargetControlApiVersion() {
        return CONTROL_API_VERSION;
    }

    @Override
    public int getRequiredSensorApiVersion() {
        return SENSOR_API_VERSION;
    }

    @Override
    public int getRequiredNotificationApiVersion() {
        return API_NOT_REQUIRED;
    }

    @Override
    public int getRequiredWidgetApiVersion() {
        return API_NOT_REQUIRED;
    }

    @Override
    public ContentValues getExtensionRegistrationConfiguration() {
        ContentValues values = new ContentValues();
        values.put(ExtensionColumns.NAME,
                mContext.getString(R.string.extension_name));
        values.put(ExtensionColumns.EXTENSION_KEY, EXTENSION_KEY);
        values.put(ExtensionColumns.HOST_APP_ICON_URI,
                ExtensionUtils.getUriString(mContext, R.drawable.ic_extension));
        values.put(ExtensionColumns.EXTENSION_ICON_URI,
                ExtensionUtils.getUriString(mContext, R.drawable.ic_extension));
        values.put(ExtensionColumns.EXTENSION_48PX_ICON_URI,
                ExtensionUtils.getUriString(mContext, R.drawable.ic_extension));
        values.put(ExtensionColumns.NOTIFICATION_API_VERSION,
                getRequiredNotificationApiVersion());
        values.put(ExtensionColumns.PACKAGE_NAME, mContext.getPackageName());
        return values;
    }

    @Override
    public boolean isDisplaySizeSupported(int width, int height) {
        // SmartEyeglass display: 419 x 138
        return (width == 419 && height == 138);
    }
}
