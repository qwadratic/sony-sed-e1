package com.explorer.util;

import com.sony.smarteyeglass.extension.util.CameraEvent;

/**
 * Interface for demos that need SmartEyeglass events (camera frames, etc.)
 * ExplorerControl routes SDK events to the currently active demo.
 */
public interface DemoEventListener {
    void onCameraReceived(CameraEvent event);
    void onCameraError(int error);
}
