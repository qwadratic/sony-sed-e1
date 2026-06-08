package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;

import com.explorer.util.DisplayRenderer;
import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;

import java.util.Timer;
import java.util.TimerTask;

/**
 * Demo 2: Real-Time Animation
 * Pushes frames at ~15 fps: scanning line bouncing top-to-bottom.
 * Demonstrates continuous bitmap streaming mode.
 */
public class AnimationDemo extends BaseDemo {

    private Timer mTimer;
    private Bitmap mFrameBitmap;   // reused each frame — no per-frame alloc
    private int mScanY = 0;
    private long mStartTime;
    private int mFrameCount = 0;
    private boolean mRunning = false;

    private final Paint mLinePaint;
    private final Paint mTextPaint;

    public AnimationDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
        mLinePaint = new Paint();
        mLinePaint.setColor(Color.WHITE);
        mLinePaint.setStrokeWidth(2);
        mLinePaint.setAntiAlias(false);

        mTextPaint = new Paint();
        mTextPaint.setColor(Color.GRAY);
        mTextPaint.setTextSize(18);
        mTextPaint.setAntiAlias(false);
    }

    public String getName() { return "Display: Animate"; }

    public void onEnter() {
        mFrameBitmap = Bitmap.createBitmap(DisplayRenderer.WIDTH, DisplayRenderer.HEIGHT,
                Bitmap.Config.ARGB_8888);
        mStartTime = System.currentTimeMillis();
        mFrameCount = 0;
        mScanY = 0;
        mRunning = true;
        startLoop();
    }

    public void onExit() {
        mRunning = false;
        if (mTimer != null) {
            mTimer.cancel();
            mTimer = null;
        }
    }

    public void onTap() {
        // toggle pause
        if (mTimer != null) {
            onExit();
            // push static "PAUSED" frame
            pushFrame(DisplayRenderer.renderMessage(
                "Animation PAUSED", "tap to resume", null, null));
        } else {
            mRunning = true;
            startLoop();
        }
    }

    public void onSwipe(int direction) { /* handled by parent */ }

    private void startLoop() {
        mTimer = new Timer("anim-loop", true);
        mTimer.scheduleAtFixedRate(new TimerTask() {
            public void run() {
                if (!mRunning) return;
                renderFrame();
            }
        }, 0, 66); // ~15 fps
    }

    private void renderFrame() {
        mFrameCount++;
        mScanY = (mScanY + 3) % DisplayRenderer.HEIGHT;

        Canvas c = DisplayRenderer.clearFrame(mFrameBitmap);

        // Bouncing scan line
        c.drawLine(0, mScanY, DisplayRenderer.WIDTH, mScanY, mLinePaint);
        // Second line for visual texture
        int y2 = (mScanY + 69) % DisplayRenderer.HEIGHT;
        Paint p2 = new Paint(mLinePaint);
        p2.setAlpha(80);
        c.drawLine(0, y2, DisplayRenderer.WIDTH, y2, p2);

        // FPS readout
        long elapsed = System.currentTimeMillis() - mStartTime;
        float fps = (elapsed > 0) ? (mFrameCount * 1000f / elapsed) : 0;
        c.drawText("frame #" + mFrameCount + "  " + String.format("%.1f", fps) + " fps",
                8, 130, mTextPaint);

        pushFrame(mFrameBitmap);
    }
}
