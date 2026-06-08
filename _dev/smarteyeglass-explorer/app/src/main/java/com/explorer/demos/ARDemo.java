package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;

import com.sony.smarteyeglass.SmartEyeglassControl;
import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;
import com.sony.smarteyeglass.extension.util.ar.CylindricalRenderObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Timer;
import java.util.TimerTask;

/**
 * Demo 8: AR Coordinate Rendering (Cylindrical mode)
 * Places markers at fixed headings on the cylindrical coordinate system.
 * On emulator: demonstrates the AR mode API surface with mock rotation.
 */
public class ARDemo extends BaseDemo {

    private static final String TAG = "ARDemo";

    private Timer mTimer;
    private float mMockHeading = 0; // simulated compass heading in degrees
    private boolean mArActive = false;
    private Bitmap mFrameBitmap;

    private final Paint mPaint;
    private final Paint mSmallPaint;

    // AR objects we'll register at fixed headings
    private final List<CylindricalRenderObject> mObjects = new ArrayList<CylindricalRenderObject>();

    public ARDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
        mPaint = new Paint();
        mPaint.setColor(Color.WHITE);
        mPaint.setTextSize(20);
        mPaint.setAntiAlias(false);

        mSmallPaint = new Paint(mPaint);
        mSmallPaint.setTextSize(16);
        mSmallPaint.setColor(Color.GRAY);
    }

    public String getName() { return "AR: Cylindrical"; }

    public void onEnter() {
        mFrameBitmap = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        activateAR();
        startMockRotation();
    }

    public void onExit() {
        stopMockRotation();
        deactivateAR();
    }

    public void onTap() {
        // Step heading manually
        mMockHeading = (mMockHeading + 45) % 360;
        renderStatus();
    }

    public void onSwipe(int direction) {}

    private void activateAR() {
        try {
            utils.setRenderMode(SmartEyeglassControl.Intents.MODE_AR);
            mArActive = true;
            Log.d(TAG, "AR mode activated");

            // Create a simple bitmap marker (white cross on black)
            Bitmap marker = Bitmap.createBitmap(40, 40, Bitmap.Config.ARGB_8888);
            Canvas mc = new Canvas(marker);
            mc.drawColor(Color.BLACK);
            Paint mp = new Paint();
            mp.setColor(Color.WHITE);
            mc.drawLine(20, 5, 20, 35, mp);
            mc.drawLine(5, 20, 35, 20, mp);

            // Register a cylindrical object at heading 0 (North)
            // CylindricalRenderObject(id, bitmap, order, objectType, h_deg, v_deg)
            CylindricalRenderObject obj = new CylindricalRenderObject(
                    1, marker, 0,
                    SmartEyeglassControl.Intents.AR_OBJECT_TYPE_STATIC_IMAGE,
                    0.0f, 0.0f);
            mObjects.add(obj);
            utils.registerARObject(obj);

        } catch (Exception e) {
            Log.w(TAG, "AR mode not available: " + e.getMessage());
            mArActive = false;
        }
    }

    private void deactivateAR() {
        try {
            for (CylindricalRenderObject o : mObjects) {
                utils.deleteARObject(o);
            }
            mObjects.clear();
            utils.setRenderMode(SmartEyeglassControl.Intents.MODE_NORMAL);
        } catch (Exception ignored) {}
    }

    private void startMockRotation() {
        mTimer = new Timer("ar-mock", true);
        mTimer.scheduleAtFixedRate(new TimerTask() {
            public void run() {
                mMockHeading = (mMockHeading + 1f) % 360;
                renderStatus();
            }
        }, 0, 100); // 10 Hz heading update
    }

    private void stopMockRotation() {
        if (mTimer != null) {
            mTimer.cancel();
            mTimer = null;
        }
    }

    private void renderStatus() {
        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);

        c.drawText("AR Mode: Cylindrical", 8, 20, mPaint);
        Paint sep = new Paint(); sep.setColor(Color.WHITE);
        c.drawLine(0, 26, 419, 26, sep);

        c.drawText("AR active: " + (mArActive ? "YES" : "NO (emulator)"), 8, 52, mPaint);
        c.drawText(String.format("Heading: %.0f deg", mMockHeading), 8, 78, mPaint);
        c.drawText("Marker @ 0 deg (North)", 8, 104, mPaint);
        c.drawText("[tap] step +45deg", 8, 130, mSmallPaint);

        pushFrame(mFrameBitmap);
    }
}
