import 'package:get_storage/get_storage.dart';

/// Persisted display preferences (clock, coordinate format, locator type, and the
/// two heading display modes).  Each is a small enum with GetStorage load/save.

// ── Clock: UTC vs local ──────────────────────────────────────────────────────
const _timeUtcKey = 'time_utc';
bool loadTimeUtc() => GetStorage().read<bool>(_timeUtcKey) ?? true;
void saveTimeUtc(bool v) => GetStorage().write(_timeUtcKey, v);

// ── Coordinate format ────────────────────────────────────────────────────────
enum CoordFormat { degMinDec, degDec, degMinSec }

const _coordFmtKey = 'coord_format';
CoordFormat loadCoordFormat() {
  final idx = GetStorage().read<int>(_coordFmtKey) ?? 0;
  return CoordFormat.values[idx.clamp(0, CoordFormat.values.length - 1)];
}
void saveCoordFormat(CoordFormat f) => GetStorage().write(_coordFmtKey, f.index);

// ── Locator type ─────────────────────────────────────────────────────────────
enum LocatorType { maidenhead, mgrs }

const _locTypeKey = 'locator_type';
LocatorType loadLocatorType() {
  final idx = GetStorage().read<int>(_locTypeKey) ?? 0;
  return LocatorType.values[idx.clamp(0, LocatorType.values.length - 1)];
}
void saveLocatorType(LocatorType t) => GetStorage().write(_locTypeKey, t.index);

// ── Heading arrow display mode ───────────────────────────────────────────────
// arrow    = simple rotating arrow + relative dots (mode A)
// windRose = compass rose rotating around the arrow (mode B)
enum HeadingArrowMode { arrow, windRose }

const _arrowModeKey = 'heading_arrow_mode';
HeadingArrowMode loadHeadingArrowMode() {
  final idx = GetStorage().read<int>(_arrowModeKey) ?? 0;
  return HeadingArrowMode.values[idx.clamp(0, HeadingArrowMode.values.length - 1)];
}
void saveHeadingArrowMode(HeadingArrowMode m) =>
    GetStorage().write(_arrowModeKey, m.index);

// ── Heading source mode ──────────────────────────────────────────────────────
// magOnly = compass always primary  (TRK/GPS secondary)
// auto    = GPS when fast, TRK when medium speed, MAG when slow (MAG secondary)
enum HeadingSourceMode { magOnly, auto }

const _sourceModeKey = 'heading_source_mode';
HeadingSourceMode loadHeadingSourceMode() {
  final idx = GetStorage().read<int>(_sourceModeKey) ?? 0;
  return HeadingSourceMode.values[idx.clamp(0, HeadingSourceMode.values.length - 1)];
}
void saveHeadingSourceMode(HeadingSourceMode m) =>
    GetStorage().write(_sourceModeKey, m.index);
