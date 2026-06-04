package com.elgassia.qthdashboard

/**
 * Centralized native tunables — the ONE place to adjust anchor thresholds, the
 * background GPS cadence, and the alarm-audio parameters.  Call sites reference
 * these named constants; never inline a magic number for a tunable value.
 *
 * `Tuning.Anchor` mirrors the simplified Dart spec in `lib/utils/anchor_math.dart`.
 * The native side is the runtime AUTHORITY (the background service evaluates the
 * alarm with the Flutter engine dead) and has additional robustness the Dart spec
 * does not (hysteresis, debounce, liveness-based GPS loss).  Dart and Kotlin cannot
 * share a compile-time constant, so the GPS-loss timings that must agree are
 * duplicated here and in tuning.dart — keep them in sync (constitution §7.6).
 */
object Tuning {

    /** Anchor alarm state-machine thresholds (see AnchorController). */
    object Anchor {
        const val RADIUS_MIN_M = 10.0
        const val RADIUS_MAX_M = 1000.0
        const val WARN_FRAC_MIN = 0.50
        const val WARN_FRAC_MAX = 0.95

        // GPS-loss escalation (pure liveness: seconds since the last fix of any kind).
        const val GPS_NOFIX_GRACE_S = 10   // brief gaps are normal; ignore them
        const val GPS_WARN_S = 60
        const val GPS_ALARM_S = 180

        // Low-battery escalation (only while NOT charging).
        const val BATT_WARN_PCT = 20
        const val BATT_ALARM_PCT = 7

        // Distance is updated only from a fix at least this accurate (lenient, so a
        // real drag is never missed; clearly-broken fixes are still rejected).
        const val POS_GATE_FLOOR_M = 50.0

        // The out-of-range condition must persist this long before escalating, so a
        // lone spurious fix can't raise (or latch) a false alarm.
        const val POS_WARN_DEBOUNCE_MS = 4_000L
        const val POS_ALARM_DEBOUNCE_MS = 8_000L

        // Hysteresis: a level is only left after coming back inside by this margin.
        const val HYSTERESIS_MIN_M = 5.0
        const val HYSTERESIS_FRAC = 0.05
    }

    /** Background GPS feed (AnchorMonitorService). */
    object Gps {
        const val UPDATE_INTERVAL_MS = 1_000L   // 1 Hz: stationary receiver keeps delivering
        const val UPDATE_MIN_DISTANCE_M = 0f
        const val TICK_INTERVAL_MS = 1_000L     // drives the GPS-loss timer
    }

    /** Alarm audio synthesis (AnchorAlarmManager). */
    object Audio {
        const val SAMPLE_RATE = 44_100

        const val WARNING_PING_INTERVAL_MS = 8_000L  // one gentle ping every 8 s
        const val WARNING_FREQ_HZ = 880.0
        const val WARNING_PING_MS = 250
        const val WARNING_AMPLITUDE = 0.32

        const val TEST_AUTOSTOP_MS = 60_000L          // safety auto-stop for the test tone
        const val TEST_VOLUME_SCALE = 0.10f           // test plays at 10 % volume

        // Continuous siren: two oscillators a tritone apart, the fundamental wailing
        // LOW → LOW+SWEEP → LOW across one loop, summed and hard-clipped.
        const val SIREN_LOOP_SEC = 2.0
        const val SIREN_FREQ_LOW_HZ = 400.0
        const val SIREN_FREQ_SWEEP_HZ = 800.0         // peak = LOW + SWEEP = 1200 Hz
        const val SIREN_TRITONE = 1.4142              // √2, the most dissonant interval
        const val SIREN_FADE_MS = 6                   // click-free loop seam
        const val SIREN_CLIP = 0.9                    // hard-clip threshold
        const val SIREN_AMPLITUDE = 0.9
    }
}
