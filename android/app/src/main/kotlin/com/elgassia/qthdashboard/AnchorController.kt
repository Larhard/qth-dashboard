package com.elgassia.qthdashboard

import android.content.Context
import android.location.Location
import android.os.SystemClock
import kotlin.math.max

/**
 * Single source of truth for the anchor alarm — a latching state machine.
 *
 * Owned by no single component: [AnchorMonitorService] feeds it GPS / GNSS /
 * battery / ticks, and [MainActivity] bridges it to Flutter.  Everything runs on
 * the one main thread (the service and activity share it), so there is no locking
 * and no race.
 *
 * Design goals (bulletproof reliability):
 *   • A coarse (NETWORK / low-accuracy) fix never moves the anchor distance — only
 *     accurate fixes do — so a bad fix can't flash a false alarm.
 *   • Position level has HYSTERESIS — jitter at the boundary can't chatter.
 *   • "GPS lost" means REALLY lost (no fix AND no satellites in fix), never just
 *     "stationary and not pushing updates" (the service holds a wake-lock and asks
 *     for 1 Hz updates so a stationary receiver keeps delivering).
 *   • The ALARM state LATCHES: once raised it stays until the user mutes it
 *     (3-second hold) — returning inside the radius does NOT silence it.
 *   • WARNING auto-clears when the boat returns to the safe zone.
 *   • After muting, the alarm re-arms only once the boat is safe again.
 *
 * State ordinals match the Dart AnchorAlarmLevel enum: SAFE=0, WARNING=1, ALARM=2.
 */
object AnchorController {

    enum class State { SAFE, WARNING, ALARM }

    // ── Configuration ────────────────────────────────────────────────────────
    @Volatile var active = false;  private set
    @Volatile var lat = 0.0;       private set
    @Volatile var lon = 0.0;       private set
    @Volatile var radiusM = 50.0;  private set   // 10..1000
    @Volatile var warnFrac = 0.80; private set

    // ── Live state ────────────────────────────────────────────────────────────
    @Volatile var distanceM = 0.0;     private set
    @Volatile var bearingDeg = 0.0;    private set
    @Volatile var gpsLostSeconds = 0;  private set
    @Volatile var hasFix = false;      private set
    @Volatile var state = State.SAFE;  private set
    @Volatile var muted = false;       private set   // muted-until-safe

    // ── Internal ───────────────────────────────────────────────────────────────
    private var posLevel = 0                 // position level with hysteresis (0/1/2)
    private var lastFixElapsed = 0L          // SystemClock.elapsedRealtime of last fix
    private var satsUsedInFix = -1           // GNSS satellites used (-1 = unknown)
    private var batteryPct = 100
    private var charging = true
    private var alarm: AnchorAlarmManager? = null

    /** Service sets this to refresh its notification on every state change. */
    var onStateChanged: (() -> Unit)? = null
    /** Service sets this to launch the activity when the alarm is first raised. */
    var onAlarmEscalated: (() -> Unit)? = null

    // Tunables
    private const val GPS_NOFIX_GRACE_S = 8      // a real receiver delivers ≤1 Hz
    private const val GPS_WARN_S = 60
    private const val GPS_ALARM_S = 180
    private const val BATT_WARN_PCT = 20
    private const val BATT_ALARM_PCT = 7
    // Accuracy gate: a fix must be at least this accurate to count for distance.
    // Cleanly separates GPS (≈5–20 m) from coarse NETWORK fixes (≥50 m).
    private const val GATE_MIN_M = 12.0
    private const val GATE_MAX_M = 30.0

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    fun start(ctx: Context, lat: Double, lon: Double, radiusM: Double, warnFrac: Double) {
        alarm = AnchorAlarmManager.getInstance(ctx)
        val coercedRadius = radiusM.coerceIn(10.0, 1000.0)
        // start() is delivered TWICE for one drop — once in-process by MainActivity
        // (so the alarm arms instantly) and once by the service (for survival).  If
        // we're already monitoring this very anchor, keep the LIVE state: re-running
        // the reset would wipe a latched alarm or the muted flag.
        val sameAnchor = active &&
            Math.abs(this.lat - lat) < 1e-7 &&
            Math.abs(this.lon - lon) < 1e-7 &&
            Math.abs(this.radiusM - coercedRadius) < 0.5
        this.lat = lat; this.lon = lon
        this.radiusM = coercedRadius
        this.warnFrac = warnFrac.coerceIn(0.50, 0.95)
        if (sameAnchor) { active = true; onStateChanged?.invoke(); return }
        active = true
        distanceM = 0.0; bearingDeg = 0.0
        gpsLostSeconds = 0; hasFix = false
        state = State.SAFE; muted = false; posLevel = 0
        satsUsedInFix = -1; batteryPct = 100; charging = true
        lastFixElapsed = SystemClock.elapsedRealtime()
        onStateChanged?.invoke()
    }

    fun stopAll() {
        active = false
        state = State.SAFE; muted = false; posLevel = 0
        gpsLostSeconds = 0; hasFix = false
        alarm?.stop()
        onStateChanged?.invoke()
    }

    // ── Inputs ──────────────────────────────────────────────────────────────────

