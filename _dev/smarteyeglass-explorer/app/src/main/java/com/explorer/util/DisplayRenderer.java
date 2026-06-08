package com.explorer.util;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;

/**
 * Shared canvas/bitmap helpers for the 419x138 monochrome green display.
 * All content: white on black (SDK converts to green on device).
 */
public class DisplayRenderer {

    public static final int WIDTH = 419;
    public static final int HEIGHT = 138;

    // Line height in pixels for default 22sp font
    public static final int LINE_H = 28;
    // Y position of first body line (below header separator at y=24)
    public static final int BODY_Y_START = 52;

    private static final Paint sDefaultPaint;
    private static final Paint sHeaderPaint;
    private static final Paint sFooterPaint;

    static {
        sDefaultPaint = new Paint();
        sDefaultPaint.setColor(Color.WHITE);
        sDefaultPaint.setTextSize(22);
        sDefaultPaint.setTypeface(Typeface.MONOSPACE);
        sDefaultPaint.setAntiAlias(false);

        sHeaderPaint = new Paint(sDefaultPaint);
        sHeaderPaint.setTextSize(18);

        sFooterPaint = new Paint(sDefaultPaint);
        sFooterPaint.setTextSize(14);
        sFooterPaint.setColor(Color.GRAY);
    }

    /** Allocate a blank black frame. */
    public static Bitmap createFrame() {
        Bitmap bmp = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        c.drawColor(Color.BLACK);
        return bmp;
    }

    /**
     * Clear an existing bitmap to black (reuse instead of allocating).
     * Returns a fresh Canvas wrapping it.
     */
    public static Canvas clearFrame(Bitmap bmp) {
        Canvas c = new Canvas(bmp);
        c.drawColor(Color.BLACK);
        return c;
    }

    /**
     * Draw title + page indicator in header area, with separator line.
     */
    public static void drawHeader(Canvas c, String title, String pageInfo) {
        c.drawText(title, 8, 18, sHeaderPaint);
        float w = sHeaderPaint.measureText(pageInfo);
        c.drawText(pageInfo, WIDTH - w - 8, 18, sHeaderPaint);
        Paint linePaint = new Paint();
        linePaint.setColor(Color.WHITE);
        linePaint.setStrokeWidth(1);
        c.drawLine(0, 24, WIDTH, 24, linePaint);
    }

    /**
     * Draw up to 4 lines of body text starting at BODY_Y_START.
     */
    public static void drawBody(Canvas c, String[] lines) {
        int y = BODY_Y_START;
        for (String line : lines) {
            if (line == null) break;
            c.drawText(line, 8, y, sDefaultPaint);
            y += LINE_H;
        }
    }

    /**
     * Draw a single footer hint at the bottom.
     */
    public static void drawFooter(Canvas c, String hint) {
        c.drawText(hint, 8, HEIGHT - 6, sFooterPaint);
    }

    /**
     * Draw a full screen: header + body lines + footer.
     */
    public static Bitmap renderScreen(String title, String pageInfo,
                                      String[] bodyLines, String footer) {
        Bitmap bmp = createFrame();
        Canvas c = new Canvas(bmp);
        drawHeader(c, title, pageInfo);
        drawBody(c, bodyLines);
        drawFooter(c, footer);
        return bmp;
    }

    /**
     * Render a simple full-screen message (no header/footer chrome).
     */
    public static Bitmap renderMessage(String line1, String line2,
                                       String line3, String line4) {
        Bitmap bmp = createFrame();
        Canvas c = new Canvas(bmp);
        Paint p = new Paint(sDefaultPaint);
        if (line1 != null) c.drawText(line1, 8, 30, p);
        if (line2 != null) c.drawText(line2, 8, 58, p);
        if (line3 != null) c.drawText(line3, 8, 86, p);
        if (line4 != null) c.drawText(line4, 8, 114, p);
        return bmp;
    }

    /**
     * Truncate a string to fit in the display width at default font size.
     * Rough heuristic: ~30 chars at size 22 monospace.
     */
    public static String truncate(String s, int maxChars) {
        if (s == null) return "";
        if (s.length() <= maxChars) return s;
        return s.substring(0, maxChars - 1) + "~";
    }
}
