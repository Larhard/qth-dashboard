import 'package:flutter/foundation.dart' show ValueListenable, immutable;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../services/city_service.dart' show NearestCity;
import '../settings/display_settings.dart';
import '../utils/formatting.dart' show SpeedUnit;

/// What the dashboard sections need to render and what they can do.
///
/// [DashboardVm] is an immutable snapshot of the display state, rebuilt by
/// `_HomeScreenState.build()` each frame. [DashboardActions] bundles the action
/// callbacks (stable). Section widgets take `(vm, actions)` instead of a dozen
/// individual parameters, so the screen↔section boundary is one clear contract.
///
/// Sections derive their own *trivial* palette colours from `vm.dayMode`; the VM
/// carries only the colours that need screen-side logic (heading source, city tier).

@immutable
class DashboardActions {
  final VoidCallback toggleHeadingArrowMode;
  final VoidCallback toggleHeadingSource;
  final VoidCallback toggleCoordFormat;
  final VoidCallback toggleLocatorType;
  final VoidCallback toggleTimeZone;
  final VoidCallback cycleSpeedUnit;
  final VoidCallback toggleCityMode;
  final VoidCallback toggleGpsLock;
  final VoidCallback togglePocketLock;
  final VoidCallback openWaypoints;
  final void Function(String text) copy;
  final void Function(NearestCity nc) showCityDetails;

  const DashboardActions({
    required this.toggleHeadingArrowMode,
    required this.toggleHeadingSource,
    required this.toggleCoordFormat,
    required this.toggleLocatorType,
    required this.toggleTimeZone,
    required this.cycleSpeedUnit,
    required this.toggleCityMode,
    required this.toggleGpsLock,
    required this.togglePocketLock,
    required this.openWaypoints,
    required this.copy,
    required this.showCityDetails,
  });
}

@immutable
class DashboardVm {
  // Display modes / settings.
  final bool dayMode;
  final bool timeUtc;
  final SpeedUnit speedUnit;
  final LocatorType locatorType;
  final bool gpsOnLock;
  final bool pocketLockEnabled;

  // Position + heading.
  final Position position;
  final double heading; // primary heading value (already source-resolved)
  final Color headingColor; // colour for the primary source
  final Color secondaryHeadingColor;
  final String sourceLabel; // 'GPS' / 'TRK' / 'MAG'
  final bool headingValid; // false → show '---'
  final bool windRose; // heading arrow mode
  final bool sourceAuto; // heading source mode == auto
  final double? trackBearing;
  final double? lastValidGpsHeading;
  final ValueListenable<double> compassNotifier;
  final List<({double bearingDeg, Color color, double sizeScale})> markers;

  // Nearest city.
  final NearestCity? nearestCity;
  final Color cityColor;
  final Color citySubColor;

  // Coordinate / locator / clock display caches.
  final String latStr;
  final String lonStr;
  final String locStr;
  final double altMeters;
  final double accuracyMeters;
  final Duration gpsClockOffset;
  final int gpsStaleSeconds;

  const DashboardVm({
    required this.dayMode,
    required this.timeUtc,
    required this.speedUnit,
    required this.locatorType,
    required this.gpsOnLock,
    required this.pocketLockEnabled,
    required this.position,
    required this.heading,
    required this.headingColor,
    required this.secondaryHeadingColor,
    required this.sourceLabel,
    required this.headingValid,
    required this.windRose,
    required this.sourceAuto,
    required this.trackBearing,
    required this.lastValidGpsHeading,
    required this.compassNotifier,
    required this.markers,
    required this.nearestCity,
    required this.cityColor,
    required this.citySubColor,
    required this.latStr,
    required this.lonStr,
    required this.locStr,
    required this.altMeters,
    required this.accuracyMeters,
    required this.gpsClockOffset,
    required this.gpsStaleSeconds,
  });
}
