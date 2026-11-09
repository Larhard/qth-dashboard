/// Parsers that turn each program's upstream download into normalized [HamRef]s.
///
/// Pure Dart (no Flutter). The SAME functions run in two places:
///   • `tool/fetch_refs.dart` — at build time, to produce the bundled assets;
///   • `services/ref_updater.dart` — on the phone, for "Update via network".
/// One implementation means the bundled data and on-device updates can never
/// disagree. Each parser keeps only currently-valid references with usable
/// coordinates, and is unit-tested against real upstream sample rows
/// (`test/ref_parsers_test.dart`).
library;

import 'dart:convert';

import '../models/ham_ref.dart';
import '../models/poi_category.dart';
import 'csv.dart';

typedef RefParser = List<HamRef> Function(String body, {DateTime? today});

/// Parser for a category, or null when the program has no source yet.
RefParser? parserFor(PoiCategory c) => switch (c) {
      PoiCategory.sota => parseSota,
      PoiCategory.pota => parsePota,
      PoiCategory.wwff => parseWwff,
      PoiCategory.iota => parseIota,
      PoiCategory.bota => parseBota,
      PoiCategory.llota => parseLlota,
      PoiCategory.tota => parseTota,
      // Multi-part sources: the parser handles ONE part (see RefSource.partUrl).
      PoiCategory.gma => parseGmaRegion,
      PoiCategory.wca => parseCotaPrefix,
      PoiCategory.mota => parseMotaPrefix,
      PoiCategory.zlota => parseZlota,
      PoiCategory.gia => parseGia,
      PoiCategory.sbw => parseSbw,
      PoiCategory.siota => parseSiota,
      PoiCategory.arlhs => parseArlhs,
      PoiCategory.wlota => parseWlota,
      // HEMA is read from several page types and joined in refdata/fetch.dart.
      _ => null,
    };

// ── helpers ──────────────────────────────────────────────────────────────────

bool _validCoord(double? lat, double? lon) =>
    lat != null &&
    lon != null &&
    lat.isFinite &&
    lon.isFinite &&
    lat.abs() <= 90 &&
    lon.abs() <= 180 &&
    !(lat == 0 && lon == 0); // (0,0) = "unknown" in several upstream lists

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
int _i(Object? v) => v is num ? v.round() : (int.tryParse('${v ?? ''}'.trim()) ?? 0);
String _s(Object? v) => v == null ? '' : '$v'.trim();

String _join(Iterable<String> parts, [String sep = ' · ']) =>
    parts.map((p) => p.trim()).where((p) => p.isNotEmpty && p != '-').join(sep);

/// Index of every header name in [header] (exact match, trimmed).
Map<String, int> _cols(List<String> header) =>
    {for (var i = 0; i < header.length; i++) header[i].trim(): i};

/// Walks a CSV whose header row contains [requiredColumn]; rows before the
/// header (e.g. SOTA's title line) are skipped.
List<HamRef> _csv(
  String body,
  String requiredColumn,
  HamRef? Function(String Function(String col) get) build,
) {
  final out = <HamRef>[];
  Map<String, int>? cols;
  forEachCsvRow(body, (row) {
    if (cols == null) {
      if (row.map((c) => c.trim()).contains(requiredColumn)) cols = _cols(row);
      return;
    }
    String get(String col) {
      final i = cols![col];
      return (i == null || i >= row.length) ? '' : row[i].trim();
    }

    final r = build(get);
    if (r != null) out.add(r);
  });
  return out;
}

// ── SOTA — https://storage.sota.org.uk/summitslist.csv ──────────────────────
// Title line, then: SummitCode,AssociationName,RegionName,SummitName,AltM,AltFt,
// GridRef1,GridRef2,Longitude,Latitude,Points,BonusPoints,ValidFrom,ValidTo,…
// Dates are dd/mm/yyyy. Retired (ValidTo < today) and future summits are skipped.

