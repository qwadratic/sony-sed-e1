package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;

import com.explorer.util.DisplayRenderer;
import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;

/**
 * Demo 1: Text Rendering
 * Cycles through font sizes on tap to show legibility tradeoffs.
 */
public class TextDemo extends BaseDemo {

    private static final int[] FONT_SIZES = {16, 20, 24, 28};
    private int mSizeIndex = 2; // start at 24

    public TextDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
    }

    public String getName() { return "Display: Text"; }

    public void onEnter() {
        mSizeIndex = 2;
        render();
    }

    public void onExit() { /* nothing to clean up */ }

    public void onTap() {
        mSizeIndex = (mSizeIndex + 1) % FONT_SIZES.length;
        render();
    }

    public void onSwipe(int direction) { /* swipe handled by parent menu */ }

    private void render() {
        int size = FONT_SIZES[mSizeIndex];
        Bitmap bmp = DisplayRenderer.createFrame();
        Canvas c = new Canvas(bmp);

        Paint p = new Paint();
        p.setColor(Color.WHITE);
        p.setTypeface(Typeface.MONOSPACE);
        p.setAntiAlias(false);
        p.setTextSize(size);

        int lineH = size + 6;
        int y = lineH;
        c.drawText("Font size: " + size + "px", 8, y, p); y += lineH;
        c.drawText("ABCDEFGHIJKLMNOPQRSTUVWX", 8, y, p); y += lineH;
        c.drawText("abcdefghijklmnopqrstuvwx", 8, y, p); y += lineH;
        c.drawText("0123456789 !@#$%^&*()", 8, y, p);

        Paint fp = new Paint();
        fp.setColor(Color.GRAY);
        fp.setTextSize(14);
        fp.setAntiAlias(false);
        c.drawText("[tap] cycle size " + mSizeIndex + "/4", 8, 132, fp);

        pushFrame(bmp);
    }
}
