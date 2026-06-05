package dev.glasses

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Wakes up the SDK on Smart Connect registration events.
 * Declared in SDK manifest — calling apps don't need to add anything.
 */
class RegistrationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Touch the singleton — triggers registration if not already done
        GlassesBridge.getInstance(context)
        // Also start GlassesBridgeService to ensure it's running
        context.startService(Intent(context, GlassesBridgeService::class.java).apply {
            action = intent.action
        })
    }
}
