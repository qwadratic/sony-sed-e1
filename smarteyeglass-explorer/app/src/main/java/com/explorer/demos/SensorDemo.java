package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;

import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;
import com.sonyericsson.extras.liveware.aef.registration.Registration.SensorTypeValue;
import com.sonyericsson.extras.liveware.aef.sensor.Sensor;
import com.sonyericsson.extras.liveware.extension.util.sensor.AccessorySensor;
import com.sonyericsson.extras.liveware.extension.util.sensor.AccessorySensorEvent;
import com.sonyericsson.extras.liveware.extension.util.sensor.AccessorySensorEventListener;
import com.sonyericsson.extras.liveware.extension.util.sensor.AccessorySensorException;
import com.sonyericsson.extras.liveware.extension.util.sensor.AccessorySensorManager;

/**
 * Demo 5: Live Sensor Readout
 * Shows accelerometer, gyroscope, and compass data in real time.
 * Falls back to mock data if sensors are unavailable (emulator).
 */
public class SensorDemo extends BaseDemo {

    private static final String TAG = "SensorDemo";

    private AccessorySensorManager mSensorManager;
    private AccessorySensor mAccel;
    private AccessorySensor mGyro;

    private float[] mAccelVals = {0, 0, 9.81f};
    private float[] mGyroVals  = {0, 0, 0};

    private boolean mUseMock = false;
    private Bitmap mFrameBitmap;
    private final Paint mPaint;
    private final Paint mLabelPaint;

    public SensorDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
        mPaint = new Paint();
        mPaint.setColor(Color.WHITE);
        mPaint.setTextSize(20);
        mPaint.setAntiAlias(false);

        mLabelPaint = new Paint(mPaint);
        mLabelPaint.setTextSize(16);
        mLabelPaint.setColor(Color.GRAY);
    }

    public String getName() { return "Sensors: Live"; }

    public void onEnter() {
        mFrameBitmap = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        startSensors();
        render();
    }

    public void onExit() {
        stopSensors();
    }

    public void onTap() {
        // Toggle mock data
        mUseMock = !mUseMock;
        if (mUseMock) {
            // Simulate movement
            mAccelVals = new float[]{0.12f, 9.81f, 0.34f};
            mGyroVals  = new float[]{0.01f, -0.02f, 0.00f};
        }
        render();
    }

    public void onSwipe(int direction) {}

    private void startSensors() {
        try {
            mSensorManager = new AccessorySensorManager(context,
                    "com.sony.smarteyeglass");

            mAccel = mSensorManager.getSensor(SensorTypeValue.ACCELEROMETER);
            if (mAccel != null) {
                mAccel.registerFixedRateListener(mAccelListener,
                        Sensor.SensorRates.SENSOR_DELAY_UI);
            }

            mGyro = mSensorManager.getSensor(SensorTypeValue.GYROSCOPE);
            if (mGyro != null) {
                mGyro.registerFixedRateListener(mGyroListener,
                        Sensor.SensorRates.SENSOR_DELAY_UI);
            }

            if (mAccel == null && mGyro == null) {
                mUseMock = true;
                Log.d(TAG, "No sensors found, using mock data");
            }
        } catch (Exception e) {
            mUseMock = true;
            Log.d(TAG, "Sensor init failed: " + e.getMessage() + " - using mock");
        }
    }

    private void stopSensors() {
        try {
            if (mAccel != null) mAccel.unregisterListener();
            if (mGyro != null)  mGyro.unregisterListener();
        } catch (Exception ignored) {}
    }

    private final AccessorySensorEventListener mAccelListener = new AccessorySensorEventListener() {
        public void onSensorEvent(AccessorySensorEvent event) {
            float[] vals = event.getSensorValues();
            if (vals != null && vals.length >= 3) {
                mAccelVals = vals;
                render();
            }
        }
    };

    private final AccessorySensorEventListener mGyroListener = new AccessorySensorEventListener() {
        public void onSensorEvent(AccessorySensorEvent event) {
            float[] vals = event.getSensorValues();
            if (vals != null && vals.length >= 3) {
                mGyroVals = vals;
                render();
            }
        }
    };

    private void render() {
        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);

        c.drawText("Sensors" + (mUseMock ? " [MOCK]" : " [LIVE]"), 8, 18, mLabelPaint);
        Paint sep = new Paint(); sep.setColor(Color.WHITE);
        c.drawLine(0, 24, 419, 24, sep);

        c.drawText(String.format("Accel: x=%5.2f y=%5.2f z=%5.2f",
                mAccelVals[0], mAccelVals[1], mAccelVals[2]), 8, 50, mPaint);

        c.drawText(String.format("Gyro:  x=%5.2f y=%5.2f z=%5.2f",
                mGyroVals[0], mGyroVals[1], mGyroVals[2]), 8, 76, mPaint);

        c.drawText("Compass: --deg (no compass reg)", 8, 102, mPaint);

        Paint fp = new Paint(mLabelPaint);
        c.drawText("[tap] toggle mock data", 8, 130, fp);

        pushFrame(mFrameBitmap);
    }
}
