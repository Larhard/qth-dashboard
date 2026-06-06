package com.elgassia.qthdashboard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import kotlin.math.abs

/**
 * Hosts the floating compass overlay ([OverlayView]) in a system window so it
 * stays on top of other apps.  Runs as a foreground service so the process stays
 * alive while the user is in another app.  Only ever started when the user
 * explicitly enables the overlay.
 *
 * Data source: ONLY the foreground Flutter app, via [update]. It alone knows the
 * heading-source rules (GPS/TRK/MAG, auto vs explicit) and the live nav data, so it
 * is the single authority for what the overlay shows. There is deliberately NO
 * native compass fallback — a sensor-driven fallback would show a raw MAG heading
 * that ignores those rules and freeze stale POI data. Instead, a watchdog closes
 * the overlay when the app stops pushing (e.g. swiped away): better gone than stale.
 */
class OverlayService : Service() {

    companion object {
        const val ACTION_SHOW = "com.elgassia.qthdashboard.OVERLAY_SHOW"
        const val ACTION_HIDE = "com.elgassia.qthdashboard.OVERLAY_HIDE"
        const val NOTIF_ID    = 3001
        const val CHANNEL_ID  = "overlay_monitor"
        // No frame from the app for this long → assume it's gone; close the overlay.
        const val WATCHDOG_MS = 3000L

        // Live instance so MainActivity's channel can push data without binding.
        @Volatile var instance: OverlayService? = null
        val isRunning: Boolean get() = instance != null
    }

    private var wm: WindowManager? = null
    private var view: OverlayView? = null
    private lateinit var params: WindowManager.LayoutParams

    // Watchdog: the overlay is driven only by the foreground app. If no frame
    // arrives for WATCHDOG_MS (the app was swiped away / killed), close the overlay
    // rather than leave it frozen on stale data.
    @Volatile private var lastFlutterUpdate = 0L
    private var startedAt = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val watchdog = object : Runnable {
        override fun run() {
            // Reference the later of "service started" and "last frame" so we allow
            // a brief grace for the first push after show().
            val ref = maxOf(lastFlutterUpdate, startedAt)
            if (SystemClock.elapsedRealtime() - ref > WATCHDOG_MS) {
                teardown(); stopSelf(); return   // stop rescheduling
            }
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HIDE -> { teardown(); stopSelf(); return START_NOT_STICKY }
            else -> {
                if (!canDraw()) { stopSelf(); return START_NOT_STICKY }
                startForeground(NOTIF_ID, notification())
                addOverlay()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() { teardown(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null

    private fun canDraw(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    // ── Overlay window ──────────────────────────────────────────────────────────

    private fun addOverlay() {
        if (view != null) return
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val v = OverlayView(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (24 * resources.displayMetrics.density).toInt()
            y = (120 * resources.displayMetrics.density).toInt()
        }

        attachDragAndTap(v)
        try { wm?.addView(v, params); view = v; instance = this } catch (_: Exception) { stopSelf() }
        startWatchdog()
    }

    // ── Watchdog (close the overlay when the app stops driving it) ───────────────

    private fun startWatchdog() {
        startedAt = SystemClock.elapsedRealtime()
        handler.removeCallbacks(watchdog)
        handler.postDelayed(watchdog, 1000L)
    }

    private fun stopWatchdog() {
        handler.removeCallbacks(watchdog)
    }

    private fun attachDragAndTap(v: View) {
        var downX = 0f; var downY = 0f
        var startX = 0; var startY = 0
        var moved = false
        val touchSlop = 8 * resources.displayMetrics.density
        v.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    startX = params.x; startY = params.y; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX; val dy = e.rawY - downY
                    if (abs(dx) > touchSlop || abs(dy) > touchSlop) moved = true
                    params.x = startX + dx.toInt()
                    params.y = startY + dy.toInt()
                    try { wm?.updateViewLayout(v, params) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) openApp()   // tap (not drag) → open the app
                    true
                }
                else -> false
            }
        }
    }

    private fun openApp() {
        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                         Intent.FLAG_ACTIVITY_SINGLE_TOP or
                         Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            })
        } catch (_: Exception) {}
    }

    private fun teardown() {
        stopWatchdog()
        try { view?.let { wm?.removeView(it) } } catch (_: Exception) {}
        view = null
        instance = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
            stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
    }

    // ── Data push (called by MainActivity channel) ──────────────────────────────

    fun update(
        heading: Double, headingValid: Boolean, windRose: Boolean,
        secondaryBearing: Double?, primaryColor: Long, secondaryColor: Long,
        northColor: Long, ringColor: Long, bgColor: Long, textColor: Long,
        lineLabels: Array<String>, lineValues: Array<String>, lineColors: IntArray,
        markerBearings: DoubleArray, markerColors: IntArray, markerScales: DoubleArray,
    ) {
        lastFlutterUpdate = SystemClock.elapsedRealtime() // Flutter is alive → it drives
        val v = view ?: return
        v.heading = heading.toFloat()
        v.headingValid = headingValid
        v.windRose = windRose
        v.secondaryBearing = secondaryBearing?.toFloat() ?: Float.NaN
        v.primaryColor = primaryColor.toInt()
        v.secondaryColor = secondaryColor.toInt()
        v.northColor = northColor.toInt()
        v.ringColor = ringColor.toInt()
        v.bgColor = bgColor.toInt()
        v.textColor = textColor.toInt()
        v.lineLabels = lineLabels
        v.lineValues = lineValues
        v.lineColors = lineColors
        v.markerBearings = markerBearings
        v.markerColors = markerColors
        v.markerScales = markerScales
        v.applyData()
    }

    // ── Notification ──────────────────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Floating Compass",
                NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows the floating compass over other apps"
                setSound(null, null)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
        }
    }

    private fun notification(): Notification {
        val tap = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else
            @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setContentTitle("QTH floating compass")
            .setContentText("Tap to open the dashboard")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(tap)
            .setOngoing(true)
            .build()
    }
}
