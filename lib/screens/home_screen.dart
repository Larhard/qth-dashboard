import 'dart:async';
import '../utils/track_bearing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../config/tuning.dart';
import '../controllers/sensor_lifecycle.dart';
import '../utils/heading_source.dart';
import '../utils/text_fit.dart';
import '../models/waypoint.dart';
import '../services/city_service.dart';
import '../services/declination_service.dart';
import '../services/waypoint_service.dart';
import '../utils/coordinate_utils.dart';
import '../utils/geo_utils.dart';
import '../utils/mgrs_utils.dart';
import '../utils/units.dart';
import '../utils/gpx_utils.dart';
import '../services/anchor_service.dart';
import '../services/overlay_service.dart';
import '../widgets/arrow_widget.dart';
import '../widgets/compass_painters.dart';
import '../widgets/anchor_card.dart';
import '../widgets/rel_bearing_arrow.dart';
import '../widgets/city_detail_sheet.dart';
import '../widgets/anchor_alarm_overlay.dart';
import 'debug_screen.dart';
import 'waypoints_screen.dart';

/// Which waypoint card the current hold gesture is targeting.
enum _WptHoldTarget { emergency, nav }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── Constants ───────────────────────────────────────────────────────────
  // Tunable values live in lib/config/tuning.dart; these are local aliases so
  // call sites stay terse.  Adjust the value in tuning.dart, not here.
  static const _compassIntervalMs = DisplayTuning.compassMinIntervalMs;
  static const _cityRecalcThresholdM = DisplayTuning.cityRecalcThresholdM;

  // ── GPS / compass / tick lifecycle ────────────────────────────────────────
  // Subscription + timer plumbing lives in the controller; this widget keeps the
  // event handlers and orchestration. Built in initState.
  late final SensorLifecycle _sensors;

  // ── GPS state ─────────────────────────────────────────────────────────────
  Position? _position;
  double? _lastValidGpsHeading;
  NearestCity? _nearestCity;
  Position? _lastCityCalcPos;
  String? _error;

  // Cached display strings — updated in GPS listener, read in build.
  // Avoids re-running formatLat/formatLon/maidenhead on every widget rebuild.
  String _cachedLatStr = '';
  String _cachedLonStr = '';
  String _cachedLocStr = '';
  double _cachedAlt = 0;
  double _cachedAccuracy = 0;

  // ── Compass state ─────────────────────────────────────────────────────────
  double _compassHeading = 0;
  bool _compassReceived = false;
  int _lastCompassMs = 0;
  // ValueNotifier drives the secondary arrow directly, bypassing setState batching.
  final _compassNotifier = ValueNotifier<double>(0.0);

  // ── Track azimuth ─────────────────────────────────────────────────────────
  // ── Track azimuth ─────────────────────────────────────────────────────────
  final _track = TrackBearingEstimator();

  // ── GPS staleness ─────────────────────────────────────────────────────────
  DateTime _lastGpsFix = DateTime.now();
  int _gpsStaleSeconds = 0; // 0 = fresh; > 0 = seconds since last fix

  // Charger state, used ONLY to pick the navigation GPS profile (power priority
  // off-charger).  Defaults to true (responsive) until the first native query.
  // The anchor GPS is unaffected — it always runs at full robustness.
  bool _charging = true;
  int _powerTick = 0; // counts stale-ticks for the periodic charging re-check

  // True while the screen is on (resumed lifecycle). Used to skip wasted
  // display work and city lookups when the GPS fires in LIVE mode background.
  bool _screenOn = true;
  // Last compass heading that actually triggered a setState — used to suppress
  // rebuilds when the heading hasn't changed enough to matter visually.
  double _lastRenderedCompassHeading = -1.0;

  // ── Pocket-lock feature ───────────────────────────────────────────────────
  // When enabled: proximity sensor detects pocket → screen locks after 5 s.
  // Uses DevicePolicyManager.lockNow() if Device Admin is active; falls back to
  // screenBrightness=0 otherwise.
  // Default off — enabled by the user via long-press on the SCR toggle.
  static const _screenChannel = MethodChannel('qth_helper/screen');
  bool _pocketLockEnabled = GetStorage().read<bool>('pocket_lock') ?? false;

  // ── Heading arrow / source modes ─────────────────────────────────────────
  HeadingArrowMode  _headingArrowMode  = loadHeadingArrowMode();
  HeadingSourceMode _headingSourceMode = loadHeadingSourceMode();

  // ── Speed unit ────────────────────────────────────────────────────────────
  SpeedUnit _speedUnit = loadSpeedUnit();

  // ── Time display ──────────────────────────────────────────────────────────
  bool _timeUtc = loadTimeUtc();
  // Offset from system clock to GPS time, updated on every GPS fix.
  // DateTime.now() + _gpsClockOffset gives a GPS-calibrated current time
  // that ticks in real time between fixes.
  Duration _gpsClockOffset = Duration.zero;

  // ── Coordinate / locator format ────────────────────────────────────────────
  CoordFormat _coordFormat = loadCoordFormat();
  LocatorType _locatorType = loadLocatorType();

  // ── MOB hold-to-clear ─────────────────────────────────────────────────────
  // Driven by a real Stopwatch — immune to ticker mute/unmute jumps.
  static const _holdToClearMs = DisplayTuning.holdToClearMs;
  static const _rewindPerFrame = 0.05;
  late final Ticker _holdTicker;
  final Stopwatch _holdWatch = Stopwatch();
  bool _holding = false;
  double _clearProgress = 0.0;

  // ── GPS-on-lock mode ───────────────────────────────────────────────────────
  bool _gpsOnLock = false;

  // ── Anchor alarm ──────────────────────────────────────────────────────────
  // AnimationController drives the full-screen strobe when alarm level == alarm.
  // Runs only while alarm is active — zero overhead otherwise.
  late final AnimationController _strobeCtrl;
  // Drives the 3-second hold-to-mute progress on the alarm overlay.
  late final AnimationController _muteCtrl;

  // ── Anchor restore after kill ─────────────────────────────────────────────
  // Called post-frame when loadFromStorage() found a persisted anchor.
  // Restarts GPS lock, background service, and GPS stream — all idempotent.
  Future<void> _restoreAnchor() async {
    if (!mounted || !AnchorService.instance.isActive) return;
    final svc = AnchorService.instance;
    if (!_gpsOnLock) {
      setState(() => _gpsOnLock = true);
      GetStorage().write('gps_on_lock', true);
      _enableLiveModeWithPermission();
    }
    _anchorAlarmChannel.invokeMethod('startAnchorService', {
      'lat': svc.anchorLat, 'lon': svc.anchorLon,
      'radius': svc.radiusM, 'warnFrac': svc.warningFraction,
    }).catchError((_) {});
    if (_gpsOnLock) _sensors.startBackgroundGps(); else _sensors.startForegroundGps();
    // Sync the live snapshot so an in-progress alarm shows its overlay at once.
    await svc.refresh();
    if (!mounted) return;
    setState(() {});
    _showSettingSnack(
        '⚓ Anchor alarm restored (radius ${svc.radiusM.round()} m). Background service active.');
  }

  // ── Day / Night mode ──────────────────────────────────────────────────────
  // Day  : full-contrast palette — readable in direct sunlight.
  // Night: red-only palette — preserves rhodopsin (night-vision accommodation)
  //        by emitting only long-wavelength light.  No greens, blues, or ambers.
  bool _dayMode = GetStorage().read<bool>('day_mode') ?? true;
  /// Semantic colour resolver for the current mode (see lib/theme/palette.dart).
  Palette get _pal => Palette.of(_dayMode);

  // ── Night palette target: 4 levels of dim red, no other colours ─────────────
  //   Primary   0xFFCC3333  — main data (heading degrees, coordinates)
  //   Secondary 0xFF882222  — supporting (speed, city name, bearing, MOB name)
  //   Tertiary  0xFF661111  — labels (source, TRK, alt/acc, hints)
  //   Ghost     0xFF441111  — barely-there (dividers, secondary arrow, borders)

  // Text hierarchy
  Color get _cText1 => _pal.textPrimary;
  Color get _cText2 => _pal.textSecondary;
  Color get _cText3 => _pal.pick(kDFg2, kN3);
  // Element-specific
  Color get _cSpeed   => _pal.textTertiary;
  Color get _cAltAcc  => _pal.textTertiary;
  Color get _cStale   => _pal.stale;
  // IARU locator — green (same family as GPS heading and UTC clock)
  Color get _cLocator      => _pal.pick(kDGps, kN2);
  Color get _cLocatorLabel => _pal.gpsLabel;
  // MGRS — amber-orange family
  Color get _cMgrs      => _pal.amber;
  Color get _cMgrsLabel => _pal.amberLabel;
  // Clock: UTC shares GPS green; local time shares MGRS amber
  Color get _cTime => _dayMode
      ? (_timeUtc ? kDGps : kDAmb)
      : kN2;
  Color get _cTimeLabel => _dayMode
      ? (_timeUtc ? kDGpsL : kDAmbs)
      : kN3;
  // GPS-lock toggle indicator
  Color get _cSaveLock => _pal.pick(kDAmb, kN3);
  Color get _cLiveLock => _pal.port;
  // Active waypoint / MOB card — red emergency family
  Color get _cWptName   => _pal.pick(kDEmg, kN1);
  Color get _cWptArrow  => _pal.pick(kDEmg, kN1);
  Color get _cWptData   => _pal.pick(kDEmg, kN2);
  Color get _cWptCoords => _pal.pick(kDEmgS, kN2);
  // MOB button
  Color get _cMobBg   => _pal.pick(kDEmgBg, kN3);
  Color get _cMobText => _pal.textPrimary;

  void _toggleDayMode() {
    HapticFeedback.mediumImpact();
    setState(() => _dayMode = !_dayMode);
    GetStorage().write('day_mode', _dayMode);
    _showSettingSnack(_dayMode
        ? 'Day mode — full brightness'
        : 'Night mode — red only, preserves night vision');
  }

  // ── Derived ───────────────────────────────────────────────────────────────
  // ── Primary heading source ────────────────────────────────────────────────
  // magOnly mode: compass always primary.
  // auto mode:    GPS when fast (≥1.5 m/s), TRK when medium (≥0.5 m/s), MAG otherwise.
  // Secondary is always the complementary source (MAG in auto, TRK/GPS in magOnly).

  bool _gpsSpeedValid() {
    final p = _position;
    return p != null && gpsHeadingUsable(p.speed, p.heading);
  }

  // Heading-source selection is pure logic (see utils/heading_source.dart, tested
  // in heading_source_test.dart). This widget only supplies the live inputs.
  HeadingChoice get _hc => chooseHeadingSource(
        mode: _headingSourceMode,
        gpsUsable: _gpsSpeedValid(),
        trkAvailable: _track.bearing != null,
      );

  // True when GPS/TRK data is actually available — drives live degrees vs "---".
  bool get _intendedSourceHasData => _hc.hasData;

  // Compass listener: while waiting for TRK/GPS the computed source is still MAG,
  // so this stays false and the listener keeps calling setState → arrow rotates.
  bool get _usingGps => _hc.usingGps;

  double get _heading {
    // In auto mode before GPS/TRK data arrives: freeze the ring/primary arrow at
    // North rather than silently following MAG. The secondary MAG arrow/dash still
    // updates via ValueListenableBuilder.
    if (!_hc.hasData && _headingSourceMode == HeadingSourceMode.auto) {
      return 0.0;
    }
    return switch (_hc.computed) {
      HeadingSource.gps => _position?.heading ?? _compassHeading,
      HeadingSource.trk => _track.bearing ?? _compassHeading,
      HeadingSource.mag => _compassHeading,
    };
  }

  // Colour and label use the DISPLAY source.
  // GPS=green (kDGps), TRK=yellow (kDTrk), MAG=white (kDFg0); night shifts to reds.
  Color get _headingColor => switch (_hc.display) {
    HeadingSource.gps => _pal.gps,
    HeadingSource.trk => _pal.trk,
    HeadingSource.mag => _pal.pick(kDFg0, kN2),
  };

  String get _sourceLabel => _hc.display.label;

  Color get _secondaryHeadingColor {
    if (_headingSourceMode == HeadingSourceMode.auto) {
      return _pal.pick(kDFg0, kN3); // MAG secondary — dimmer than primary
    }
    // magOnly: secondary is TRK or GPS
    if (_track.bearing != null) {
      return _pal.pick(kDTrk, kN3); // TRK secondary
    }
    return _pal.pick(kDGps, kN3);   // GPS secondary
  }

  // City accent colours — each tier has a distinct hue; night collapses to red.
  Color get _cityColor => !_dayMode ? kN2 : switch (CityService.instance.mode) {
    CityMode.large    => kDCityL, // orange   — global overview
    CityMode.precise  => kDCityP, // amber    — regional
    CityMode.detailed => kDCityD, // lime     — local detail
    CityMode.port     => kDPort,  // cyan     — port/nautical
  };
  Color get _citySubColor => !_dayMode ? kN3 : switch (CityService.instance.mode) {
    CityMode.large    => kDAmbs,  // deep orange
    CityMode.precise  => kDAmb,   // amber
    CityMode.detailed => kDCityDS,// lime-dark
    CityMode.port     => kDPortL, // cyan sub-text
  };

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _holdTicker = createTicker(_onHoldTick);
    _syncPocketLock();
    _gpsOnLock = GetStorage().read<bool>('gps_on_lock') ?? false;
    _strobeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _muteCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          AnchorService.instance.mute();
          _muteCtrl.reset();
          setState(() {});
        }
      });
    AnchorService.instance.onStateChanged = _onAnchorStateChanged;
    _sensors = SensorLifecycle(
      onPosition: _onPositionUpdate,
      onCompass: _onCompassEvent,
      onTick: _onStaleTick,
      buildSettings: _locationSettings,
    );
    // Restore anchor if it was active before the app was killed.
    if (AnchorService.instance.loadFromStorage()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAnchor());
    }
    _sensors.ensureTimer();
    _init();
    // Check for a GPX file that was opened to launch the app (cold start).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingGpx());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holdTicker.dispose();
    _strobeCtrl.dispose();
    _muteCtrl.dispose();
    AnchorService.instance.onStateChanged = null;
    _compassNotifier.dispose();
    _sensors.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _screenOn = false;
      _cancelClear();

      // Show the floating overlay while the user is in another app.
      if (OverlayController.instance.enabled) OverlayController.instance.show();

      // Keep sensors alive when there's a background consumer (GPS-on-lock,
      // an active anchor, or the floating overlay).  Otherwise release them.
      final keepAlive = _gpsOnLock ||
          AnchorService.instance.isActive ||
          OverlayController.instance.enabled;

      if (keepAlive) {
        // Compass + 1 Hz tick stay running so the overlay/anchor keep updating.
        _sensors.ensureTimer();
        _sensors.startBackgroundGps(); // foreground-service backed GPS
      } else {
        // Battery-saving default: release everything.
        _sensors.pauseCompass();
        _sensors.stopTimer();
        _sensors.stopGps();
      }
    } else if (state == AppLifecycleState.resumed) {
      _screenOn = true;
      // Hide the overlay while the dashboard itself is in front (idempotent —
      // call whenever the feature is enabled, regardless of locally-tracked state).
      if (OverlayController.instance.enabled) OverlayController.instance.hide();
      _sensors.resumeCompass();
      _checkPocketLockOnResume();
      _sensors.ensureTimer();
      _sensors.startForegroundGps();
      _refreshChargingProfile(); // adapt nav GPS to charger state on each resume
      _requestImmediateGpsFix();
      _checkPendingGpx(); // handle files opened from other apps
      // Immediately sync the anchor snapshot so the alarm overlay / silence
      // button appears at once when the service raised the alarm in the
      // background (e.g. the service launched us, or the user tapped the
      // notification).  Without this the overlay would wait for the next tick.
      if (AnchorService.instance.isActive) AnchorService.instance.refresh();
    }
  }

  void _requestImmediateGpsFix() {
    Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).then((pos) {
      if (!mounted) return;
      _lastGpsFix = DateTime.now();
      _cachedLatStr = formatLatF(pos.latitude, _coordFormat);
      _cachedLonStr = formatLonF(pos.longitude, _coordFormat);
      _cachedLocStr = _locStr(pos.latitude, pos.longitude);
      _cachedAlt = pos.altitude;
      _cachedAccuracy = pos.accuracy;
      _gpsClockOffset = pos.timestamp.difference(DateTime.now());
      AnchorService.instance.forwardPosition(pos.latitude, pos.longitude, pos.accuracy);
      setState(() {
        _position = pos;
        _gpsStaleSeconds = 0;
      });
    }).catchError((_) {});
  }

  // ── GPS staleness timer (driven by SensorLifecycle's 1 Hz tick) ────────────
  void _onStaleTick() {
    if (!mounted) return;
    final sec = DateTime.now().difference(_lastGpsFix).inSeconds;
    // Conditional rebuild: only when the stale counter actually changes.
    if (sec != _gpsStaleSeconds) setState(() => _gpsStaleSeconds = sec);

    // Keep the floating overlay fresh (cheap; only when shown).
    _pushOverlay();

    // Re-check the charger state every ~30 s so the nav power profile adapts even
    // during a long screen-on session (e.g. the user plugs in mid-drive).
    if (++_powerTick % GpsTuning.chargerRecheckTicks == 0) _refreshChargingProfile();

    // Anchor-only work (zero overhead when not anchoring).
    if (AnchorService.instance.isActive) {
      // Poll the native authority for the live alarm snapshot (drives the card
      // + strobe overlay). _onAnchorStateChanged fires via the onStateChanged hook.
      AnchorService.instance.refresh();

      // GPS keep-alive — request a fresh single-fix if updates have stalled.
      // (Battery and GPS-loss are monitored natively in AnchorMonitorService so
      // they work even when the app is closed.)
      if (sec > 0 && sec % GpsTuning.keepAliveFixAfterStaleSec == 0) {
        _requestImmediateGpsFix();
      }
    }
  }

  // ── Stream init ───────────────────────────────────────────────────────────
  Future<void> _init() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() =>
            _error = 'Location permission required.\nEnable it in Settings.');
      }
      return;
    }

    _sensors.startForegroundGps();
    _refreshChargingProfile(); // pick the right nav power profile at startup
    _sensors.startCompass();
  }

  // Compass event handler (declination correction + ~10 Hz throttle + redraw gate).
  void _onCompassEvent(CompassEvent e) {
    final h = e.heading;
    if (h == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCompassMs < _compassIntervalMs) return;
    _lastCompassMs = now;
    final corrected =
        (h + DeclinationService.instance.declination + 360) % 360;
    _compassHeading = corrected;
    _compassNotifier.value = corrected;
    if (!_compassReceived) _compassReceived = true;
    // Feed the floating overlay at the compass rate (~10 Hz) when shown.
    if (OverlayController.instance.isShown) _pushOverlay();
    // Only rebuild when the heading has changed enough to be visible.
    // Suppresses ~10 Hz redraws when stationary (compass jitter ±0.5°).
    if (!_usingGps && mounted) {
      final delta = (corrected - _lastRenderedCompassHeading).abs();
      final wrapped = delta > 180 ? 360 - delta : delta; // handle 359°→1° wrap
      if (wrapped >= DisplayTuning.compassRedrawMinDeltaDeg) {
        _lastRenderedCompassHeading = corrected;
        setState(() {});
      }
    }
  }

  // The position stream is cancelled when the screen turns off (see lifecycle
  // handler) and recreated here on resume, so the GNSS receiver isn't draining
  // power during long screen-off stretches on a hike.
  // Shared handler — called from both the normal (foreground) and background
  // (foreground-service) GPS streams.
  void _onPositionUpdate(Position pos) {
    _lastGpsFix = DateTime.now();
    if (_gpsStaleSeconds > 0) _gpsStaleSeconds = 0;
    // Forward the (reliable, fused) foreground fix to the native anchor authority
    // so its GPS-loss timer is reset by the most reliable source available.
    AnchorService.instance.forwardPosition(pos.latitude, pos.longitude, pos.accuracy);

    // GPS course is usable above the TRK threshold; cache it so the secondary
    // arrow appears even at walking pace.
    if (pos.speed >= GpsTuning.trkHeadingMinSpeed &&
        !pos.heading.isNaN && pos.heading >= 0) {
      _lastValidGpsHeading = pos.heading;
    }

    // Track bearing and declination run in both foreground and background —
    // they are the primary benefit of LIVE mode (fresh TRK on unlock).
    _updateTrackBearing(pos);
    DeclinationService.instance.update(pos.latitude, pos.longitude, pos.altitude);

    if (!_screenOn || !mounted) {
      // Screen is off (LIVE mode background stream): skip all display work.
      // String formatting, city lookups, and setState are wasted CPU when
      // nothing is visible. Cache the raw position for display on resume.
      // NOTE: !mounted also guards against rare widget-disposal races.
      _position = pos;
      return;
    }

    // Foreground: update display caches and rebuild.
    _cachedLatStr = formatLatF(pos.latitude, _coordFormat);
    _cachedLonStr = formatLonF(pos.longitude, _coordFormat);
    _cachedLocStr = _locStr(pos.latitude, pos.longitude);
    _cachedAlt = pos.altitude;
    _cachedAccuracy = pos.accuracy;
    _gpsClockOffset = pos.timestamp.difference(DateTime.now());

    final needsCity = _lastCityCalcPos == null ||
        Geolocator.distanceBetween(
              _lastCityCalcPos!.latitude, _lastCityCalcPos!.longitude,
              pos.latitude, pos.longitude,
            ) >= _cityRecalcThresholdM;

    if (needsCity) {
      _lastCityCalcPos = pos;
      final city = CityService.instance.nearest(pos.latitude, pos.longitude);
      setState(() { _position = pos; _nearestCity = city; });
    } else {
      setState(() => _position = pos);
    }
  }

  // Builds the Geolocator settings for the current mode.
  //   • Anchoring → always full robustness: distanceFilter=0 + 3 s interval so a
  //     stationary boat keeps delivering fixes (never charging-dependent).
  //   • Navigating → power-aware: economical off-charger, responsive when charging.
  //     (It is fine for navigation to look "stale"/lost when stationary — the user
  //      is aware the vehicle isn't moving; power is the priority here.)
  AndroidSettings _locationSettings({ForegroundNotificationConfig? fg}) {
    final p = GpsTuning.profile(
      anchoring: AnchorService.instance.isActive,
      charging: _charging,
    );
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: p.distanceFilterM,
      intervalDuration: p.interval,
      foregroundNotificationConfig: fg,
    );
  }

  /// Query the charger state and, if it changed while navigating, restart the
  /// foreground stream so the new power profile takes effect.  Cheap; the anchor
  /// stream is intentionally unaffected.
  Future<void> _refreshChargingProfile() async {
    bool charging;
    try {
      charging = await _anchorAlarmChannel.invokeMethod<bool>('isCharging') ?? _charging;
    } catch (_) { return; }
    if (!mounted || charging == _charging) return;
    _charging = charging;
    // Only the navigating foreground stream depends on charger state.
    if (_screenOn && !AnchorService.instance.isActive) _sensors.startForegroundGps();
  }

  // ── Track azimuth ─────────────────────────────────────────────────────────
  void _updateTrackBearing(Position pos) {
    _track.update(pos.latitude, pos.longitude);
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  void _addWaypoint() {
    final pos = _position;
    if (pos == null) return;
    HapticFeedback.heavyImpact();
    WaypointService.instance.addEmergency(pos.latitude, pos.longitude);
    setState(() {});
  }

  void _clearEmergency() {
    WaypointService.instance.clearEmergency();
    if (mounted) setState(() {});
  }

  void _toggleHeadingArrowMode() {
    final next = _headingArrowMode == HeadingArrowMode.arrow
        ? HeadingArrowMode.windRose
        : HeadingArrowMode.arrow;
    setState(() => _headingArrowMode = next);
    saveHeadingArrowMode(next);
    HapticFeedback.lightImpact();
    _showSnack(next == HeadingArrowMode.windRose
        ? 'Wind rose — rotating compass, dots show POI directions'
        : 'Arrow mode — bearing arrows with direction dots');
  }

  void _toggleHeadingSourceMode() {
    final next = _headingSourceMode == HeadingSourceMode.magOnly
        ? HeadingSourceMode.auto
        : HeadingSourceMode.magOnly;
    setState(() => _headingSourceMode = next);
    saveHeadingSourceMode(next);
    HapticFeedback.lightImpact();
    _showSnack(next == HeadingSourceMode.auto
        ? 'AUTO — GPS when fast · TRK when moving · MAG fallback'
        : 'MAG primary — TRK / GPS secondary');
  }

  // Which waypoint card the hold gesture is currently targeting.
  _WptHoldTarget? _holdTarget;

  void _startClear([_WptHoldTarget target = _WptHoldTarget.emergency]) {
    final hasItem = target == _WptHoldTarget.emergency
        ? WaypointService.instance.emergency != null
        : WaypointService.instance.active != null;
    if (!hasItem) return;
    _holdTarget = target;
    _holding = true;
    _holdWatch..reset()..start();
    if (!_holdTicker.isActive) _holdTicker.start();
  }

  void _cancelClear() {
    _holding = false;
    _holdWatch..stop()..reset();
    if (_clearProgress > 0 && !_holdTicker.isActive) _holdTicker.start();
  }

  void _onHoldTick(Duration _) {
    if (_holding) {
      final elapsed = _holdWatch.elapsedMilliseconds;
      final p = (elapsed / _holdToClearMs).clamp(0.0, 1.0);
      if (p != _clearProgress) setState(() => _clearProgress = p);
      if (elapsed >= _holdToClearMs) _finishClear();
    } else {
      final next = (_clearProgress - _rewindPerFrame).clamp(0.0, 1.0);
      setState(() => _clearProgress = next);
      if (next <= 0.0) _holdTicker.stop();
    }
  }

  void _finishClear() {
    _holding = false;
    _holdWatch..stop()..reset();
    _holdTicker.stop();
    setState(() => _clearProgress = 0.0);
    HapticFeedback.heavyImpact();
    if (_holdTarget == _WptHoldTarget.nav) {
      WaypointService.instance.deactivate();
      if (mounted) setState(() {});
    } else {
      _clearEmergency();
    }
    _holdTarget = null;
  }

  // ── GPS-on-lock toggle ────────────────────────────────────────────────────
  void _toggleGpsLock() {
    HapticFeedback.lightImpact();
    if (!_gpsOnLock) {
      _enableLiveModeWithPermission();
    } else {
      setState(() => _gpsOnLock = false);
      GetStorage().write('gps_on_lock', false);
      _showSettingSnack('GPS on screen lock: OFF\nGPS pauses when screen is off — saves battery');
    }
  }

  Future<void> _enableLiveModeWithPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always) {
      perm = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (perm == LocationPermission.always) {
      setState(() => _gpsOnLock = true);
      GetStorage().write('gps_on_lock', true);
      _showSettingSnack('GPS on screen lock: ON\nGPS keeps tracking when screen is off');
    } else {
      // Permission denied: stay off and tell the user what to do.
      _showSettingSnack(
        'Background location required.\nGrant "Allow all the time" in app Settings to enable GPS on lock screen.',
      );
    }
  }

  void _showSettingSnack(String message) {
    final bg = _pal.snackBg;
    final fg = _pal.textSecondary;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: fg, fontSize: 13, height: 1.5)),
      backgroundColor: bg,
      duration: const Duration(milliseconds: 2500),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  String _locStr(double lat, double lon) =>
      _locatorType == LocatorType.maidenhead ? maidenhead(lat, lon) : mgrs(lat, lon);

  void _toggleCoordFormat() {
    final next = CoordFormat.values[(_coordFormat.index + 1) % CoordFormat.values.length];
    final pos = _position;
    setState(() {
      _coordFormat = next;
      if (pos != null) {
        _cachedLatStr = formatLatF(pos.latitude, next);
        _cachedLonStr = formatLonF(pos.longitude, next);
      }
    });
    saveCoordFormat(next);
    HapticFeedback.lightImpact();
  }

  void _toggleLocatorType() {
    final next = _locatorType == LocatorType.maidenhead
        ? LocatorType.mgrs
        : LocatorType.maidenhead;
    final pos = _position;
    setState(() {
      _locatorType = next;
      if (pos != null) _cachedLocStr = _locStr(pos.latitude, pos.longitude);
    });
    saveLocatorType(next);
    HapticFeedback.lightImpact();
  }

  void _toggleTimeZone() {
    setState(() => _timeUtc = !_timeUtc);
    saveTimeUtc(_timeUtc);
    HapticFeedback.lightImpact();
  }

  void _syncPocketLock() {
    _screenChannel
        .invokeMethod('setPocketLock', {'enabled': _pocketLockEnabled})
        .catchError((_) {});
  }

  void _togglePocketLock() {
    final next = !_pocketLockEnabled;
    setState(() => _pocketLockEnabled = next);
    GetStorage().write('pocket_lock', next);
    _syncPocketLock();
    HapticFeedback.lightImpact();
    _showSnack(next
        ? 'Pocket lock ON — screen dims after 5 s in pocket'
        : 'Pocket lock OFF');
  }

  Future<void> _checkPocketLockOnResume() async {
    // Sync persisted state back to Android in case it was reset by a crash.
    _syncPocketLock();
  }

  void _showSnack(String msg, {Duration duration = const Duration(milliseconds: 2000)}) {
    final bg = _pal.snackBg;
    final fg = _pal.textSecondary;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: fg, fontSize: 13), maxLines: 2),
      backgroundColor: bg,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ));
  }

  void _cycleSpeedUnit() {
    final next =
        SpeedUnit.values[(_speedUnit.index + 1) % SpeedUnit.values.length];
    setState(() => _speedUnit = next);
    saveSpeedUnit(next);
    HapticFeedback.lightImpact();
    _showSnack(speedUnitLabel(next), duration: const Duration(milliseconds: 900));
  }

  void _toggleCityMode() {
    CityService.instance.toggleMode();
    _lastCityCalcPos = null;
    final pos = _position;
    if (pos != null) {
      final city = CityService.instance.nearest(pos.latitude, pos.longitude);
      setState(() => _nearestCity = city);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    _showSnack(text, duration: const Duration(milliseconds: 1200));
  }

  // ── Pending GPX from ACTION_VIEW intent ──────────────────────────────────
  // Called on cold start (initState) and on resume so files opened from
  // file managers or email attachments are imported automatically.
  static const _gpxChannel = MethodChannel('qth_helper/file_picker');

  Future<void> _checkPendingGpx() async {
    if (!mounted) return;
    final String? content;
    try {
      content = await _gpxChannel.invokeMethod<String>('getPendingGpx');
    } catch (_) { return; }
    if (content == null || !mounted) return;

    List<GpxWaypoint> parsed;
    try {
      parsed = GpxUtils.parse(content);
    } catch (_) {
      _showSnack('Received file is not valid GPX.');
      return;
    }
    if (parsed.isEmpty) {
      _showSnack('GPX file contained no waypoints (track points are not imported).');
      return;
    }
    final r = WaypointService.instance.importWaypoints(parsed);
    if (mounted) setState(() {});
    // Show undo action so the user can reverse an accidental open-with import.
    if (r.added > 0 && mounted) {
      final bg  = _pal.snackBg;
      final fg  = _pal.textSecondary;
      final act = _pal.pick(kDFg0, kN0);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(_gpxImportSummary(r, parsed.length),
              style: TextStyle(color: fg, fontSize: 13), maxLines: 3),
          backgroundColor: bg,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: act,
            onPressed: () {
              if (!mounted) return;
              WaypointService.instance.undoLastImport();
              setState(() {});
            },
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ));
    } else {
      _showSnack(_gpxImportSummary(r, parsed.length));
    }
  }

  static const _anchorAlarmChannel = MethodChannel('qth_helper/anchor_alarm');

  // ── Floating overlay data push ────────────────────────────────────────────
  // Builds one frame for the native compass overlay (compass + all POI dots +
  // one coloured text line per active item).  No-op unless the overlay is shown.
  void _pushOverlay() {
    if (!OverlayController.instance.isShown) return;
    final windRose  = _headingArrowMode == HeadingArrowMode.windRose;
    final secondary = _headingSourceMode == HeadingSourceMode.auto
        ? _compassHeading
        : (_track.bearing ?? _lastValidGpsHeading);

    // POI dots — exactly the main bearing ring (city / nav waypoint / MOB).
    final pos = _position;
    final markers = pos != null ? _bearingMarkers(pos) : const [];
    final mB = <double>[]; final mC = <int>[]; final mS = <double>[];
    for (final m in markers) {
      mB.add(m.bearingDeg.toDouble());
      mC.add(m.color.toARGB32());
      mS.add(m.sizeScale);
    }

    // One coloured text line per active item, each in its dashboard palette colour.
    // The label (name) is croppable; the value (heading + distance) is drawn
    // flush-right by the native view so it is never pushed off when names are long.
    final lineLabels = <String>[];
    final lineValues = <String>[];
    final lineColors = <int>[];
    void addLine(String label, String value, Color c) {
      lineLabels.add(label);
      lineValues.add(value);
      lineColors.add(c.toARGB32());
    }
    String bd(double b, double distKm) =>
        '${b.round()}°  ${formatDistanceUnit(distKm, _speedUnit)}';

    if (pos != null) {
      final nc = _nearestCity;
      if (nc != null) addLine(nc.city.name, bd(nc.bearingDeg, nc.distKm), _cityColor);

      final nav = WaypointService.instance.active;
      if (nav != null) {
        final b = bearing(pos.latitude, pos.longitude, nav.lat, nav.lon);
        final dk = haversineKm(pos.latitude, pos.longitude, nav.lat, nav.lon);
        addLine(nav.name, bd(b, dk), _pal.nav);
      }
      final mob = WaypointService.instance.emergency;
      if (mob != null) {
        final b = bearing(pos.latitude, pos.longitude, mob.lat, mob.lon);
        final dk = haversineKm(pos.latitude, pos.longitude, mob.lat, mob.lon);
        addLine('MOB', bd(b, dk), _pal.emergency);
      }
    }

    if (AnchorService.instance.isActive) {
      final a = AnchorService.instance;
      final status = switch (a.level) {
        AnchorAlarmLevel.alarm   => '⚓ ALARM',
        AnchorAlarmLevel.warning => '⚓ WARN',
        AnchorAlarmLevel.idle    => '⚓ OK',
      };
      final detail = a.gpsLost
          ? 'GPS lost ${a.gpsLossSeconds}s'
          : '${(a.distanceM ?? 0).round()}/${a.radiusM.round()} m';
      addLine(status, detail, _anchorLevelColor(a.level));
    }

    OverlayController.instance.update(
      heading: _heading,
      headingValid: _intendedSourceHasData,
      windRose: windRose,
      secondaryBearing: secondary,
      primaryColor: _headingColor,          // GPS/TRK/MAG colour, as on the dashboard
      secondaryColor: _secondaryHeadingColor,
      northColor: _pal.emergency,
      ringColor: _pal.pick(kDFg0, kN2),
      bgColor: (_pal.tileBg).withValues(alpha: 0.92),
      textColor: _pal.textPrimary,
      lineLabels: lineLabels,
      lineValues: lineValues,
      lineColors: lineColors,
      markerBearings: mB,
      markerColors: mC,
      markerScales: mS,
    );
  }

  void _onAnchorStateChanged() {
    if (!mounted) return;
    final svc = AnchorService.instance;
    // The full-screen strobe shows for an un-muted alarm.
    final showStrobe = svc.level == AnchorAlarmLevel.alarm && !svc.isMuted;
    if (showStrobe) {
      if (!_strobeCtrl.isAnimating) _strobeCtrl.repeat(reverse: true);
    } else {
      if (_strobeCtrl.isAnimating) _strobeCtrl.stop();
      if (_muteCtrl.value != 0) _muteCtrl.reset(); // cancel any partial hold
    }
    setState(() {});
  }

  void _dropAnchor(double lat, double lon, double radiusM, double warnFrac) {
    final prevGpsOnLock = _gpsOnLock;
    if (!_gpsOnLock) {
      _gpsOnLock = true;
      GetStorage().write('gps_on_lock', true);
      _enableLiveModeWithPermission();
    }
    AnchorService.instance.dropAnchor(
      lat: lat, lon: lon, radiusM: radiusM, warningFraction: warnFrac,
      prevGpsOnLock: prevGpsOnLock,
    );
    // Start background service — survives app kill.
    _anchorAlarmChannel.invokeMethod('startAnchorService', {
      'lat': lat, 'lon': lon, 'radius': radiusM, 'warnFrac': warnFrac,
    }).catchError((_) {});
    // Restart GPS stream with distanceFilter = 0 + intervalDuration = 3 s.
    if (_gpsOnLock) _sensors.startBackgroundGps(); else _sensors.startForegroundGps();
    setState(() {});
    _showSettingSnack(
      'Anchor dropped · radius ${radiusM.round()} m · '
      'warning at ${(radiusM * warnFrac).round()} m.\n'
      'GPS-on-lock ${prevGpsOnLock ? 'was already' : 'has been'} enabled.',
    );
  }

  void _liftAnchor() {
    final prev = AnchorService.instance.prevGpsOnLock;
    AnchorService.instance.liftAnchor();
    // Stop background service.
    _anchorAlarmChannel.invokeMethod('stopAnchorService').catchError((_) {});
    if (!prev && _gpsOnLock) {
      setState(() => _gpsOnLock = false);
      GetStorage().write('gps_on_lock', false);
    }
    // Restore normal (foreground) stream settings — see GpsTuning.profile.
    _sensors.startForegroundGps();
    setState(() {});
    _showSettingSnack(
      'Anchor lifted. GPS-on-lock ${prev ? 'stays on' : 'turned off'}.',
    );
  }

  // ── Anchor card colours ───────────────────────────────────────────────────
  // Status colour lives on AnchorCard (also used by the floating-overlay line).
  Color _anchorLevelColor(AnchorAlarmLevel lvl) => AnchorCard.levelColor(_pal, lvl);

  static String _gpxImportSummary(
      ({int added, int skipped, int renamed}) r, int total) {
    final parts = <String>[];
    if (r.added   > 0) parts.add('${r.added} added');
    if (r.renamed > 0) parts.add('${r.renamed} renamed');
    if (r.skipped > 0) parts.add('${r.skipped} already existed');
    if (parts.isEmpty) return 'GPX: all waypoints already existed.';
    return 'GPX import: ${parts.join(', ')}.';
  }

  Future<void> _openWaypoints() async {
    _cancelClear(); // reset any in-progress hold
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WaypointsScreen(
          currentPosition: _position,
          speedUnit: _speedUnit,
          coordFormat: _coordFormat,
          locatorType: _locatorType,
          timeUtc: _timeUtc,
          dayMode: _dayMode,
          onAnchorDrop: (lat, lon, r, wf) => _dropAnchor(lat, lon, r, wf),
          onAnchorLift: _liftAnchor,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_error != null) return _buildError(_error!);
    if (_position == null) return _buildWaiting();
    return _buildMain();
  }

  Widget _buildWaiting() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Show compass heading while GPS is still acquiring.
            if (_compassReceived) ...[
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(alignment: Alignment.center, children: [
                  ArrowWidget(bearingDeg: _compassHeading,
                      color: _pal.pick(kDFg0, kN2), size: 80),
                ]),
              ),
              const SizedBox(height: 6),
              Text('${_compassHeading.round()}°',
                  style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: _pal.pick(kDFg0, kN2),
                      height: 1.0)),
              Text('MAG',
                  style: TextStyle(
                      color: _pal.textDim,
                      fontSize: 12, letterSpacing: 2.5)),
              const SizedBox(height: 32),
            ],
            CircularProgressIndicator(color: _pal.textFaint),
            const SizedBox(height: 20),
            Text('Acquiring GPS…',
                style: TextStyle(color: _pal.textDim, fontSize: 18)),
          ]),
        ),
      );

  Widget _buildError(String msg) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: _pal.textTertiary, fontSize: 18)),
          ),
        ),
      );

  Widget _buildMain() {
    final pos = _position!;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            isLandscape ? _buildLandscape(pos) : _buildPortrait(pos),
            // Anchor alarm overlay — shown on top of everything when alarm is active.
            if (AnchorService.instance.level == AnchorAlarmLevel.alarm &&
                !AnchorService.instance.isMuted)
              AnchorAlarmOverlay(
                dayMode: _dayMode, strobe: _strobeCtrl, muteController: _muteCtrl),
            // Waypoints — 48 × 48 hit area, icon visually at top-right corner.
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: _openWaypoints,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: Icon(
                        Icons.pin_drop_outlined,
                        size: 22,
                        color: _pal.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Debug screen — hold to open; deliberate action required.
            // GestureDetector instead of IconButton: IconButton's Tooltip
            // widget intercepts long-press to show tooltip text, so the
            // onLongPress callback never fires when a tooltip is set.
            // HitTestBehavior.opaque: transparent padding area responds to touches.
            // 48 px minimum touch target matches Material spec and IconButton default.
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                onLongPress: _openDebug,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, left: 6),
                      child: Icon(
                        Icons.bug_report_outlined,
                        size: 22,
                        color: _pal.focus,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Day / Night toggle — hold required (accidental switch during night
            // sailing would be dangerous).  Placed immediately left of waypoints.
            Positioned(
              top: 0,
              right: 48,
              child: GestureDetector(
                onLongPress: _toggleDayMode,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: Icon(
                        _dayMode ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                        size: 22,
                        color: _pal.pick(kDFg3, kN2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Adaptive secondary block ──────────────────────────────────────────────
  // Wraps the city / nav / anchor section so it ALWAYS fits the space left over
  // by the fixed heading/coords/MOB, shrinking uniformly instead of scrolling or
  // overlapping. This is THE mechanism that guarantees the no-scroll contract:
  // any widget placed here automatically participates in shrink-to-fit, so future
  // additions can't break the layout.
  //
  //   • Expanded      → claims exactly the leftover height (≥ 0 on all mandatory
  //                     devices because fixed sections sum well under the budget).
  //   • FittedBox     → scaleDown only: natural size when there's room, shrinks
  //                     uniformly when crowded, never enlarges.
  //   • SizedBox(W)   → pins the natural width to the full content width so rows
  //                     (bearing/distance, etc.) lay out normally before scaling.
  Widget _adaptiveSecondary({required List<Widget> children}) {
    return Expanded(
      child: LayoutBuilder(
        builder: (_, c) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: c.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortrait(Position pos) {
    final anchoring = AnchorService.instance.isActive;
    final nav = WaypointService.instance.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      // ── Layout contract (see CONSTITUTION §3) ───────────────────────────
      //   FIXED top    : heading + coordinates — always full size, always visible.
      //   ADAPTIVE mid : city + nav + anchor — shrinks uniformly to the leftover
      //                  space (FittedBox scaleDown). Never scrolls, never overlaps.
      //   FIXED bottom : MOB — always full size, always reachable.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headingSection(pos),
          _divider(),
          _coordsSection(),
          _divider(),
          _adaptiveSecondary(children: [
            if (_nearestCity != null)
              anchoring
                  ? _citySectionCompact(_nearestCity!)
                  : _citySection(_nearestCity!),
            if (anchoring) ...[
              _navWptCompact(pos),
              const SizedBox(height: 4),
              AnchorCard(dayMode: _dayMode, portrait: true, heading: _heading),
            ] else if (nav != null) ...[
              const SizedBox(height: 8),
              _navWptCard(pos, nav, portrait: true),
            ],
          ]),
          const SizedBox(height: 8),
          _mobSection(pos: pos, portrait: true),
        ],
      ),
    );
  }

  // Compact one-liner for nav waypoint bearing when anchoring.
  // Shows arrow + name + bearing + distance in a single tight row.
  Widget _navWptCompact(Position pos) {
    final nav = WaypointService.instance.active;
    if (nav == null) return const SizedBox.shrink();
    final b = bearing(pos.latitude, pos.longitude, nav.lat, nav.lon);
    final d = haversineKm(pos.latitude, pos.longitude, nav.lat, nav.lon);
    final navColor = _pal.nav;
    return GestureDetector(
      onLongPress: () => _openWaypoints(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          _arrowWithRelRing(b, navColor, 22),
          const SizedBox(width: 6),
          Expanded(child: Text(nav.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: navColor, fontWeight: FontWeight.w600))),
          Text('${b.round()}°',
              style: TextStyle(fontSize: 12, color: navColor.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text(formatDistanceUnit(d, _speedUnit),
              style: TextStyle(fontSize: 12, color: navColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }

  // Compact city row when anchoring: arrow+dot-ring, name, bearing°, distance.
  // Mirrors the nav waypoint compact row so both rows look consistent.
  Widget _citySectionCompact(NearestCity nc) {
    return GestureDetector(
      onTap: _toggleCityMode,
      onLongPress: () => _showCityDetails(nc),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          _arrowWithRelRing(nc.bearingDeg.toDouble(), _cityColor, 22),
          const SizedBox(width: 6),
          Expanded(child: Text(nc.city.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _cityColor, fontWeight: FontWeight.w600))),
          Text('${nc.bearingDeg.round()}°',
              style: TextStyle(fontSize: 12,
                  color: _citySubColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text(formatDistanceUnit(nc.distKm, _speedUnit),
              style: TextStyle(fontSize: 12, color: _cityColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }


  // ── Landscape layout ─────────────────────────────────────────────────────
  //
  // Left column  (fixed 252 dp): heading (arrow + degrees + speed + source)
  //                              + compact divider
  //                              + coordinates (lat / lon / locator / alt / time)
  //
  // Right column (Expanded):     city section
  //                              + compact divider
  //                              + active waypoint card / MOB button
  //
  // This split gives each section enough vertical room without stacking
  // everything into a single column that overflows on short landscape screens.
  // Font sizes are stepped down ~15 % from portrait — legible without
  // constantly shrinking with each new feature.
  Widget _buildLandscape(Position pos) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      // CrossAxisAlignment.stretch gives the right column the same height as the
      // Scaffold body so Spacer can pin the MOB section to the bottom.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: navigation data (40 % of available width) ──────────
          // Flexible flex values scale proportionally on any screen size.
          Flexible(
            flex: 4,
            fit: FlexFit.tight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _headingSectionLandscape(pos),
                _dividerCompact(),
                _coordsSectionLandscape(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Right: city + nav (scrollable) / MOB pinned at bottom ────
          Flexible(
            flex: 6,
            fit: FlexFit.tight,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: _cDivider, width: 1)),
              ),
              padding: const EdgeInsets.only(left: 14),
              // Adaptive middle (shrinks to fit) + fixed-bottom MOB — same
              // no-scroll contract as portrait.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _adaptiveSecondary(children: [
                    if (_nearestCity != null) ...[
                      AnchorService.instance.isActive
                          ? _citySectionCompact(_nearestCity!)
                          : _citySectionLandscape(_nearestCity!),
                      _dividerCompact(),
                    ],
                    if (!AnchorService.instance.isActive)
                      _navWptSectionLandscape(pos),
                    if (AnchorService.instance.isActive) ...[
                      _navWptCompact(pos),
                      const SizedBox(height: 4),
                      AnchorCard(dayMode: _dayMode, portrait: false, heading: _heading),
                      const SizedBox(height: 4),
                    ],
                  ]),
                  _mobSection(pos: pos, portrait: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _cDivider => _pal.divider;

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: _cDivider, height: 1),
      );

  Widget _dividerCompact() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(color: _cDivider, height: 1),
      );

  // ── Arrow with relative-bearing ring ─────────────────────────────────────
  // Wraps ArrowWidget with a thin ring whose dot shows WHERE the POI is
  // relative to the current heading (12 o'clock = ahead, 3 = right, …).
  // Bearing arrow + relative-direction ring for a POI (see RelBearingArrow).
  Widget _arrowWithRelRing(double bearingDeg, Color color, double size) =>
      RelBearingArrow(
        bearingDeg: bearingDeg,
        heading: _heading,
        color: color,
        size: size,
        dayMode: _dayMode,
      );

  // ── Bearing-ring markers ──────────────────────────────────────────────────
  // Returns the city and/or active-waypoint bearing as coloured dots that will
  // be drawn on the ring around the heading arrow, showing relative direction
  // ("is the POI ahead? to my right? behind me?") at a glance while driving.
  // City dot, navigation waypoint dot (amber, medium), MOB dot (red, largest).
  // sizeScale multiplies the base dot radius so urgency is also expressed by size.
  List<({double bearingDeg, Color color, double sizeScale})> _bearingMarkers(Position pos) {
    final result = <({double bearingDeg, Color color, double sizeScale})>[];

    // City
    if (_nearestCity != null) {
      result.add((bearingDeg: _nearestCity!.bearingDeg, color: _cityColor, sizeScale: 1.0));
    }

    // Navigation waypoint (non-emergency, selected from list)
    final navWp = WaypointService.instance.active;
    if (navWp != null) {
      // Day: deep orange-red — clearly distinct from city oranges/amber/lime.
    // Night: medium red (consistent with palette).
    final navColor = _pal.nav;
      result.add((
        bearingDeg: bearing(pos.latitude, pos.longitude, navWp.lat, navWp.lon),
        color: navColor,
        sizeScale: 1.2,
      ));
    }

    // Emergency MOB
    final mob = WaypointService.instance.emergency;
    if (mob != null) {
      result.add((
        bearingDeg: bearing(pos.latitude, pos.longitude, mob.lat, mob.lon),
        color: _pal.emergency,
        sizeScale: 1.45,
      ));
    }

    return result;
  }

  // ── Heading ───────────────────────────────────────────────────────────────
  Widget _headingSection(Position pos) {
    final color    = _headingColor;
    final primary  = _heading;
    final headingText = _intendedSourceHasData ? '${primary.round()}°' : '---';
    final markers  = _bearingMarkers(pos);
    final windRose = _headingArrowMode == HeadingArrowMode.windRose;
    return Row(children: [
      GestureDetector(
        onLongPress: _toggleHeadingArrowMode,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 80,
          height: 80,
          child: Stack(alignment: Alignment.center, children: [
            // Wind-rose: live ring via ValueListenableBuilder so secondary dash
            // repaints at compass rate even when GPS is the primary source.
            // Arrow mode: static ring (headed by GPS setState).
            if (windRose)
              ValueListenableBuilder<double>(
                valueListenable: _compassNotifier,
                builder: (_, compassBearing, __) {
                  final sec = _headingSourceMode == HeadingSourceMode.auto
                      ? compassBearing
                      : (_track.bearing ?? _lastValidGpsHeading);
                  return Positioned.fill(child: CustomPaint(
                    painter: BearingRingPainter(
                      primaryHeading: primary, markers: markers, dayMode: _dayMode,
                      windRoseMode: true, secondaryBearing: sec,
                      secondaryColor: _secondaryHeadingColor,
                    ),
                  ));
                },
              )
            else
              Positioned.fill(child: CustomPaint(
                painter: BearingRingPainter(
                  primaryHeading: primary, markers: markers, dayMode: _dayMode),
              )),
            // Arrow mode only — both arrows. Wind-rose shows no arrows.
            if (!windRose) ...[
              ValueListenableBuilder<double>(
                valueListenable: _compassNotifier,
                builder: (_, compassBearing, __) {
                  final sb = _headingSourceMode == HeadingSourceMode.auto
                      ? compassBearing
                      : (_track.bearing ?? _lastValidGpsHeading);
                  if (sb == null) return const SizedBox.shrink();
                  // Always dim the secondary arrow regardless of mode so it's
                  // clearly distinguishable from the primary in night mode.
                  return Opacity(opacity: 0.38,
                      child: ArrowWidget(bearingDeg: sb, color: _secondaryHeadingColor, size: 80));
                },
              ),
              ArrowWidget(bearingDeg: primary, color: color, size: 80),
            ],
          ]),
        ),
      ),
      const SizedBox(width: 20),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: _toggleHeadingSourceMode,
          behavior: HitTestBehavior.opaque,
          child: Text(headingText,
              style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.0)),
        ),
        GestureDetector(
          onLongPress: _cycleSpeedUnit,
          child: Text(
            formatSpeed(pos.speed, _speedUnit),
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: _cSpeed,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        _lockModeWidget(sourceFontSize: 14, trkFontSize: 14),
      ]),
    ]);
  }

  // Landscape heading: mirrors the portrait layout (arrow left, text right) so
  // both orientations feel consistent. A fixed-width SizedBox on the degrees
  // text prevents the whole section from shifting when digit count changes
  // (e.g. "9°" → "10°" → "359°"). TRK is always rendered so the row height
  // is stable regardless of whether a bearing is available.
  Widget _headingSectionLandscape(Position pos) {
    final color    = _headingColor;
    final primary  = _heading;
    final headingText = _intendedSourceHasData ? '${primary.round()}°' : '---';
    final markers  = _bearingMarkers(pos);
    final windRose = _headingArrowMode == HeadingArrowMode.windRose;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onLongPress: _toggleHeadingArrowMode,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 80,
            height: 80,
            child: Stack(alignment: Alignment.center, children: [
              if (windRose)
                ValueListenableBuilder<double>(
                  valueListenable: _compassNotifier,
                  builder: (_, compassBearing, __) {
                    final sec = _headingSourceMode == HeadingSourceMode.auto
                        ? compassBearing
                        : (_track.bearing ?? _lastValidGpsHeading);
                    return Positioned.fill(child: CustomPaint(
                      painter: BearingRingPainter(
                        primaryHeading: primary, markers: markers, dayMode: _dayMode,
                        windRoseMode: true, secondaryBearing: sec,
                        secondaryColor: _secondaryHeadingColor,
                      ),
                    ));
                  },
                )
              else
                Positioned.fill(child: CustomPaint(
                  painter: BearingRingPainter(
                    primaryHeading: primary, markers: markers, dayMode: _dayMode),
                )),
              if (!windRose) ...[
                ValueListenableBuilder<double>(
                  valueListenable: _compassNotifier,
                  builder: (_, compassBearing, __) {
                    final sb = _headingSourceMode == HeadingSourceMode.auto
                        ? compassBearing
                        : (_track.bearing ?? _lastValidGpsHeading);
                    if (sb == null) return const SizedBox.shrink();
                    return Opacity(opacity: 0.38,
                        child: ArrowWidget(bearingDeg: sb, color: _secondaryHeadingColor, size: 80));
                  },
                ),
                ArrowWidget(bearingDeg: primary, color: color, size: 80),
              ],
            ]),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onLongPress: _toggleHeadingSourceMode,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 120,
                child: Text(headingText,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1.0)),
              ),
            ),
            GestureDetector(
              onLongPress: _cycleSpeedUnit,
              child: Text(
                formatSpeed(pos.speed, _speedUnit),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: _cSpeed,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            _lockModeWidget(sourceFontSize: 12, trkFontSize: 12),
          ],
        ),
      ],
    );
  }

  // ── GPS lock mode indicator ───────────────────────────────────────────────
  // Shows the current heading source (GPS/MAG) and the GPS-during-lock mode.
  // Long-press either badge to toggle it (same UX as pocket-lock).
  Widget _lockModeWidget({required double sourceFontSize, required double trkFontSize}) {
    final modeColor = _gpsOnLock ? _cLiveLock : _cSaveLock;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: GPS toggle + pocket-lock toggle (same line).
        Row(mainAxisSize: MainAxisSize.min, children: [
          // GPS @ lock — long-press to toggle, matches pocket-lock UX.
          GestureDetector(
            onLongPress: _toggleGpsLock,
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_sourceLabel,
                  style: TextStyle(
                      fontSize: sourceFontSize,
                      color: _cText2,
                      letterSpacing: 2.5)),
              const SizedBox(width: 6),
              Icon(_gpsOnLock ? Icons.gps_fixed : Icons.gps_off,
                  size: sourceFontSize - 1, color: modeColor),
              Text('@',
                  style: TextStyle(
                      fontSize: sourceFontSize - 2,
                      color: modeColor,
                      height: 1.0)),
              Icon(Icons.lock, size: sourceFontSize - 1, color: modeColor),
            ]),
          ),
          // Pocket-lock toggle
          const SizedBox(width: 8),
          GestureDetector(
            onLongPress: _togglePocketLock,
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.smartphone,
                  size: sourceFontSize,
                  color: _pocketLockEnabled ? _cLiveLock : _cText3),
              Icon(
                _pocketLockEnabled ? Icons.lock : Icons.lock_open,
                size: sourceFontSize - 1,
                color: _pocketLockEnabled ? _cLiveLock : _cText3,
              ),
              Text('@',
                  style: TextStyle(
                      fontSize: sourceFontSize - 2,
                      color: _pocketLockEnabled ? _cLiveLock : _cText3,
                      height: 1.0)),
              Icon(Icons.sensors,
                  size: sourceFontSize - 1,
                  color: _pocketLockEnabled ? _cLiveLock : _cText3),
            ]),
          ),
        ]),
        // Row 2: TRK bearing.
        Text(
          _track.bearing != null
              ? 'TRK ${_track.bearing!.round()}°'
              : 'TRK ---',
          style: TextStyle(
              fontSize: trkFontSize,
              color: _cText3,
              letterSpacing: 1.5),
        ),
      ],
    );
  }

  void _openDebug() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DebugScreen(
        position: _position,
        compassHeading: _compassHeading,
        track: _track,
        coordFormat: _coordFormat,
        locatorType: _locatorType,
        speedUnit: _speedUnit,
        timeUtc: _timeUtc,
        dayMode: _dayMode,
      ),
    ));
  }

  // ── Coordinates ───────────────────────────────────────────────────────────
  Widget _coordsSection() {
    // Coordinates are "medium" priority — smaller than the locator (critical)
    // but bigger than altitude (tertiary). Long-press cycles the format.
    final coordStyle = TextStyle(
      fontSize: 22,
      color: _cText1,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => _copyToClipboard('$_cachedLatStr\n$_cachedLonStr'),
        onLongPress: _toggleCoordFormat,
        behavior: HitTestBehavior.opaque,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_cachedLatStr, style: coordStyle),
          const SizedBox(height: 2),
          Text(_cachedLonStr, style: coordStyle),
        ]),
      ),
      const SizedBox(height: 8),
      _locatorRow(fontSize: 32, letterSpacing: 4.0),
      const SizedBox(height: 6),
      _altAccuracyRow(),
      const SizedBox(height: 3),
      _timeRow(),
    ]);
  }

  Widget _coordsSectionLandscape() {
    final coordStyle = TextStyle(
      fontSize: 22,
      color: _cText1,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => _copyToClipboard('$_cachedLatStr\n$_cachedLonStr'),
        onLongPress: _toggleCoordFormat,
        behavior: HitTestBehavior.opaque,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_cachedLatStr, style: coordStyle),
          const SizedBox(height: 2),
          Text(_cachedLonStr, style: coordStyle),
        ]),
      ),
      const SizedBox(height: 6),
      _locatorRow(fontSize: 24, letterSpacing: 2.5),
      const SizedBox(height: 4),
      _altAccuracyRow(),
      const SizedBox(height: 3),
      _timeRow(fontSize: 15.0),
    ]);
  }

  // Single locator row used by both portrait and landscape coords sections.
  // IARU (green) vs MGRS (amber) — color and label make the type obvious.
  // Long-press toggles the type; tap copies the value.
  Widget _locatorRow({required double fontSize, required double letterSpacing}) {
    final isMaidenhead = _locatorType == LocatorType.maidenhead;
    final locColor = isMaidenhead ? _cLocator : _cMgrs;
    final labelColor = isMaidenhead ? _cLocatorLabel : _cMgrsLabel;
    final locFontSize = isMaidenhead ? fontSize : fontSize * 0.72;
    final locLetterSpacing = isMaidenhead ? letterSpacing : 0.5;
    final label = isMaidenhead ? 'IARU' : 'MGRS';

    return GestureDetector(
      onTap: () => _copyToClipboard(_cachedLocStr),
      onLongPress: _toggleLocatorType,
      behavior: HitTestBehavior.opaque,
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(_cachedLocStr,
            style: TextStyle(
                fontSize: locFontSize,
                color: locColor,
                fontWeight: FontWeight.w700,
                letterSpacing: locLetterSpacing,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: labelColor,
                letterSpacing: 1.5)),
      ]),
    );
  }

  Widget _altAccuracyRow() {
    final stale = _gpsStaleSeconds > 10;
    final altStr = formatAlt(_cachedAlt, _speedUnit);
    final accStr = '±${_cachedAccuracy.round()} m';
    final staleStr = stale ? '  GPS ${formatStaleDuration(_gpsStaleSeconds)}' : '';
    return Row(children: [
      Text('alt $altStr',
          style: TextStyle(
              fontSize: 14,
              color: _cAltAcc,
              fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(width: 12),
      Text('$accStr$staleStr',
          style: TextStyle(
              fontSize: 14,
              color: stale ? _cStale : _cAltAcc,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }

  Widget _timeRow({double fontSize = 18.0}) {
    // Compute the current GPS-calibrated time on every build.
    // _gpsClockOffset is updated on each GPS fix; between fixes the system
    // clock advances normally, so the display ticks every second in real time.
    // Before the first GPS fix the offset is zero and the system clock is shown.
    final now = DateTime.now().add(_gpsClockOffset);
    final dateStr = formatDateYmd(now, utc: _timeUtc);
    final timeStr = formatTimeHms(now, utc: _timeUtc);
    final color = _cTime;
    final label = _timeUtc ? 'UTC' : 'LCL';
    final labelColor = _cTimeLabel;
    final labelSize = fontSize >= 16 ? 12.0 : 11.0;
    return GestureDetector(
      onLongPress: _toggleTimeZone,
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        Text(dateStr,
            style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Text(timeStr,
            style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: labelSize,
                fontWeight: FontWeight.w700,
                color: labelColor,
                letterSpacing: 1.5)),
      ]),
    );
  }

  // ── City ──────────────────────────────────────────────────────────────────
  void _showCityDetails(NearestCity nc) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: _pal.sheetBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      isScrollControlled: true,
      builder: (_) => CityDetailSheet(
        nc: nc,
        dayMode: _dayMode,
        position: _position,
        speedUnit: _speedUnit,
        coordFormat: _coordFormat,
        locatorType: _locatorType,
      ),
    );
  }

  Widget _citySection(NearestCity nc) {
    final color = _cityColor;
    final subColor = _citySubColor;
    return GestureDetector(
      onTap: _toggleCityMode,
      onLongPress: () => _showCityDetails(nc),
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        _arrowWithRelRing(nc.bearingDeg, color, 60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (_, bc) {
            final fs = fitFontSize(nc.city.name, bc.maxWidth, maxSize: 32, minSize: 18);
            return Text(nc.city.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: fs, fontWeight: FontWeight.w700, color: color));
          }),
          Row(children: [
            Text('${nc.bearingDeg.round()}°',
                style: TextStyle(
                    fontSize: 22,
                    color: subColor,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 18),
            Text(formatDistanceUnit(nc.distKm, _speedUnit),
                style: TextStyle(
                    fontSize: 22,
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 14),
            Flexible(
              child: Text(nc.city.country,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      color: subColor.withValues(alpha: 0.7),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
          if (nc.city.vhf.isNotEmpty)
            GestureDetector(
              onTap: () => _copyToClipboard('VHF ${nc.city.vhf}'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.radio, size: 14, color: subColor),
                const SizedBox(width: 4),
                Text('VHF ${nc.city.vhf}',
                    style: TextStyle(
                        fontSize: 16,
                        color: color,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5)),
              ]),
            ),
          if (nc.city.callSign.isNotEmpty)
            Text(nc.city.callSign,
                style: TextStyle(
                    fontSize: 14,
                    color: subColor.withValues(alpha: 0.8),
                    letterSpacing: 2.0)),
        ]),
        ),   // Expanded
      ]),
    );
  }

  Widget _citySectionLandscape(NearestCity nc) {
    final color = _cityColor;
    final subColor = _citySubColor;
    return GestureDetector(
      onTap: _toggleCityMode,
      onLongPress: () => _showCityDetails(nc),
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        _arrowWithRelRing(nc.bearingDeg, color, 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: LayoutBuilder(builder: (_, bc) {
                  // 24px for short names; fitFontSize shrinks dynamically so long
                  // names still fit in 2 lines without overflowing the landscape layout.
                  final fs = fitFontSize(nc.city.name, bc.maxWidth, maxSize: 24, minSize: 10);
                  return Text(nc.city.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: fs, fontWeight: FontWeight.w700, color: color));
                }),
              ),
              const SizedBox(width: 6),
              Text(nc.city.country,
                  style: TextStyle(fontSize: 12, color: subColor.withValues(alpha: 0.7))),
            ]),
            Row(children: [
              Text('${nc.bearingDeg.round()}°',
                  style: TextStyle(
                      fontSize: 16,
                      color: subColor,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 10),
              Text(formatDistanceUnit(nc.distKm, _speedUnit),
                  style: TextStyle(
                      fontSize: 16,
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── Active waypoint (MOB) ─────────────────────────────────────────────────
  // ── Navigation waypoint (selected from list, amber) ──────────────────────
  Widget _navWptCard(Position pos, Waypoint wp, {required bool portrait}) {
    final b = bearing(pos.latitude, pos.longitude, wp.lat, wp.lon);
    final d = haversineKm(pos.latitude, pos.longitude, wp.lat, wp.lon);
    final navColor = _pal.nav;
    final navSub   = _pal.navLabel;
    final arrowSz  = portrait ? 50.0 : 36.0;
    final dataFz   = portrait ? 22.0 : 16.0;
    // Same hold-to-deactivate animation as MOB, targeting _WptHoldTarget.nav.
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Listener(
        onPointerDown: (_) => _startClear(_WptHoldTarget.nav),
        onPointerUp: (_) => _cancelClear(),
        onPointerCancel: (_) => _cancelClear(),
        child: CustomPaint(
          painter: WptBorderPainter(_holdTarget == _WptHoldTarget.nav ? _clearProgress : 0.0,
              dayMode: _dayMode),
          child: Padding(
            padding: portrait
                ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
                : const EdgeInsets.fromLTRB(10, 5, 10, 5),
            child: Row(children: [
              _arrowWithRelRing(b, navColor, arrowSz),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wp.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: navSub, letterSpacing: 1.2)),
                  Row(children: [
                    Text('${b.round()}°',
                        style: TextStyle(fontSize: dataFz, color: navSub,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: 12),
                    Text(formatDistanceUnit(d, _speedUnit),
                        style: TextStyle(fontSize: dataFz, color: navColor,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }

  // Nav waypoint only — used in the scrollable top portion of the landscape column.
  Widget _navWptSectionLandscape(Position pos) {
    final nav = WaypointService.instance.active;
    if (nav == null) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _navWptCard(pos, nav, portrait: false),
      const SizedBox(height: 4),
    ]);
  }

  // MOB card (when active) or MOB button — always pinned to the bottom in both
  // orientations.  Sized down slightly in landscape.
  Widget _mobSection({required Position pos, required bool portrait}) {
    final mob = WaypointService.instance.emergency;
    if (mob != null) return _wptCard(pos, mob, portrait: portrait);
    return SizedBox(
      width: double.infinity,
      height: portrait ? 80 : 62,
      child: ElevatedButton(
        onPressed: _addWaypoint,
        style: ElevatedButton.styleFrom(
          backgroundColor: _cMobBg, foregroundColor: _cMobText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        child: Text('MOB',
            style: TextStyle(
                fontSize: portrait ? 38 : 30,
                fontWeight: FontWeight.w900,
                letterSpacing: portrait ? 5 : 4)),
      ),
    );
  }

  Widget _wptCard(Position pos, Waypoint wp, {required bool portrait}) {
    final b = bearing(pos.latitude, pos.longitude, wp.lat, wp.lon);
    final d = haversineKm(pos.latitude, pos.longitude, wp.lat, wp.lon);
    final arrowSize = portrait ? 60.0 : 46.0;
    final nameFontSize = portrait ? 20.0 : 14.0;
    final dataFontSize = portrait ? 22.0 : 17.0;
    final coordFontSize = portrait ? 14.0 : 11.0;
    final padding = portrait
        ? const EdgeInsets.fromLTRB(14, 12, 14, 14)
        : const EdgeInsets.fromLTRB(10, 5, 10, 5);

    // Outer Padding ensures the border ring is never clipped by parent bounds.
    return Padding(
      padding: EdgeInsets.all(portrait ? 3 : 2),
      child: Listener(
      onPointerDown: (_) => _startClear(),
      onPointerUp: (_) => _cancelClear(),
      onPointerCancel: (_) => _cancelClear(),
      child: CustomPaint(
        painter: WptBorderPainter(
            _holdTarget == _WptHoldTarget.emergency ? _clearProgress : 0.0,
            dayMode: _dayMode),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Bearing row ─────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _arrowWithRelRing(b, _cWptArrow, arrowSize),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(wp.name,
                              style: TextStyle(
                                  fontSize: nameFontSize,
                                  fontWeight: FontWeight.w900,
                                  color: _cWptName,
                                  letterSpacing: 1.5)),
                        ),
                        Row(children: [
                          Text('${b.round()}°',
                              style: TextStyle(
                                  fontSize: dataFontSize,
                                  color: _cWptData,
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                          const SizedBox(width: 14),
                          Text(formatDistanceUnit(d, _speedUnit),
                              style: TextStyle(
                                  fontSize: dataFontSize,
                                  color: _cWptName,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: portrait ? 6 : 2),
              // ── [lat | date], [lon | time], [locator | elapsed] ─────────
              // All three rows share the same color palette so the right
              // column reads as part of the card rather than secondary info.
              _wptDataRow(
                left: formatLatF(wp.lat, _coordFormat),
                right: formatDateYmd(wp.timestamp, utc: _timeUtc),
                fontSize: coordFontSize,
              ),
              _wptDataRow(
                left: formatLonF(wp.lon, _coordFormat),
                right: '${formatTimeHms(wp.timestamp, utc: _timeUtc)} ${_timeUtc ? 'UTC' : 'LCL'}',
                fontSize: coordFontSize,
              ),
              const SizedBox(height: 2),
              _wptDataRow(
                left: _locStr(wp.lat, wp.lon),
                right: formatElapsed(DateTime.now().difference(wp.timestamp)),
                fontSize: coordFontSize,
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  // Single row in the waypoint data section: left-aligned label, right-aligned
  // value, both the same font size and the same dim-red card colour.
  Widget _wptDataRow({
    required String left,
    required String right,
    required double fontSize,
  }) {
    final style = TextStyle(
      fontSize: fontSize,
      color: _cWptCoords,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(left, style: style),
        Text(right, style: style),
      ],
    );
  }
}
