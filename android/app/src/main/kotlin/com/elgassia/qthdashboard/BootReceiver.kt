package com.elgassia.qthdashboard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Restarts the anchor monitor service after a device reboot (or crash-reboot).
 *
 * If an anchor was deployed before the device powered off, the alarm must keep
 * protecting the boat once the device comes back up — without requiring the user
 * to reopen the app.  This receiver reads the same SharedPreferences the service
 * persists ([AnchorMonitorService.PREFS_NAME]); if an anchor is active it
 * restarts the foreground service with the saved configuration.
 *
 * Does nothing (zero overhead) when no anchor is deployed.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON") return

        val prefs = context.getSharedPreferences(
            AnchorMonitorService.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return // no anchor → nothing to do

        val svc = Intent(context, AnchorMonitorService::class.java).apply {
            this.action = AnchorMonitorService.ACTION_START
            putExtra("lat",      prefs.getFloat("lat", 0f).toDouble())
            putExtra("lon",      prefs.getFloat("lon", 0f).toDouble())
            putExtra("radius",   prefs.getFloat("radius", 50f).toDouble())
            putExtra("warnFrac", prefs.getFloat("warnFrac", 0.80f).toDouble())
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(svc)
            else
                context.startService(svc)
        } catch (_: Exception) {
            // Some OEMs restrict FGS-from-boot; fail silently. The anchor config
            // is still persisted, so reopening the app restores the alarm.
        }
    }
}
