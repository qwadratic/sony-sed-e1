package com.explorer;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.util.Log;

import com.explorer.demos.AnimationDemo;
import com.explorer.demos.ARDemo;
import com.explorer.demos.BaseDemo;
import com.explorer.demos.CameraCaptureDemo;
import com.explorer.demos.CameraStreamDemo;
import com.explorer.demos.GraphicsDemo;
import com.explorer.demos.SensorDemo;
import com.explorer.demos.TextDemo;
import com.explorer.demos.TouchDemo;
import com.explorer.util.DemoEventListener;
import com.sony.smarteyeglass.extension.util.CameraEvent;
import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;
import com.sony.smarteyeglass.extension.util.SmartEyeglassEventListener;
import com.sonyericsson.extras.liveware.aef.control.Control;
import com.sonyericsson.extras.liveware.extension.util.control.ControlExtension;
import com.sonyericsson.extras.liveware.extension.util.control.ControlTouchEvent;

/**
 * Main control extension. Renders a swipe-navigable menu on the glasses display.
 * Each menu item delegates to a BaseDemo subclass.
 */
public class ExplorerControl extends ControlExtension {

    private static final String TAG = "ExplorerControl";
    private static final int SMARTEYEGLASS_API_VERSION = 1;

    private final SmartEyeglassControlUtils mUtils;
    private final BaseDemo[] mDemos;

    /** Index in mDemos currently highlighted in menu. */
    private int mMenuIndex = 0;

    /** Non-null when user is inside a demo (not at the menu). */
    private BaseDemo mActivDemo = null;

    // Reusable bitmap for menu — avoid per-frame alloc
    private Bitmap mMenuBitmap;

    private final Paint mMenuPaint;
    private final Paint mMenuSelPaint;
    private final Paint mHeaderPaint;
    private final Paint mFooterPaint;
    private final Paint mSepPaint;

    public ExplorerControl(Context context, String hostAppPackageName) {
        super(context, hostAppPackageName);

        mUtils = new SmartEyeglassControlUtils(hostAppPackageName,
                new SmartEyeglassEventListener() {
                    @Override
                    public void onCameraReceived(CameraEvent event) {
                        if (mActivDemo instanceof DemoEventListener) {
                            ((DemoEventListener) mActivDemo).onCameraReceived(event);
                        }
                    }
                    @Override
                    public void onCameraErrorReceived(int error) {
                        if (mActivDemo instanceof DemoEventListener) {
                            ((DemoEventListener) mActivDemo).onCameraError(error);
                        }
                    }
                });
        mUtils.setRequiredApiVersion(SMARTEYEGLASS_API_VERSION);
        mUtils.activate(context);

        mDemos = new BaseDemo[] {
            new TextDemo(mUtils, context),
            new AnimationDemo(mUtils, context),
            new GraphicsDemo(mUtils, context),
            new TouchDemo(mUtils, context),
            new SensorDemo(mUtils, context),
            new CameraCaptureDemo(mUtils, context),
            new CameraStreamDemo(mUtils, context),
            new ARDemo(mUtils, context),
        };

        mMenuBitmap = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);

        mMenuPaint = new Paint();
        mMenuPaint.setColor(Color.WHITE);
        mMenuPaint.setTextSize(22);
        mMenuPaint.setTypeface(Typeface.MONOSPACE);
        mMenuPaint.setAntiAlias(false);

        mMenuSelPaint = new Paint(mMenuPaint);
        mMenuSelPaint.setTextSize(24);

        mHeaderPaint = new Paint(mMenuPaint);
        mHeaderPaint.setTextSize(16);
        mHeaderPaint.setColor(Color.GRAY);

        mFooterPaint = new Paint(mMenuPaint);
        mFooterPaint.setTextSize(14);
        mFooterPaint.setColor(Color.GRAY);

