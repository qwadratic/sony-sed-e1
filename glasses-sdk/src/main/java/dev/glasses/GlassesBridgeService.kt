package dev.glasses

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * Long-running service that keeps the SDK alive.
 * Smart Connect binds to this via the EXTENSION intent-filter.
 * Auto-started from RegistrationReceiver — apps don't start this directly.
 */
class GlassesBridgeService : Service() {

    companion object {
        private const val TAG = "GlassesBridgeService"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service started")
        // Ensure bridge singleton is alive
        GlassesBridge.getInstance(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.action?.let { action ->
            Log.d(TAG, "Received: $action")
            // Re-trigger registration on every start
            GlassesBridge.getInstance(applicationContext)
        }
        // STICKY: restart if killed, without re-delivering intent
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service stopped")
    }
}