List<HamRef> parseSota(String body, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  DateTime? dmy(String s) {
    final p = s.split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
    return (d == null || m == null || y == null) ? null : DateTime(y, m, d);
  }

  return _csv(body, 'SummitCode', (get) {
    final from = dmy(get('ValidFrom'));
    final to = dmy(get('ValidTo'));
    if (from != null && from.isAfter(day)) return null;
    if (to != null && to.isBefore(day)) return null;
    final lat = _d(get('Latitude')), lon = _d(get('Longitude'));
    if (!_validCoord(lat, lon)) return null;
    return HamRef(
      ref: get('SummitCode'),
      name: get('SummitName'),
      lat: lat!,
      lon: lon!,
      altM: _i(get('AltM')),
      points: _i(get('Points')),
      bonus: _i(get('BonusPoints')),
      extra: _join([get('AssociationName'), get('RegionName')]),
    );
  });
}

// ── POTA — https://pota.app/all_parks_ext.csv ───────────────────────────────
// "reference","name","active","entityId","locationDesc","latitude","longitude","grid"

List<HamRef> parsePota(String body, {DateTime? today}) =>
    _csv(body, 'reference', (get) {
      if (get('active') != '1') return null;
      final lat = _d(get('latitude')), lon = _d(get('longitude'));
      if (!_validCoord(lat, lon)) return null;
      return HamRef(
        ref: get('reference'),
        name: get('name'),
        lat: lat!,
        lon: lon!,
        extra: get('locationDesc'),
      );
    });

// ── WWFF — https://wwff.co/wwff-data/wwff_directory.csv ─────────────────────
// reference,status,name,program,dxcc,state,county,continent,iota,iaruLocator,
// latitude,longitude,…,country,region,…

List<HamRef> parseWwff(String body, {DateTime? today}) =>
    _csv(body, 'reference', (get) {
      if (get('status').toLowerCase() != 'active') return null;
      final lat = _d(get('latitude')), lon = _d(get('longitude'));
      if (!_validCoord(lat, lon)) return null;
      return HamRef(
        ref: get('reference'),
        name: get('name'),
        lat: lat!,
        lon: lon!,
        extra: _join([get('region'), get('country')]),
      );
    });

// ── IOTA — iota-world.org fulllist.json ─────────────────────────────────────
// [{refno, name, latitude_max, latitude_min, longitude_max, longitude_min,
//   sub_groups:[{status}…]}…]. Groups are AREAS: we store the bounding-box centre
// as the point and the box itself in `extra` (so "inside the group" can be
// shown). Boxes crossing the antimeridian (lonMax < lonMin) are unwrapped.

List<HamRef> parseIota(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final g in data) {
    if (g is! Map) continue;
    final subs = g['sub_groups'];
    if (subs is List &&
        subs.isNotEmpty &&
        subs.every((s) => s is Map && _s(s['status']).toLowerCase().startsWith('del'))) {
      continue; // every island of the group is deleted
    }
    final a = _d(g['latitude_min']), b = _d(g['latitude_max']);
    final c = _d(g['longitude_min']), d = _d(g['longitude_max']);
    if (a == null || b == null || c == null || d == null) continue;
    final latMin = a < b ? a : b, latMax = a < b ? b : a;
    final lonMin = c;
    var lonMax = d;
    if (lonMax < lonMin) lonMax += 360; // crosses the antimeridian
    var lon = (lonMin + lonMax) / 2;
    if (lon > 180) lon -= 360;
    final lat = (latMin + latMax) / 2;
    if (!_validCoord(lat, lon)) continue;
    out.add(HamRef(
      ref: _s(g['refno']),
      name: _s(g['name']),
      lat: lat,
      lon: lon,
      extra: 'bbox:$latMin,$latMax,$c,$d',
    ));
  }
  return out;
}

// ── BOTA (WWBOTA) — https://api.wwbota.org/bunkers/ ─────────────────────────
// [{dxcc, reference, type, long, extra, scheme, name, lat, locator}…]

List<HamRef> parseBota(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final b in data) {
    if (b is! Map) continue;
    final lat = _d(b['lat']), lon = _d(b['long']);
    if (!_validCoord(lat, lon)) continue;
    out.add(HamRef(
      ref: _s(b['reference']),
      name: _s(b['name']),
      lat: lat!,
      lon: lon!,
      extra: _join([_s(b['scheme']), _s(b['type'])]),
    ));
  }
  return out;
}

// ── LLOTA — https://llota.app/api/public/references ─────────────────────────
// [{reference_code, name, latitude, longitude, region, country_name, …}…]