        mSepPaint = new Paint();
        mSepPaint.setColor(Color.WHITE);
        mSepPaint.setStrokeWidth(1);
    }

    @Override
    public void onStart() {
        mMenuIndex = 0;
        mActivDemo = null;
        Log.d(TAG, "onStart");
    }

    @Override
    public void onResume() {
        Log.d(TAG, "onResume");
        if (mActivDemo != null) {
            mActivDemo.onEnter();
        } else {
            renderMenu();
        }
        super.onResume();
    }

    @Override
    public void onPause() {
        Log.d(TAG, "onPause");
        if (mActivDemo != null) {
            mActivDemo.onExit();
        }
        super.onPause();
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "onDestroy");
        if (mActivDemo != null) {
            mActivDemo.onExit();
            mActivDemo = null;
        }
        mUtils.deactivate();
    }

    @Override
    public void onTouch(ControlTouchEvent event) {
        super.onTouch(event);
        if (event.getAction() != Control.Intents.TOUCH_ACTION_RELEASE) {
            // Forward press events to TouchDemo if active
            if (mActivDemo instanceof TouchDemo) {
                ((TouchDemo) mActivDemo).onTouchEvent(event);
            }
            return;
        }
        // Release = primary tap action
        if (mActivDemo != null) {
            if (mActivDemo instanceof TouchDemo) {
                ((TouchDemo) mActivDemo).onTouchEvent(event);
            } else {
                mActivDemo.onTap();
            }
        } else {
            // At menu: enter selected demo
            enterDemo(mMenuIndex);
        }
    }

    @Override
    public void onSwipe(int direction) {
        if (mActivDemo != null) {
            // Inside a demo: back gesture exits
            if (direction == Control.Intents.SWIPE_DIRECTION_DOWN) {
                exitDemo();
                return;
            }
            if (mActivDemo instanceof TouchDemo) {
                ((TouchDemo) mActivDemo).onSwipe(direction);
            } else {
                mActivDemo.onSwipe(direction);
            }
        } else {
            // At menu: navigate
            if (direction == Control.Intents.SWIPE_DIRECTION_LEFT) {
                mMenuIndex = (mMenuIndex + 1) % mDemos.length;
            } else if (direction == Control.Intents.SWIPE_DIRECTION_RIGHT) {
                mMenuIndex = (mMenuIndex - 1 + mDemos.length) % mDemos.length;
            }
            renderMenu();
        }
    }

    private void enterDemo(int index) {
        if (index < 0 || index >= mDemos.length) return;
        mActivDemo = mDemos[index];
        mActivDemo.onEnter();
    }

    private void exitDemo() {
        if (mActivDemo != null) {
            mActivDemo.onExit();
            mActivDemo = null;
        }
        renderMenu();
    }

    private void renderMenu() {
        Canvas c = new Canvas(mMenuBitmap);
        c.drawColor(Color.BLACK);

        // Header
        String pageInfo = (mMenuIndex + 1) + "/" + mDemos.length;
        c.drawText("API Explorer", 8, 16, mHeaderPaint);
        float pw = mHeaderPaint.measureText(pageInfo);
        c.drawText(pageInfo, 419 - pw - 8, 16, mHeaderPaint);
        c.drawLine(0, 22, 419, 22, mSepPaint);

        // Show 3 items: prev (dimmed), current (highlighted), next (dimmed)
        int prev = (mMenuIndex - 1 + mDemos.length) % mDemos.length;
        int next = (mMenuIndex + 1) % mDemos.length;

        Paint dimPaint = new Paint(mMenuPaint);
        dimPaint.setAlpha(80);
        dimPaint.setTextSize(18);

        c.drawText(mDemos[prev].getName(), 8, 44, dimPaint);
        c.drawText("▶ " + mDemos[mMenuIndex].getName(), 8, 72, mMenuSelPaint);
        c.drawText(mDemos[next].getName(), 8, 98, dimPaint);

        c.drawText("[tap] enter  [swipe] navigate  [↓] back", 8, 130, mFooterPaint);

        mUtils.showBitmap(mMenuBitmap);
    }
}
