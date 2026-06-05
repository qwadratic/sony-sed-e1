package com.explorer.demos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;

import com.sony.smarteyeglass.extension.util.SmartEyeglassControlUtils;

import java.util.Timer;
import java.util.TimerTask;

/**
 * Demo 3: Graphics & Shapes
 * Tap cycles: rects, circles, arcs, wireframe cube (rotating).
 */
public class GraphicsDemo extends BaseDemo {

    private static final int MODE_SHAPES = 0;
    private static final int MODE_CUBE   = 1;
    private static final int MODE_COUNT  = 2;
    private int mMode = MODE_SHAPES;

    private Timer mTimer;
    private Bitmap mFrameBitmap;
    private float mCubeAngle = 0;

    private final Paint mPaint;

    public GraphicsDemo(SmartEyeglassControlUtils utils, Context context) {
        super(utils, context);
        mPaint = new Paint();
        mPaint.setColor(Color.WHITE);
        mPaint.setAntiAlias(false);
        mPaint.setStyle(Paint.Style.STROKE);
        mPaint.setStrokeWidth(1.5f);
    }

    public String getName() { return "Display: Graphics"; }

    public void onEnter() {
        mMode = MODE_SHAPES;
        mFrameBitmap = Bitmap.createBitmap(419, 138, Bitmap.Config.ARGB_8888);
        renderCurrent();
    }

    public void onExit() {
        stopTimer();
    }

    public void onTap() {
        mMode = (mMode + 1) % MODE_COUNT;
        stopTimer();
        renderCurrent();
    }

    public void onSwipe(int direction) {}

    private void renderCurrent() {
        if (mMode == MODE_SHAPES) {
            renderShapes();
        } else {
            startCubeLoop();
        }
    }

    private void renderShapes() {
        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);

        // Rectangles
        c.drawRect(8, 8, 80, 50, mPaint);
        c.drawRect(90, 8, 162, 50, mPaint);

        // Filled rect
        Paint fill = new Paint(mPaint);
        fill.setStyle(Paint.Style.FILL);
        c.drawRect(172, 8, 230, 50, fill);

        // Circles
        c.drawCircle(50, 90, 30, mPaint);
        c.drawCircle(130, 90, 20, mPaint);
        c.drawCircle(200, 90, 10, mPaint);

        // Arcs
        RectF arc1 = new RectF(240, 10, 340, 110);
        c.drawArc(arc1, 0, 180, false, mPaint);
        c.drawArc(arc1, 180, 90, true, mPaint);

        // Lines star pattern
        for (int i = 0; i < 8; i++) {
            float a = (float)(i * Math.PI / 4);
            float x2 = 390 + 30 * (float)Math.cos(a);
            float y2 = 69 + 60 * (float)Math.sin(a);
            c.drawLine(390, 69, x2, y2, mPaint);
        }

        Paint lbl = new Paint();
        lbl.setColor(Color.GRAY);
        lbl.setTextSize(14);
        c.drawText("[tap] wireframe cube", 8, 132, lbl);

        pushFrame(mFrameBitmap);
    }

    private void startCubeLoop() {
        mTimer = new Timer("cube-loop", true);
        mTimer.scheduleAtFixedRate(new TimerTask() {
            public void run() {
                mCubeAngle += 2f;
                renderCube();
            }
        }, 0, 66);
    }

    private void renderCube() {
        Canvas c = new Canvas(mFrameBitmap);
        c.drawColor(Color.BLACK);

        // Simple wireframe cube via projection
        float cx = 209, cy = 60;
        float s = 40;
        float a = (float)Math.toRadians(mCubeAngle);
        float b = (float)Math.toRadians(mCubeAngle * 0.7f);

        float cosA = (float)Math.cos(a), sinA = (float)Math.sin(a);
        float cosB = (float)Math.cos(b), sinB = (float)Math.sin(b);

        float[][] verts = {
            {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
            {-1,-1, 1},{1,-1, 1},{1,1, 1},{-1,1, 1}
        };

        float[][] proj = new float[8][2];
        for (int i = 0; i < 8; i++) {
            float x = verts[i][0], y = verts[i][1], z = verts[i][2];
            // Rotate Y
            float x1 = x * cosA - z * sinA;
            float z1 = x * sinA + z * cosA;
            // Rotate X
            float y1 = y * cosB - z1 * sinB;
            float z2 = y * sinB + z1 * cosB;
            // Simple perspective
            float d = 1.0f + z2 * 0.3f;
            proj[i][0] = cx + x1 * s / d;
            proj[i][1] = cy + y1 * s / d;
        }

        // Draw 12 edges
        int[][] edges = {
            {0,1},{1,2},{2,3},{3,0},
            {4,5},{5,6},{6,7},{7,4},
            {0,4},{1,5},{2,6},{3,7}
        };
        for (int[] e : edges) {
            c.drawLine(proj[e[0]][0], proj[e[0]][1],
                       proj[e[1]][0], proj[e[1]][1], mPaint);
        }

        Paint lbl = new Paint();
        lbl.setColor(Color.GRAY);
        lbl.setTextSize(14);
        c.drawText("Rotating cube  [tap] shapes", 8, 132, lbl);

        pushFrame(mFrameBitmap);
    }

    private void stopTimer() {
        if (mTimer != null) {
            mTimer.cancel();
            mTimer = null;
        }
    }
}
