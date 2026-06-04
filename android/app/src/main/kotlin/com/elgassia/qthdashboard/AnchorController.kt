package com.elgassia.qthdashboard

import android.content.Context
import android.location.Location
import android.os.SystemClock
import kotlin.math.max

/**
 * Single source of truth for the anchor alarm — a latching state machine.
 *
 * Owned by no single component: [AnchorMonitorService] feeds it GPS / battery /
 * ticks, and [MainActivity] bridges it to Flutter.  Everything runs on the one main
 * thread (the service and activity share it), so there is no locking and no race.
 *
 * Design goals (bulletproof reliability — false alarms make the feature unusable):
 *
 *   • LIVENESS IS DECOUPLED FROM PRECISION.  *Any* fix — at *any* accuracy — proves
 *     the receiver is alive and resets the GPS-loss timer.  A working GPS keeps
 *     delivering fixes even when stationary (and even when accuracy fluctuates); it
 *     only goes silent when the fix is genuinely lost.  So "GPS lost" is decided
 *     purely by liveness: no fix at all for a sustained time.  This is what stops a
 *     stationary boat from ever false-alarming — the previous design wrongly
 *     required *accurate* fixes for liveness, so a flat/obstructed phone whose
 *     accuracy drifted above the gate looked "lost" while GPS was working fine.
 *
 *   • DISTANCE uses a LENIENT accuracy gate (so real drag is never missed) that
 *     still rejects clearly-broken fixes, plus a short DEBOUNCE so a single bad fix
 *     can never latch the alarm — the out-of-range condition must persist.
 *
 *   • Position level has HYSTERESIS — jitter at the boundary can't chatter.
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
    private var posLevel = 0                 // effective (debounced) position level
    private var lastFixElapsed = 0L          // SystemClock.elapsedRealtime of last fix
    private var posWarnSinceMs = 0L          // when distance first reached warn level (0 = not now)
    private var posAlarmSinceMs = 0L         // when distance first reached alarm level (0 = not now)
    private var batteryPct = 100
    private var charging = true
    private var alarm: AnchorAlarmManager? = null

    /** Service sets this to refresh its notification on every state change. */
    var onStateChanged: (() -> Unit)? = null
    /** Service sets this to launch the activity when the alarm is first raised. */
    var onAlarmEscalated: (() -> Unit)? = null

    // Tunables
    private const val GPS_NOFIX_GRACE_S = 10     // brief gaps are normal; ignore them
    private const val GPS_WARN_S = 60            // no fix this long → warning
    private const val GPS_ALARM_S = 180          // no fix this long → alarm
    private const val BATT_WARN_PCT = 20
    private const val BATT_ALARM_PCT = 7
    // Distance accuracy gate: a fix may move the distance only if its accuracy is
    // within max(radius, FLOOR).  Lenient on purpose — rejecting good-enough fixes
    // would risk MISSING a real drag.  Clearly-broken fixes are still rejected.
    private const val POS_GATE_FLOOR_M = 50.0
    // Debounce: the out-of-range condition must persist this long before escalating,
    // so a lone spurious fix can't raise (and, for ALARM, latch) a false alarm.
    private const val POS_WARN_DEBOUNCE_MS = 4_000L
    private const val POS_ALARM_DEBOUNCE_MS = 8_000L

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
        posWarnSinceMs = 0L; posAlarmSinceMs = 0L
        batteryPct = 100; charging = true
        lastFixElapsed = SystemClock.elapsedRealtime()
        onStateChanged?.invoke()
    }

    fun stopAll() {
        active = false
        state = State.SAFE; muted = false; posLevel = 0
        posWarnSinceMs = 0L; posAlarmSinceMs = 0L
        gpsLostSeconds = 0; hasFix = false
        alarm?.stop()
        onStateChanged?.invoke()
    }

    // ── Inputs ──────────────────────────────────────────────────────────────────

    /**
     * A GPS fix.  [accuracyM] = horizontal accuracy in metres (<0 if unknown).
     *
     * ANY fix resets the liveness timer (a fix means the receiver is alive — that is
     * the whole anti-false-alarm guarantee).  The distance is updated only from a
     * usable fix (lenient gate); the evaluate() debounce then prevents a lone bad
     * fix from latching the alarm.
     */
    fun onPosition(lat: Double, lon: Double, accuracyM: Double = -1.0) {
        if (!active) return
        lastFixElapsed = SystemClock.elapsedRealtime()
        val gate = max(radiusM, POS_GATE_FLOOR_M)
        if (accuracyM < 0 || accuracyM <= gate) {
            val d = FloatArray(2)
            Location.distanceBetween(lat, lon, this.lat, this.lon, d)
            distanceM = d[0].toDouble()
            bearingDeg = (d[1] + 360.0) % 360.0
            hasFix = true
        }
        evaluate()
    }

    /** Battery state from the service's ACTION_BATTERY_CHANGED receiver. */
    fun onBattery(pct: Int, charging: Boolean) {
        this.batteryPct = pct
        this.charging = charging
        evaluate()
    }

    /** Periodic 1 Hz tick — re-derives the GPS-loss duration (pure liveness). */
    fun tick() {
        if (!active) return
        val noFix = ((SystemClock.elapsedRealtime() - lastFixElapsed) / 1000L).toInt()
        gpsLostSeconds = if (noFix > GPS_NOFIX_GRACE_S) noFix else 0
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
        val posEff = positionLevelDebounced()
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
        val cond = maxOf(posEff, gpsLevel, battLevel)
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
     * Effective position level (0/1/2) after hysteresis AND debounce.
     *
     * The raw level (with hysteresis) must persist for the debounce window before it
     * counts, so a single spurious fix can't raise — or, since ALARM latches, lock
     * in — a false alarm.  A return inside the radius clears the timers immediately.
     */
    private fun positionLevelDebounced(): Int {
        val raw = rawPositionLevel()
        val now = SystemClock.elapsedRealtime()
        posAlarmSinceMs = if (raw >= 2) (if (posAlarmSinceMs == 0L) now else posAlarmSinceMs) else 0L
        posWarnSinceMs  = if (raw >= 1) (if (posWarnSinceMs  == 0L) now else posWarnSinceMs)  else 0L
        val eff = when {
            posAlarmSinceMs != 0L && now - posAlarmSinceMs >= POS_ALARM_DEBOUNCE_MS -> 2
            posWarnSinceMs  != 0L && now - posWarnSinceMs  >= POS_WARN_DEBOUNCE_MS  -> 1
            else -> 0
        }
        posLevel = eff   // feed back into the hysteresis thresholds
        return eff
    }

    /**
     * Raw position level with hysteresis: once a level is entered it is only left
     * after coming back inside by a margin (≥5 m or 5 % of radius).
     */
    private fun rawPositionLevel(): Int {
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
