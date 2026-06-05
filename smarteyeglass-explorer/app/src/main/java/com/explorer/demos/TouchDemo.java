package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;

import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;
import com.sonyericsson.extras.liveware.aef.control.Control;
import com.sonyericsson.extras.liveware.extension.util.control.ControlTouchEvent;

import java.util.ArrayList;
import java.util.List;

/**
 * Demo 4: Touch & Input
 * Displays a live event log for tap, long-press, and swipe.
 */
public class TouchDemo extends BaseDemo {

    private static final int MAX_LOG = 4;
    private final List<String> mLog = new ArrayList<String>();
    private Bitmap mFrameBitmap;

    private final Paint mPaint;
    private final Paint mHeaderPaint;

    public TouchDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
        mPaint = new Paint();
        mPaint.setColor(Color.WHITE);
        mPaint.setTextSize(20);
        mPaint.setAntiAlias(false);

        mHeaderPaint = new Paint(mPaint);
        mHeaderPaint.setTextSize(16);
        mHeaderPaint.setColor(Color.GRAY);
    }

    public String getName() { return "Input: Touch"; }

    public void onEnter() {
        mLog.clear();
        mFrameBitmap = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        addEvent("-- waiting for input --");
        render();
    }

    public void onExit() {
        mLog.clear();
    }

    public void onTap() {
        addEvent("TAP");
        render();
    }

    /**
     * Called by ExplorerControl with the full ControlTouchEvent.
     */
    public void onTouchEvent(ControlTouchEvent event) {
        String action;
        switch (event.getAction()) {
            case Control.Intents.TOUCH_ACTION_PRESS:
                action = "PRESS x=" + (int)event.getX() + " y=" + (int)event.getY();
                break;
            case Control.Intents.TOUCH_ACTION_RELEASE:
                action = "RELEASE x=" + (int)event.getX();
                break;
            case Control.Intents.TOUCH_ACTION_LONGPRESS:
                action = "LONG_PRESS";
                break;
            default:
                action = "ACT=" + event.getAction();
        }
        addEvent(action);
        render();
    }

    public void onSwipe(int direction) {
        String dir;
        switch (direction) {
            case Control.Intents.SWIPE_DIRECTION_LEFT:  dir = "SWIPE LEFT";  break;
            case Control.Intents.SWIPE_DIRECTION_RIGHT: dir = "SWIPE RIGHT"; break;
            case Control.Intents.SWIPE_DIRECTION_UP:    dir = "SWIPE UP";    break;
            case Control.Intents.SWIPE_DIRECTION_DOWN:  dir = "SWIPE DOWN";  break;
            default: dir = "SWIPE dir=" + direction;
        }
        addEvent(dir);
        render();
    }

    private void addEvent(String event) {
        mLog.add(0, event);
        if (mLog.size() > MAX_LOG) {
            mLog.remove(mLog.size() - 1);
        }
    }

    private void render() {
        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);
        c.drawText("Input Events", 8, 16, mHeaderPaint);
        Paint sep = new Paint();
        sep.setColor(Color.WHITE);
        c.drawLine(0, 22, 419, 22, sep);

        int y = 44;
        for (String entry : mLog) {
            c.drawText(entry, 8, y, mPaint);
            y += 24;
        }

        pushFrame(mFrameBitmap);
    }
}
