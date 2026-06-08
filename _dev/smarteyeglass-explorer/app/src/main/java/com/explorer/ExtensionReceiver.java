package com.explorer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Receives Smart Connect registration broadcasts and starts the extension service.
 * Pattern: plain BroadcastReceiver that re-routes the intent to the Service.
 */
public class ExtensionReceiver extends BroadcastReceiver {

    private static final String TAG = "ExtensionReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(TAG, "onReceive: " + intent.getAction());
        intent.setClass(context, ExplorerExtensionService.class);
        context.startService(intent);
    }
}
