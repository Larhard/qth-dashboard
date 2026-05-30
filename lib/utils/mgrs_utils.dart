import 'dart:math';

/// Converts WGS84 lat/lon to an MGRS string with 1 m precision.
/// Format: "32U NB 12345 67890"
/// Returns 'POLAR' for latitudes outside the standard UTM range (±80° / +84°).
String mgrs(double lat, double lon) {
  if (lat > 84.0 || lat < -80.0) return 'POLAR';

  // ── Zone number ───────────────────────────────────────────────────────────
  var zoneNum = ((lon + 180.0) / 6.0).floor() + 1;
  if (lon == 180.0) zoneNum = 60;

  // Special zones: Norway (V/32) and Svalbard (X zones).
  final band = _latBand(lat);
  if (band == 'V' && zoneNum == 31 && lon >= 3.0) zoneNum = 32;
  if (band == 'X') {
    if (lon < 9.0) zoneNum = 31;
    else if (lon < 21.0) zoneNum = 33;
    else if (lon < 33.0) zoneNum = 35;
    else if (lon < 42.0) zoneNum = 37;
  }

  // ── Transverse Mercator projection (WGS84) ────────────────────────────────
  const a = 6378137.0;
  const f = 1.0 / 298.257223563;
  const e2 = 2 * f - f * f;
  const ep2 = e2 / (1.0 - e2);
  const k0 = 0.9996;

  final lonOrigin = ((zoneNum - 1) * 6.0 - 180.0 + 3.0) * pi / 180.0;
  final phi = lat * pi / 180.0;
  final lam = lon * pi / 180.0;

  final sp = sin(phi);
  final cp = cos(phi);
  final tp = tan(phi);

  final N = a / sqrt(1.0 - e2 * sp * sp);
  final T = tp * tp;
  final C = ep2 * cp * cp;
  final A = cp * (lam - lonOrigin);

  final M = a * (
      (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0) * phi
    - (3.0 * e2 / 8.0 + 3.0 * e2 * e2 / 32.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(2.0 * phi)
    + (15.0 * e2 * e2 / 256.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(4.0 * phi)
    - (35.0 * e2 * e2 * e2 / 3072.0) * sin(6.0 * phi));

  final easting = k0 * N * (A + (1.0 - T + C) * A * A * A / 6.0
      + (5.0 - 18.0 * T + T * T + 72.0 * C - 58.0 * ep2) * A * A * A * A * A / 120.0)
      + 500000.0;

  var northing = k0 * (M + N * tp * (A * A / 2.0
      + (5.0 - T + 9.0 * C + 4.0 * C * C) * A * A * A * A / 24.0
      + (61.0 - 58.0 * T + T * T + 600.0 * C - 330.0 * ep2) * A * A * A * A * A * A / 720.0));
  if (lat < 0.0) northing += 10000000.0;

  // ── MGRS letter coding ────────────────────────────────────────────────────
  final col = _colLetter(zoneNum, easting);
  final row = _rowLetter(zoneNum, northing, lat >= 0.0);

  final eg = (easting % 100000.0).round().clamp(0, 99999).toString().padLeft(5, '0');
  final ng = (northing % 100000.0).round().clamp(0, 99999).toString().padLeft(5, '0');

  return '${zoneNum.toString().padLeft(2, '0')}$band $col$row $eg $ng';
}

String _latBand(double lat) {
  const bands = 'CDEFGHJKLMNPQRSTUVWX';
  return bands[((lat + 80.0) / 8.0).floor().clamp(0, 19)];
}

// Column letters cycle every 3 zones: ABCDEFGH / JKLMNPQR / STUVWXYZ.
String _colLetter(int zone, double easting) {
  const sets = ['ABCDEFGH', 'JKLMNPQR', 'STUVWXYZ'];
  return sets[(zone - 1) % 3][((easting / 100000.0).floor() - 1).clamp(0, 7)];
}

// Row letters cycle through 20 letters (no I/O). Even zones are offset by 5.
String _rowLetter(int zone, double northing, bool northern) {
  const rows = 'ABCDEFGHJKLMNPQRSTUV';
  final n = northern ? northing : northing - 10000000.0;
  final offset = zone.isEven ? 5 : 0;
  final idx = ((n / 100000.0).floor() + offset) % 20;
  return rows[idx < 0 ? idx + 20 : idx];
}
