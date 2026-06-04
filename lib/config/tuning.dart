/// Centralized tunable constants for the Dart side of the app.
///
/// This is the ONE place to adjust GPS cadence, display thresholds, and hold
/// durations.  Call sites reference these named constants — never inline a magic
/// number for a tunable value.
///
/// Anchor-alarm *thresholds* (radius limits, GPS-loss timings, battery levels,
/// debounce) live on the native side because the background service must evaluate
/// the alarm with the Flutter engine dead — see `android/.../Tuning.kt`.  Dart and
/// Kotlin cannot share a compile-time constant, so any value that must agree across
/// the boundary is duplicated and called out in both files and in the constitution.
library;

/// GPS acquisition cadence.  Two distinct profiles:
///   • Navigation — economical and charger-aware (power is the priority).
///   • Anchoring  — full robustness; never power-throttled.
abstract final class GpsTuning {
  // Heading-source speed thresholds (metres/second).
  /// At/above this speed the GPS course is the primary heading (≈ 5.4 km/h).
  static const double gpsHeadingMinSpeed = 1.5;
  /// At/above this speed the (smoothed) track bearing / GPS course is usable.
  static const double trkHeadingMinSpeed = 0.5;

  // Navigation stream — charger-aware (see HomeScreen._locationSettings).
  static const int navDistanceFilterChargingM = 2;
  static const int navDistanceFilterBatteryM = 8;
  static const Duration navIntervalCharging = Duration(seconds: 8);
  static const Duration navIntervalBattery = Duration(seconds: 20);

  // Anchoring stream — distanceFilter 0 + short interval force stationary fixes,
  // so the anchor's GPS-loss timer never starves while the boat sits still.
  static const int anchorDistanceFilterM = 0;
  static const Duration anchorInterval = Duration(seconds: 3);

  /// While anchoring: request a one-shot fix if the stream has stalled this long.
  static const int keepAliveFixAfterStaleSec = 20;

  /// Re-check the charger state every N stale-ticks (the timer runs at 1 Hz, so
  /// this is also N seconds) to adapt the navigation power profile mid-session.
  static const int chargerRecheckTicks = 30;
}

/// Display / interaction thresholds that trade responsiveness against battery.
abstract final class DisplayTuning {
  /// Minimum gap between compass-driven redraws (~10 Hz cap).
  static const int compassMinIntervalMs = 100;

  /// Suppress a compass redraw unless the heading moved at least this much —
  /// stops ~10 Hz repaints from sub-degree jitter while standing still.
  static const double compassRedrawMinDeltaDeg = 0.5;

  /// Move at least this far before recomputing the nearest city/port.
  static const double cityRecalcThresholdM = 100.0;

  /// Deliberate-gesture duration for safety-critical actions (clear MOB / nav,
  /// and hold-to-mute on the alarm splash), in milliseconds.  See constitution §5.8.
  static const int holdToClearMs = 3000;
  static const Duration holdToClear = Duration(milliseconds: holdToClearMs);
}
