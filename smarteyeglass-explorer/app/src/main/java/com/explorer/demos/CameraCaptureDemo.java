package com.explorer.demos;

import android.content.Context;
import android.util.Log;

import com.explorer.util.DemoEventListener;
import com.explorer.util.DisplayRenderer;
import com.sony.smarteyeglass.SmartEyeglassControl;
import com.sony.smarteyeglass.extension.util.CameraEvent;
import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;

/**
 * Demo 6: Camera Still Capture
 * Tap to trigger a JPEG capture; confirms with byte-size.
 * Events routed from ExplorerControl via DemoEventListener.
 */
public class CameraCaptureDemo extends BaseDemo implements DemoEventListener {

    private static final String TAG = "CameraCaptureDemo";

    private int mCaptureCount = 0;

    public CameraCaptureDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
    }

    public String getName() { return "Camera: Still"; }

    public void onEnter() {
        render("Tap to capture", "Camera: STILL mode", "", "");
    }

    public void onExit() {
        try {
            utils.stopCamera();
        } catch (Exception ignored) {}
    }

    public void onTap() {
        render("Capturing...", "", "", "");
        try {
            // setCameraMode(jpegQuality, resolution, recordingMode)
            utils.setCameraMode(
                    SmartEyeglassControl.Intents.CAMERA_JPEG_QUALITY_FINE,
                    SmartEyeglassControl.Intents.CAMERA_RESOLUTION_QVGA,
                    SmartEyeglassControl.Intents.CAMERA_MODE_STILL);
            utils.requestCameraCapture();
        } catch (Exception e) {
            Log.e(TAG, "capture failed: " + e.getMessage());
            render("Error: " + e.getClass().getSimpleName(),
                   e.getMessage() != null ? e.getMessage() : "unknown", "", "");
        }
    }

    public void onSwipe(int direction) {}

    // DemoEventListener
    public void onCameraReceived(CameraEvent event) {
        mCaptureCount++;
        int bytes = (event.getData() != null) ? event.getData().length : 0;
        render("Capture #" + mCaptureCount + " OK",
               "Size: " + bytes + " bytes",
               "Frame id: " + event.getFrameId(),
               "[tap] capture again");
    }

    public void onCameraError(int error) {
        render("Camera error: code=" + error,
               "emulator may lack camera feed",
               "[tap] retry", "");
    }

    private void render(String l1, String l2, String l3, String l4) {
        pushFrame(DisplayRenderer.renderMessage(l1, l2, l3, l4));
    }
}
