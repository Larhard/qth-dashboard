package com.elgassia.qthdashboard

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.GnssStatus
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import kotlin.math.roundToInt

/**
 * Foreground service that keeps the anchor alarm alive even when the Flutter
 * activity is killed.  It feeds GPS / GNSS / battery / ticks into [AnchorController]
 * (the single authority) and owns the persistent notification.
 *
 * Reliability measures:
 *   • Holds a PARTIAL_WAKE_LOCK while anchored so Doze/idle can't stop GPS — the
 *     root cause of "stationary stops updating".
 *   • Requests GPS_PROVIDER updates at 1 Hz / 0 m so a stationary receiver keeps
 *     delivering the same fix.
 *   • Registers a GNSS status callback so the controller can tell "stationary"
 *     (satellites still used) from "really lost" (no satellites).
 *   • Monitors battery natively (works even when the app is closed).
 *
 * Survival: state is persisted to SharedPreferences; START_STICKY + the null-intent
 * restore path + [BootReceiver] bring it back after a kill or reboot.
 */
class AnchorMonitorService : Service() {

    companion object {
        const val ACTION_START = "com.elgassia.qthdashboard.ANCHOR_START"
        const val ACTION_STOP  = "com.elgassia.qthdashboard.ANCHOR_STOP"
        const val NOTIF_ID     = 2001
        const val CHANNEL_ID   = "anchor_monitor"
        const val PREFS_NAME   = "anchor_monitor_state"
    }

    private var locManager: LocationManager? = null
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        AnchorController.onStateChanged   = { updateNotification() }
        AnchorController.onAlarmEscalated = { launchActivity() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startMonitoring(
                intent.getDoubleExtra("lat", 0.0),
                intent.getDoubleExtra("lon", 0.0),
                intent.getDoubleExtra("radius", 50.0),
                intent.getDoubleExtra("warnFrac", 0.80),
                persist = true)
            ACTION_STOP -> {
                clearState()
                AnchorController.stopAll()
                stopEverything()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    stopForeground(STOP_FOREGROUND_REMOVE)
                else @Suppress("DEPRECATION") stopForeground(true)
                stopSelf()
            }
            null -> {
                // START_STICKY restart after a kill — restore from prefs.
                val p = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                if (!p.getBoolean("active", false)) { stopSelf(); return START_NOT_STICKY }
                startMonitoring(
                    p.getFloat("lat", 0f).toDouble(),
                    p.getFloat("lon", 0f).toDouble(),
                    p.getFloat("radius", 50f).toDouble(),
                    p.getFloat("warnFrac", 0.80f).toDouble(),
                    persist = false)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopEverything()
        AnchorController.onStateChanged = null
        AnchorController.onAlarmEscalated = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startMonitoring(lat: Double, lon: Double, r: Double, wf: Double, persist: Boolean) {
        if (persist) saveState(lat, lon, r, wf)
        AnchorController.start(this, lat, lon, r, wf)
        startForeground(NOTIF_ID, buildNotification())
        acquireWakeLock()
        startGps()
        registerBattery()
        startTicker()
    }

    private fun stopEverything() {
        stopGps(); stopTicker(); unregisterBattery(); releaseWakeLock()
    }

    // ── State persistence ────────────────────────────────────────────────────────

    private fun saveState(lat: Double, lon: Double, r: Double, wf: Double) =
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
            .putBoolean("active", true)
            .putFloat("lat", lat.toFloat()).putFloat("lon", lon.toFloat())
            .putFloat("radius", r.toFloat()).putFloat("warnFrac", wf.toFloat())
            .apply()

    private fun clearState() =
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().clear().apply()

    // ── Wake lock (defeats Doze so GPS keeps flowing when stationary) ────────────

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "QTHDashboard:Anchor")
            wakeLock?.acquire()  // held until the anchor is lifted
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
    }

    // ── GPS + GNSS ────────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startGps() {
        locManager = getSystemService(LOCATION_SERVICE) as LocationManager
        try {
            // 1 Hz / 0 m: a stationary receiver keeps delivering the same fix.
            locManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1_000L, 0f, locationListener)
        } catch (_: Exception) {}
        try {
            locManager?.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1_000L, 0f, locationListener)
        } catch (_: Exception) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try { locManager?.registerGnssStatusCallback(gnssCallback, handler) } catch (_: Exception) {}
        }
    }

    private fun stopGps() {
        try { locManager?.removeUpdates(locationListener) } catch (_: Exception) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try { locManager?.unregisterGnssStatusCallback(gnssCallback) } catch (_: Exception) {}
        }
        locManager = null
    }

    private val locationListener = LocationListener { loc ->
        val acc = if (loc.hasAccuracy()) loc.accuracy.toDouble() else -1.0
        AnchorController.onPosition(loc.latitude, loc.longitude, acc)
    }

    private val gnssCallback = object : GnssStatus.Callback() {
        override fun onSatelliteStatusChanged(status: GnssStatus) {
            var used = 0
            for (i in 0 until status.satelliteCount) if (status.usedInFix(i)) used++
            AnchorController.onGnss(used)
        }
    }

    // ── Battery (native — works even when the app is closed) ─────────────────────

    private var batteryReceiver: BroadcastReceiver? = null

    private fun registerBattery() {
        if (batteryReceiver != null) return
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val pct = if (level >= 0 && scale > 0) (level * 100 / scale) else 100
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                               status == BatteryManager.BATTERY_STATUS_FULL
                AnchorController.onBattery(pct, charging)
            }
        }
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    }

    private fun unregisterBattery() {
        try { batteryReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        batteryReceiver = null
    }

    // ── 1 Hz ticker (drives the GPS-loss timer) ──────────────────────────────────

    private val ticker = object : Runnable {
        override fun run() { AnchorController.tick(); handler.postDelayed(this, 1_000L) }
    }
    private fun startTicker() { handler.removeCallbacks(ticker); handler.post(ticker) }
    private fun stopTicker()  { handler.removeCallbacks(ticker) }

    // ── Activity launch when the alarm is raised ─────────────────────────────────

    private fun launchActivity() {
        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                         Intent.FLAG_ACTIVITY_SINGLE_TOP or
                         Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            })
        } catch (_: Exception) {}
    }

    // ── Notification ──────────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Anchor Monitor",
                NotificationManager.IMPORTANCE_LOW).apply {
                description = "Persistent anchor status — tap to return to QTH Dashboard"
                setSound(null, null); setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val tap = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java)
                .apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val dist = AnchorController.distanceM.roundToInt()
        val rad  = AnchorController.radiusM.roundToInt()
        val (title, text) = when (AnchorController.state) {
            AnchorController.State.ALARM ->
                "⚓ ANCHOR ALARM" to (if (AnchorController.gpsLostSeconds >= 180)
                    "GPS lost ${AnchorController.gpsLostSeconds}s" else "Dragging! $dist m from anchor")
            AnchorController.State.WARNING -> "⚓ Anchor Warning" to "Approaching limit — $dist m of $rad m"
            AnchorController.State.SAFE    -> "⚓ Anchor Active" to "Riding — $dist m of $rad m"
        }
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else
            @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setContentTitle(title).setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(tap).setOngoing(true).setOnlyAlertOnce(true).build()
    }

    private fun updateNotification() {
        try { getSystemService(NotificationManager::class.java)?.notify(NOTIF_ID, buildNotification()) }
        catch (_: Exception) {}
    }
}
