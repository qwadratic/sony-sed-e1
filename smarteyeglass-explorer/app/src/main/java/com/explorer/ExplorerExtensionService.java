package com.explorer;

import android.util.Log;

import com.sonyericsson.extras.liveware.extension.util.ExtensionService;
import com.sonyericsson.extras.liveware.extension.util.control.ControlExtension;
import com.sonyericsson.extras.liveware.extension.util.registration.RegistrationInformation;

/**
 * Smart Extension service. Smart Connect binds to this; we create the
 * ExplorerControl instance when the glasses launch our extension.
 */
public class ExplorerExtensionService extends ExtensionService {

    private static final String TAG = "ExplorerExtensionService";

    public ExplorerExtensionService() {
        super(ExplorerRegistrationInformation.EXTENSION_KEY);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Service created");
    }

    @Override
    protected RegistrationInformation getRegistrationInformation() {
        return new ExplorerRegistrationInformation(this);
    }

    @Override
    protected boolean keepRunningWhenConnected() {
        return false;
    }

    @Override
    public ControlExtension createControlExtension(String hostAppPackageName) {
        Log.d(TAG, "Creating ExplorerControl for host: " + hostAppPackageName);
        return new ExplorerControl(getApplicationContext(), hostAppPackageName);
    }
}