List<HamRef> parseLlota(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final l in data) {
    if (l is! Map) continue;
    final lat = _d(l['latitude']), lon = _d(l['longitude']);
    if (!_validCoord(lat, lon)) continue;
    out.add(HamRef(
      ref: _s(l['reference_code']),
      name: _s(l['name']),
      lat: lat!,
      lon: lon!,
      extra: _join([_s(l['region']), _s(l['country_name'])]),
    ));
  }
  return out;
}

// ── TOTA — rozhledny.eu/servis/generate_csv.php?ref=ALL&filter=all ─────────
// UTF-8 + BOM, ';'-separated:
// Ref;DXCC_ID;DXCC_Name;Nazev;Obec;Okres;Kraj;Kota_m;Vyska_veze_m;Lokator;Lat;Lon;Pristupna
// (Nazev = name, Obec = municipality, Kraj = region, Kota_m = ground altitude,
//  Vyska_veze_m = tower height, Pristupna = accessible: ano / omezeně / ne)

List<HamRef> parseTota(String body, {DateTime? today}) {
  final out = <HamRef>[];
  Map<String, int>? cols;
  forEachCsvRow(body, (row) {
    if (cols == null) {
      if (row.map((c) => c.trim()).contains('Ref')) cols = _cols(row);
      return;
    }
    String get(String col) {
      final i = cols![col];
      return (i == null || i >= row.length) ? '' : row[i].trim();
    }

    final lat = _d(get('Lat')), lon = _d(get('Lon'));
    if (!_validCoord(lat, lon) || get('Ref').isEmpty) return;
    final height = get('Vyska_veze_m');
    final access = switch (get('Pristupna').toLowerCase()) {
      'ne' => 'no public access',
      'omezeně' || 'omezene' => 'limited access',
      _ => '',
    };
    out.add(HamRef(
      ref: get('Ref'),
      name: get('Nazev'),
      lat: lat!,
      lon: lon!,
      altM: (_d(get('Kota_m')) ?? 0).round(),
      extra: _join([
        get('Obec'),
        get('Kraj'),
        if (height.isNotEmpty) 'tower $height m',
        access,
      ]),
    ));
  }, separator: ';');
  return out;
}

// ── GMA — maps.gma.rocks/load_gma.php?region=<code> (one region per part) ──
// GeoJSON FeatureCollection; properties {ref, name, points}, Point [lon, lat].
// Only GMA-specific references — SOTA summits are automatically valid for GMA
// and are NOT duplicated here (see the SOTA category).

List<HamRef> parseGmaRegion(String body, {DateTime? today}) => _geoJson(body);

// ── WCA castles — maps.gma.rocks/load_cota.php?prefix=<prefix> (per part) ──
// [{ref (WCA no., e.g. OK-00001), name, latitude, longitude, cota (national
//   ref, e.g. JC-001), ort (town), …}]. GMA's COTA layer holds the castles that
// have coordinates (the official WCALIST.ods mostly has none).

List<HamRef> parseCotaPrefix(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final c in data) {
    if (c is! Map) continue;
    final lat = _d(c['latitude']), lon = _d(c['longitude']);
    if (!_validCoord(lat, lon) || _s(c['ref']).isEmpty) continue;
    out.add(HamRef(
      ref: _s(c['ref']),
      name: _s(c['name']),
      lat: lat!,
      lon: lon!,
      extra: _join([_s(c['cota']), _s(c['ort'])]),
    ));
  }
  return out;
}

// ── GMA map-service GeoJSON (GMA regions, GIA, SBW, MOTA parts) ─────────────
// FeatureCollection; Point [lon, lat]; properties carry at least {ref, name}.

List<HamRef> _geoJson(String body, {String Function(Map props)? extra}) {
  final out = <HamRef>[];
  final data = jsonDecode(body);
  final feats = data is Map ? data['features'] : null;
  if (feats is! List) return out;
  for (final f in feats) {
    if (f is! Map) continue;
    final props = f['properties'], geom = f['geometry'];
    if (props is! Map || geom is! Map) continue;
    final c = geom['coordinates'];
    if (c is! List || c.length < 2) continue;
    final lon = _d(c[0]), lat = _d(c[1]);
    if (!_validCoord(lat, lon) || _s(props['ref']).isEmpty) continue;
    out.add(HamRef(
      ref: _s(props['ref']),
      name: _s(props['name']),
      lat: lat!,
      lon: lon!,
      points: _i(props['points']),
      extra: extra?.call(props) ?? '',
    ));
  }
  return out;
}

