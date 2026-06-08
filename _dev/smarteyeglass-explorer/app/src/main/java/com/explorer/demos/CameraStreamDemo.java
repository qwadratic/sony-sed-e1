package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;

import com.explorer.util.DemoEventListener;
import com.sony.smarteyeglass.SmartEyeglassControl;
import com.sony.smarteyeglass.extension.util.CameraEvent;
import com.sony.smarteyeglass.extension.util.ControlCameraException;
import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;

/**
 * Demo 7: Camera JPEG Stream
 * Starts JPG_STREAM_HIGH_RATE, shows frame count + FPS.
 * Events routed from ExplorerControl via DemoEventListener.
 */
public class CameraStreamDemo extends BaseDemo implements DemoEventListener {

    private static final String TAG = "CameraStreamDemo";

    private boolean mStreaming = false;
    private int mFrameCount = 0;
    private long mStartTime;
    private Bitmap mFrameBitmap;
    private final Paint mPaint;
    private final Paint mSmallPaint;

    public CameraStreamDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
        mPaint = new Paint();
        mPaint.setColor(Color.WHITE);
        mPaint.setTextSize(22);
        mPaint.setAntiAlias(false);

        mSmallPaint = new Paint(mPaint);
        mSmallPaint.setTextSize(16);
        mSmallPaint.setColor(Color.GRAY);
    }

    public String getName() { return "Camera: Stream"; }

    public void onEnter() {
        mFrameBitmap = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        renderIdle("Tap to start stream", "JPEG frames at high rate");
    }

    public void onExit() {
        stopStream();
    }

    public void onTap() {
        if (mStreaming) {
            stopStream();
            renderIdle("Stream stopped", "Total frames: " + mFrameCount);
        } else {
            startStream();
        }
    }

    public void onSwipe(int direction) {}

    // DemoEventListener
    public void onCameraReceived(CameraEvent event) {
        if (!mStreaming) return;
        mFrameCount++;
        int bytes = (event.getData() != null) ? event.getData().length : 0;
        long elapsed = System.currentTimeMillis() - mStartTime;
        float fps = (elapsed > 0) ? (mFrameCount * 1000f / elapsed) : 0;

        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);
        c.drawText("JPEG Stream LIVE", 8, 24, mPaint);
        c.drawText("frame #" + mFrameCount, 8, 56, mPaint);
        c.drawText(String.format("%.1f fps  %d bytes", fps, bytes), 8, 86, mPaint);
        c.drawText("[tap] stop", 8, 130, mSmallPaint);
        pushFrame(mFrameBitmap);
    }

    public void onCameraError(int error) {
        mStreaming = false;
        renderIdle("Camera error code=" + error, "emulator may lack camera");
    }

    private void startStream() {
        mFrameCount = 0;
        mStartTime = System.currentTimeMillis();
        try {
            // setCameraMode(jpegQuality, resolution, recordingMode)
            utils.setCameraMode(
                    SmartEyeglassControl.Intents.CAMERA_JPEG_QUALITY_STANDARD,
                    SmartEyeglassControl.Intents.CAMERA_RESOLUTION_QVGA,
                    SmartEyeglassControl.Intents.CAMERA_MODE_JPG_STREAM_HIGH_RATE);
            utils.startCamera();
            mStreaming = true;
            renderIdle("Stream started...", "waiting for frames");
        } catch (ControlCameraException e) {
            Log.e(TAG, "startCamera failed: " + e.getMessage());
            renderIdle("Error starting camera:", e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "unexpected: " + e.getMessage());
            renderIdle("Unexpected error", e.getClass().getSimpleName());
        }
    }

    private void stopStream() {
        mStreaming = false;
        try {
            utils.stopCamera();
        } catch (Exception ignored) {}
    }

    private void renderIdle(String line1, String line2) {
        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);
        c.drawText("Camera: Stream", 8, 24, mPaint);
        Paint sep = new Paint(); sep.setColor(Color.WHITE);
        c.drawLine(0, 30, 419, 30, sep);
        c.drawText(line1, 8, 60, mPaint);
        if (line2 != null) c.drawText(line2, 8, 88, mSmallPaint);
        c.drawText("[tap] toggle stream", 8, 130, mSmallPaint);
        pushFrame(mFrameBitmap);
    }
}
