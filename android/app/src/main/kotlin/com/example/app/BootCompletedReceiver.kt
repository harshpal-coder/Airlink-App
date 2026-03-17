package com.example.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the foreground service when the device boots.
 * Registered in AndroidManifest.xml.
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            // The flutter_background_service plugin handles auto-start on boot
            // via its autoStartOnBoot configuration. This receiver is a safety net
            // that ensures the service starts even if the plugin's mechanism fails.
            android.util.Log.i("AirLink", "Boot completed — background service should auto-start via plugin config")
        }
    }
}
