/// One amateur-radio award reference (summit, park, island, bunker…) plus the
/// normalized on-disk format every program is converted to.
///
/// Pure Dart (no Flutter) — shared with the `tool/fetch_refs.dart` build tool, so
/// the bundled assets and on-device updates use the exact same codec.
library;

import 'text_repair.dart';

class HamRef {
  /// Program reference, e.g. "SP/BZ-005", "US-0001", "AF-001".
  final String ref;
  final String name;
  final double lat;
  final double lon;

  /// Altitude in metres above mean sea level; 0 = unknown / not applicable.
  final int altM;

  /// Award points (SOTA); 0 = the program has no points.
  final int points;

  /// Seasonal bonus points (SOTA winter bonus); 0 = none.
  final int bonus;

  /// Free-form context: association / region / country / IOTA bounding box.
  /// IOTA stores `bbox:latMin,latMax,lonMin,lonMax` so the app can tell whether
  /// the user is inside the island group's area.
  final String extra;

  const HamRef({
    required this.ref,
    required this.name,
    required this.lat,
    required this.lon,
    this.altM = 0,
    this.points = 0,
    this.bonus = 0,
    this.extra = '',
  });

  /// "lat, lon" with 5 decimals (~1 m) — pasteable into Google Maps & hiking maps.
  String get coordsText => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

  /// IOTA group bounding box, if [extra] carries one.
  ({double latMin, double latMax, double lonMin, double lonMax})? get bbox {
    if (!extra.startsWith('bbox:')) return null;
    final p = extra.substring(5).split(',').map(double.tryParse).toList();
    if (p.length != 4 || p.any((v) => v == null)) return null;
    return (latMin: p[0]!, latMax: p[1]!, lonMin: p[2]!, lonMax: p[3]!);
  }

  // ── Normalized TSV codec ───────────────────────────────────────────────────
  // One reference per line, 8 tab-separated columns:
  //   ref  name  lat  lon  alt_m  points  bonus  extra
  // Lines starting with '#' are comments; the first line is the file header
  // (see [RefFileHeader]).

  String toTsv() => [
        _clean(ref),
        _clean(repairText(name)),
        lat.toStringAsFixed(5),
        lon.toStringAsFixed(5),
        '$altM',
        '$points',
        '$bonus',
        _clean(repairText(extra)),
      ].join('\t');

  static HamRef? fromTsv(String line) {
    if (line.isEmpty || line.startsWith('#')) return null;
    final p = line.split('\t');
    if (p.length < 4) return null;
    final lat = double.tryParse(p[2]);
    final lon = double.tryParse(p[3]);
    if (lat == null || lon == null) return null;
    int i(int idx) => idx < p.length ? (int.tryParse(p[idx]) ?? 0) : 0;
    return HamRef(
      ref: p[0],
      name: p[1],
      lat: lat,
      lon: lon,
      altM: i(4),
      points: i(5),
      bonus: i(6),
      extra: p.length > 7 ? p[7] : '',
    );
  }

  // Names and extras also pass through [repairText] (mojibake, HTML entities)
  // so every source is cleaned identically. Reference codes are kept verbatim.

  /// Tabs / newlines would corrupt the TSV; collapse them.
  static String _clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();

  @override
  bool operator ==(Object other) =>
      other is HamRef &&
      other.ref == ref &&
      other.name == name &&
      other.lat == lat &&
      other.lon == lon &&
      other.altM == altM &&
      other.points == points &&
      other.bonus == bonus &&
      other.extra == extra;

  @override
  int get hashCode => Object.hash(ref, name, lat, lon, altM, points, bonus, extra);

  @override
  String toString() => 'HamRef($ref, $name, $lat, $lon)';
}

/// First line of a normalized reference file:
/// `#qthrefs<TAB>1<TAB><categoryId><TAB><YYYY-MM-DD><TAB><count>`.
class RefFileHeader {
  static const magic = '#qthrefs';
  static const version = 1;

  final String categoryId;
  final DateTime date;
  final int count;

  const RefFileHeader(this.categoryId, this.date, this.count);

  String encode() =>
      '$magic\t$version\t$categoryId\t${_ymd(date)}\t$count';

  static RefFileHeader? parse(String firstLine) {
    final p = firstLine.trim().split('\t');
    if (p.length < 5 || p[0] != magic) return null;
    final date = DateTime.tryParse(p[3]);
    final count = int.tryParse(p[4]);
    if (date == null || count == null) return null;
    return RefFileHeader(p[2], date, count);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

/// Serialize a whole program to the normalized file format (header + rows).
String encodeRefFile(String categoryId, DateTime date, List<HamRef> refs) {
  final b = StringBuffer(RefFileHeader(categoryId, date, refs.length).encode());
  for (final r in refs) {
    b
      ..write('\n')
      ..write(r.toTsv());
  }
  b.write('\n');
  return b.toString();
}