// ── GIA — gmamap/load_gia.php (single GeoJSON; properties ref, name, ref2, wff) ──
List<HamRef> parseGia(String body, {DateTime? today}) => _geoJson(body,
    extra: (p) => _join([_s(p['ref2']), if (_s(p['wff']).isNotEmpty) 'WWFF ${_s(p['wff'])}']));

// ── SBW — gmamap/load_sbw.php (single GeoJSON; properties ref, name, points) ──
List<HamRef> parseSbw(String body, {DateTime? today}) => _geoJson(body);

// ── MOTA — gmamap/load_mota.php?pfx=<prefix> (one prefix per part) ──────────
// properties {id, ref (X00113), name, type}. Unknown positions are sent as
// 9999.99… (rejected by _validCoord).
const _millTypes = {1: 'water mill', 2: 'windmill', 3: 'motor mill', 4: 'animal-powered mill'};

List<HamRef> parseMotaPrefix(String body, {DateTime? today}) =>
    _geoJson(body, extra: (p) => _millTypes[_i(p['type'])] ?? '');

// ── SiOTA — https://www.silosontheair.com/data/silos.csv ─────────────────────
// ID,LAT,LNG,ARTY,NAME,LOCALITY,STATE,COUNTRY,SILO_CODE,…,NOT_BEFORE,NOT_AFTER,…
// NOT_BEFORE / NOT_AFTER are ISO timestamps; outside that window = not valid.

List<HamRef> parseSiota(String body, {DateTime? today}) {
  final now = (today ?? DateTime.now()).toUtc();
  return _csv(body, 'SILO_CODE', (get) {
    final from = DateTime.tryParse(get('NOT_BEFORE'));
    final to = DateTime.tryParse(get('NOT_AFTER'));
    if ((from != null && from.isAfter(now)) || (to != null && to.isBefore(now))) return null;
    final lat = _d(get('LAT')), lon = _d(get('LNG'));
    if (!_validCoord(lat, lon) || get('SILO_CODE').isEmpty) return null;
    return HamRef(
      ref: get('SILO_CODE'),
      name: get('NAME'),
      lat: lat!,
      lon: lon!,
      extra: _join([get('LOCALITY'), get('STATE'), if (get('ARTY') == 'true') 'silo art']),
    );
  });
}

// ── ZLOTA — https://ontheair.nz/api/assets?asset_type=<type> (one type per part)
// [{code, name, asset_type, location: "POINT (lon lat)", altitude, region,
//   is_active, …}]. Code prefix = type: ZLH/ hut, ZLI/ island, ZLL/ lake,
// ZLP/ park, ZLV/ volcano, ZLB/ lighthouse.

final _wktPoint = RegExp(r'POINT\s*\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)');

List<HamRef> parseZlota(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final a in data) {
    if (a is! Map || a['is_active'] == false) continue;
    final m = _wktPoint.firstMatch(_s(a['location']));
    if (m == null) continue;
    final lon = _d(m[1]), lat = _d(m[2]);
    if (!_validCoord(lat, lon) || _s(a['code']).isEmpty) continue;
    out.add(HamRef(
      ref: _s(a['code']),
      name: _s(a['name']),
      lat: lat!,
      lon: lon!,
      altM: _i(a['altitude']),
      extra: _join([_s(a['asset_type']), _s(a['region'])]),
    ));
  }
  return out;
}

// ── ARLHS — gmamap/load_arlhs.php (single JSON array) ───────────────────────
// [{arlhs ("FED 001" / "FED-069"), illw, wlota, name, iota, dxcc, latitude,
//   longitude, …}]. Refs are normalized to AAA-nnn; malformed ones skipped.

final _arlhsRef = RegExp(r'^([A-Z]{3})[\s-]*(\d{1,4})$');

String? _wlotaRef(Object? v) {
  final n = _i(v);
  return n > 0 ? 'L ${'$n'.padLeft(4, '0')}' : null;
}

