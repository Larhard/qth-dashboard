import '../config/tuning.dart';
import '../settings/display_settings.dart';

/// Pure heading-source selection — extracted from the dashboard so the "honest"
/// rule (constitution §5.4) is unit-testable in isolation.
///
/// There are three sources: the magnetic compass (MAG), the smoothed GPS track
/// bearing (TRK), and the instantaneous GPS course (GPS).

enum HeadingSource { mag, trk, gps }

extension HeadingSourceLabel on HeadingSource {
  String get label => switch (this) {
        HeadingSource.gps => 'GPS',
        HeadingSource.trk => 'TRK',
        HeadingSource.mag => 'MAG',
      };
}

/// True when the GPS course is trustworthy enough to use as a heading: moving at
/// least [GpsTuning.gpsHeadingMinSpeed] and reporting a valid course.
bool gpsHeadingUsable(double speed, double heading) =>
    speed >= GpsTuning.gpsHeadingMinSpeed && !heading.isNaN && heading >= 0;

/// The outcome of heading-source selection.
class HeadingChoice {
  /// Drives the live heading VALUE and the compass listener. While auto mode is
  /// still waiting for GPS/TRK this stays MAG, so the live compass keeps the arrow
  /// rotating instead of freezing.
  final HeadingSource computed;

  /// Drives the user-facing LABEL and COLOUR. In auto mode this is never silently
  /// MAG — before data arrives it reads TRK ("waiting for signal").
  final HeadingSource display;

  /// True when GPS/TRK data is actually available; when false the degree readout
  /// shows `---` rather than a plausible-looking MAG value.
  final bool hasData;

  const HeadingChoice({
    required this.computed,
    required this.display,
    required this.hasData,
  });

  /// True when moving under GPS/TRK rather than the magnetic compass. The compass
  /// listener uses this to decide whether to keep driving live redraws.
  bool get usingGps => computed != HeadingSource.mag;
}

/// Selects the heading source from the current mode and what data is available.
///
/// - `magOnly`: MAG is always primary; the complementary TRK/GPS is the secondary.
/// - `auto`: GPS when fast → TRK when moving → otherwise MAG drives the live arrow
///   but the DISPLAY shows TRK with `hasData == false` (so the value reads `---`),
///   honouring the no-silent-fallback rule.
HeadingChoice chooseHeadingSource({
  required HeadingSourceMode mode,
  required bool gpsUsable,
  required bool trkAvailable,
}) {
  if (mode == HeadingSourceMode.magOnly) {
    return const HeadingChoice(
        computed: HeadingSource.mag, display: HeadingSource.mag, hasData: true);
  }
  if (gpsUsable) {
    return const HeadingChoice(
        computed: HeadingSource.gps, display: HeadingSource.gps, hasData: true);
  }
  if (trkAvailable) {
    return const HeadingChoice(
        computed: HeadingSource.trk, display: HeadingSource.trk, hasData: true);
  }
  // Auto mode, no GPS/TRK yet: MAG drives the live arrow, but the user sees TRK
  // and a `---` value rather than a silent MAG reading.
  return const HeadingChoice(
      computed: HeadingSource.mag, display: HeadingSource.trk, hasData: false);
}
