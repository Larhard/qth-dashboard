import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Owns the dashboard's sensor *plumbing* — the GPS position stream, the compass
/// subscription, and the 1 Hz tick timer — plus their start/stop/pause lifecycle.
///
/// It deliberately holds NO sensor state and does NO orchestration: the owning
/// widget supplies the event handlers ([onPosition], [onCompass], [onTick]) and a
/// [buildSettings] callback (which still reads live state like charger/anchoring),
/// so the data flow and ordering are identical to having the subscriptions inline.
/// This separates "how the sensor subscriptions are managed across the app
/// lifecycle" from the widget's layout and orchestration. No `BuildContext`.
class SensorLifecycle {
  final void Function(Position) onPosition;
  final void Function(CompassEvent) onCompass;
  final void Function() onTick;
  final AndroidSettings Function({ForegroundNotificationConfig? fg}) buildSettings;

  SensorLifecycle({
    required this.onPosition,
    required this.onCompass,
    required this.onTick,
    required this.buildSettings,
  });

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _timer;

  static const _tick = Duration(seconds: 1);

  // Foreground-service notification for background (screen-off) GPS — required by
  // Android API 26+ to keep location updates flowing while the app is backgrounded.
  static const _bgNotif = ForegroundNotificationConfig(
    notificationTitle: 'QTH Helper',
    notificationText: 'GPS tracking active',
    enableWakeLock: true,
  );

  // ── Compass ────────────────────────────────────────────────────────────────
  void startCompass() {
    _compassSub ??= FlutterCompass.events?.listen(onCompass);
  }

  void pauseCompass() => _compassSub?.pause();
  void resumeCompass() => _compassSub?.resume();

  // ── 1 Hz tick ────────────────────────────────────────────────────────────────
  void ensureTimer() => _timer ??= Timer.periodic(_tick, (_) => onTick());
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ── GPS position stream ──────────────────────────────────────────────────────
  /// Foreground stream (screen on).
  void startForegroundGps() => _restartGps(buildSettings());

  /// Background stream (screen off) — carries the foreground-service notification.
  void startBackgroundGps() => _restartGps(buildSettings(fg: _bgNotif));

  void stopGps() {
    _posSub?.cancel();
    _posSub = null;
  }

  void _restartGps(AndroidSettings settings) {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(onPosition, onError: (_) {});
  }

  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _timer?.cancel();
  }
}