List<HamRef> parseArlhs(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final seen = <String>{};
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final c in data) {
    if (c is! Map) continue;
    final m = _arlhsRef.firstMatch(_s(c['arlhs']).toUpperCase());
    if (m == null) continue;
    final ref = '${m[1]}-${m[2]!.padLeft(3, '0')}';
    final lat = _d(c['latitude']), lon = _d(c['longitude']);
    if (!_validCoord(lat, lon) || !seen.add(ref)) continue;
    final wlota = _wlotaRef(c['wlota']);
    out.add(HamRef(
      ref: ref,
      name: _s(c['name']),
      lat: lat!,
      lon: lon!,
      extra: _join([
        _s(c['dxcc']),
        if (_s(c['illw']).isNotEmpty) 'ILLW ${_s(c['illw'])}',
        if (wlota != null) 'WLOTA $wlota',
        if (_s(c['iota']).isNotEmpty) 'IOTA ${_s(c['iota'])}',
      ]),
    ));
  }
  return out;
}

// ── WLOTA — gmamap/load_wlota.php (single JSON array, ARLHS-like schema) ────
// wlota is an integer; shown as "L 0504" (the rules' format).

List<HamRef> parseWlota(String body, {DateTime? today}) {
  final out = <HamRef>[];
  final seen = <String>{};
  final data = jsonDecode(body);
  if (data is! List) return out;
  for (final c in data) {
    if (c is! Map) continue;
    final ref = _wlotaRef(c['wlota']);
    final lat = _d(c['latitude']), lon = _d(c['longitude']);
    if (ref == null || !_validCoord(lat, lon) || !seen.add(ref)) continue;
    out.add(HamRef(
      ref: ref,
      name: _s(c['name']),
      lat: lat!,
      lon: lon!,
      extra: _join([
        _s(c['dxcc']),
        if (_s(c['iota']).isNotEmpty) 'IOTA ${_s(c['iota'])}',
        if (_s(c['arlhs']).isNotEmpty) 'ARLHS ${_s(c['arlhs'])}',
      ]),
    ));
  }
  return out;
}

// ── HEMA — https://www.hema.org.uk/ (no export; pages are read and joined) ──
// countries.jsp → country.jsp?countryCode=GW → region.jsp?countryCode=GW&
// regionCode=HSW (rows "001 - Allt Cunedda" + "192m", keyed by summitKey) and
// mapping.jsp?countryCode=GW (map markers: lat, lon, name, summitKey).
// Reference = <country>/<region>-<nnn>, e.g. GW/HSW-001. See refdata/fetch.dart.

final _hemaCountry = RegExp(r'country\.jsp\?countryCode=([A-Za-z0-9]+)');
final _hemaRegion =
    RegExp(r'region\.jsp\?countryCode=([A-Za-z0-9]+)&(?:amp;)?regionCode=([A-Za-z0-9]+)');
final _hemaRow = RegExp(
    r'''fullSummit\.jsp\?summitKey=(\d+)['"]\s*>\s*(\d+)\s*-\s*(.*?)</a>\s*</td>\s*<td[^>]*>\s*(\d+)\s*m''',
    dotAll: true);
final _hemaMarker = RegExp(
    r'var Latitude=(-?[\d.]+);\s*var Longitude=(-?[\d.]+);.*?summitKey=(\d+)',
    dotAll: true);

String _unHtml(String s) => s
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .trim();

/// Country codes on countries.jsp, in page order.
List<String> parseHemaCountries(String html) =>
    {for (final m in _hemaCountry.allMatches(html)) m[1]!}.toList();

/// Region codes of [country] on its country.jsp page.
List<String> parseHemaRegions(String html, String country) => {
      for (final m in _hemaRegion.allMatches(html))
        if (m[1] == country) m[2]!
    }.toList();

/// Summit rows of a region.jsp page.
List<({int key, String num, String name, int altM})> parseHemaRegionRows(String html) => [
      for (final m in _hemaRow.allMatches(html))
        (
          key: int.parse(m[1]!),
          num: m[2]!,
          name: _unHtml(m[3]!) == 'NoNameFound' ? '' : _unHtml(m[3]!), // upstream placeholder
          altM: int.parse(m[4]!),
        ),
    ];

/// summitKey → position from a mapping.jsp page.
Map<int, ({double lat, double lon})> parseHemaMarkers(String html) {
  final out = <int, ({double lat, double lon})>{};
  for (final m in _hemaMarker.allMatches(html)) {
    final lat = _d(m[1]), lon = _d(m[2]);
    if (_validCoord(lat, lon)) out[int.parse(m[3]!)] = (lat: lat!, lon: lon!);
  }
  return out;
}