    /**
     * A GPS fix.  [accuracyM] = horizontal accuracy in metres (<0 if unknown).
     *
     * Only a PRECISE fix is used: it moves the anchor distance AND resets the
     * liveness timer.  The gate is capped at [GATE_MAX_M] so a coarse fix
     * (typically ≥50 m) can never move the distance — not even for a large radius —
     * while every genuine GPS fix (≈5–20 m) is accepted.  A coarse fix is ignored
     * entirely, so it can neither corrupt the distance nor mask a real GPS loss.
     */
    fun onPosition(lat: Double, lon: Double, accuracyM: Double = -1.0) {
        if (!active) return
        val gate = (radiusM * 0.25).coerceIn(GATE_MIN_M, GATE_MAX_M)
        val precise = accuracyM < 0 || accuracyM <= gate
        if (precise) {
            lastFixElapsed = SystemClock.elapsedRealtime()   // liveness from good fixes only
            val d = FloatArray(2)
            Location.distanceBetween(lat, lon, this.lat, this.lon, d)
            distanceM = d[0].toDouble()
            bearingDeg = (d[1] + 360.0) % 360.0
            hasFix = true
        }
        evaluate()
    }

    /** GNSS satellite status — distinguishes "stationary" (sats>0) from "lost".
     *  Just records the count; the 1 Hz [tick] is the single place that derives the
     *  loss duration, so there's no need to re-run the state machine here (the
     *  callback can fire several times a second). */
    fun onGnss(satellitesUsedInFix: Int) {
        satsUsedInFix = satellitesUsedInFix
    }

    /** Battery state from the service's ACTION_BATTERY_CHANGED receiver. */
    fun onBattery(pct: Int, charging: Boolean) {
        this.batteryPct = pct
        this.charging = charging
        evaluate()
    }

    /** Periodic 1 Hz tick — re-derives the GPS-loss duration. */
    fun tick() {
        if (!active) return
        val noFix = ((SystemClock.elapsedRealtime() - lastFixElapsed) / 1000L).toInt()
        // "Really lost" needs BOTH: no precise fix for a while AND a CONFIRMED zero
        // satellites used in the fix (satsUsedInFix == 0, reported by the GNSS
        // callback).  This is what guarantees a STATIONARY boat with strong signal
        // never warns:
        //   • A stationary receiver with a fix keeps delivering 1 Hz updates (we
        //     requested GPS at 1 Hz / 0 m), so noFix stays ~0 — the timer never grows.
        //   • Even if updates paused, as long as satellites are still used (> 0) we
        //     KNOW the receiver is fine, so the timer is held at zero.
        // satsUsedInFix == -1 means "not yet reported" (cold start) and is treated as
        // NOT lost, so acquisition can't false-trigger a loss.
        val reallyLost = noFix > GPS_NOFIX_GRACE_S && satsUsedInFix == 0
        gpsLostSeconds = if (reallyLost) noFix else 0
        evaluate()
    }

    /** User acknowledged the alarm (3-second hold). Silences until safe again. */
    fun mute() {
        muted = true
        state = State.SAFE
        applyHardware()
        onStateChanged?.invoke()
    }

    // ── Snapshot for the Flutter side ────────────────────────────────────────────

    fun snapshot(): Map<String, Any> = mapOf(
        "active"         to active,
        "level"          to state.ordinal,   // 0 safe, 1 warning, 2 alarm
        "distanceM"      to distanceM,
        "bearingDeg"     to bearingDeg,
        "gpsLossSeconds" to gpsLostSeconds,
        "muted"          to muted,
        "hasFix"         to hasFix,
        "radiusM"        to radiusM,
        "warnFrac"       to warnFrac,
        "batteryPct"     to batteryPct,
        "charging"       to charging,
    )

    // ── Core state machine ────────────────────────────────────────────────────────

    private fun evaluate() {
        if (!active) return
        posLevel = positionLevelWithHysteresis()
        val gpsLevel = when {
            gpsLostSeconds >= GPS_ALARM_S -> 2
            gpsLostSeconds >= GPS_WARN_S  -> 1
            else -> 0
        }
        val battLevel = when {
            !charging && batteryPct in 0..BATT_ALARM_PCT -> 2
            !charging && batteryPct in 0..BATT_WARN_PCT  -> 1
            else -> 0
        }
        val cond = maxOf(posLevel, gpsLevel, battLevel)
        val prev = state

        if (muted) {
            // Acknowledged: stay quiet until the boat is fully safe, then re-arm.
            if (cond == 0) muted = false
            state = State.SAFE
        } else {
            state = when {
                state == State.ALARM -> State.ALARM   // ALARM latches until muted
                cond == 2 -> State.ALARM
                cond == 1 -> State.WARNING
                else -> State.SAFE
            }
        }

        if (state != prev) {
            applyHardware()
            if (state == State.ALARM) onAlarmEscalated?.invoke()
        }
        onStateChanged?.invoke()  // always — keeps the notification distance fresh
    }

    /**
     * Position level with hysteresis: once a level is entered it is only left after
     * coming back inside by a margin (≥5 m or 5 % of radius).  Prevents boundary
     * jitter from chattering the alarm.
     */
    private fun positionLevelWithHysteresis(): Int {
        if (!hasFix) return 0
        val margin = max(5.0, radiusM * 0.05)
        val alarmThresh = if (posLevel >= 2) radiusM - margin else radiusM
        val warnThresh  = if (posLevel >= 1) radiusM * warnFrac - margin else radiusM * warnFrac
        return when {
            distanceM >= alarmThresh -> 2
            distanceM >= warnThresh  -> 1
            else -> 0
        }
    }

    private fun applyHardware() {
        when (state) {
            State.ALARM   -> alarm?.startAlarm()
            State.WARNING -> alarm?.startWarning()
            State.SAFE    -> alarm?.stop()
        }
    }
}
