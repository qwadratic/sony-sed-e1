package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;

import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;

/**
 * Base class for all API Explorer demo screens.
 * Each demo gets lifecycle callbacks from ExplorerControl.
 */
public abstract class BaseDemo {

    protected final SmartEyeglassControlUtils utils;
    protected final Context context;

    /** Name shown in main menu. */
    public abstract String getName();

    public BaseDemo(SmartEyeglassControlUtils utils, Context context) {
        this.utils = utils;
        this.context = context;
    }

    /** Called when user selects this demo from the menu. */
    public abstract void onEnter();

    /** Called when user presses back / returns to menu. */
    public abstract void onExit();

    /** Called on tap inside the demo. */
    public abstract void onTap();

    /** Called on swipe inside the demo. */
    public abstract void onSwipe(int direction);

    /** Push a rendered bitmap to the glasses display. */
    protected void pushFrame(Bitmap bmp) {
        utils.showBitmap(bmp);
    }
}
