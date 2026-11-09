import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/services/poi_service.dart';
import 'package:qth_dashboard/models/ham_ref.dart';
import 'package:qth_dashboard/models/poi_category.dart';
import 'package:qth_dashboard/refdata/activation_rules.dart';
import 'package:qth_dashboard/refdata/ref_table.dart';
import 'package:qth_dashboard/utils/geo_utils.dart';

RefTable _table(List<(double, double)> pts) => RefTable.fromColumns(
      [for (var i = 0; i < pts.length; i++) 'R$i\tn$i\t${pts[i].$1}\t${pts[i].$2}\t0\t0\t0\t'],
      Float64List.fromList([for (final p in pts) p.$1]),
      Float64List.fromList([for (final p in pts) p.$2]),
    );

List<int> _brute(List<(double, double)> pts, double lat, double lon, int k) {
  final idx = List<int>.generate(pts.length, (i) => i)
    ..sort((a, b) => haversineKm(lat, lon, pts[a].$1, pts[a].$2)
        .compareTo(haversineKm(lat, lon, pts[b].$1, pts[b].$2)));
  return idx.take(k).toList();
}

void main() {
  group('RefTable spatial search', () {
    final rnd = Random(42);
    // Dense cluster in Europe + sparse world-wide points + Pacific dateline points.
    final pts = <(double, double)>[
      for (var i = 0; i < 4000; i++) (45 + rnd.nextDouble() * 10, 5 + rnd.nextDouble() * 20),
      for (var i = 0; i < 400; i++) (-80 + rnd.nextDouble() * 160, -180 + rnd.nextDouble() * 360),
      (-17.0, 179.8), (-17.1, -179.9), (65.0, 179.5), (65.1, -179.6),
    ];
    final t = _table(pts);

    test('nearestK equals brute force for many random queries', () {
      for (var q = 0; q < 120; q++) {
        final lat = -85 + rnd.nextDouble() * 170, lon = -180 + rnd.nextDouble() * 360;
        final got = t.nearestK(lat, lon, 5).map((h) => h.index).toList();
        expect(got, _brute(pts, lat, lon, 5), reason: 'query ($lat, $lon)');
      }
    });

    test('finds neighbours across the antimeridian', () {
      // Query just west of 180°: the closest point is just east of it (lon -179.9).
      final hit = t.nearest(-17.1, 179.95)!;
      expect(pts[hit.index], (-17.1, -179.9));
    });

    test('high-latitude queries stay exact', () {
      expect(t.nearestK(65.05, -179.99, 2).map((h) => h.index).toList(),
          _brute(pts, 65.05, -179.99, 2));
    });

    test('nearest distance matches haversine and lines decode', () {
      final hit = t.nearest(50, 10)!;
      expect(hit.distKm, closeTo(haversineKm(50, 10, pts[hit.index].$1, pts[hit.index].$2), 1e-9));
      expect(t.row(hit.index).ref, 'R${hit.index}');
    });

    test('empty table and k larger than the table', () {
      expect(_table(const []).nearest(0, 0), isNull);
      expect(_table(const [(1.0, 1.0), (2.0, 2.0)]).nearestK(0, 0, 10), hasLength(2));
    });

    test('fromTsv reads a normalized file and its header', () {
      final text = encodeRefFile('pota', DateTime(2026, 1, 2), const [
        HamRef(ref: 'US-0001', name: 'Acadia', lat: 44.31, lon: -68.2034),
        HamRef(ref: 'US-0002', name: 'Alagnak', lat: 59.0908, lon: -156.463),
      ]);
      final tt = RefTable.fromTsv(text);
      expect(tt.length, 2);
      expect(tt.header!.count, 2);
      expect(tt.row(tt.nearest(44, -68)!.index).name, 'Acadia');
    });
  });

  group('activation rules', () {
    test('every reference program has a rule entry', () {
      for (final c in PoiCategory.references) {
        expect(activationRules[c], isNotNull, reason: '${c.id} has no activation rule');
      }
    });

    test('SOTA: 25 m vertical zone, 4 QSOs, points', () {
      final r = activationRules[PoiCategory.sota]!;
      expect(r.zone, ZoneKind.vertical);
      expect(r.zoneMeters, 25);
      expect(r.minQsos, 4);
      expect(r.hasPoints, isTrue);
    });

    test('vertical-zone estimate: inside, below, too far, no altitude', () {
      final inside = estimateVerticalZone(summitAltM: 1310, gpsAltM: 1295, distKm: 0.2, zoneMeters: 25)!;
      expect(inside.deltaM, -15);
      expect(inside.likelyInZone, isTrue);
      final below = estimateVerticalZone(summitAltM: 1310, gpsAltM: 1250, distKm: 0.8, zoneMeters: 25)!;
      expect(below.likelyInZone, isFalse);
      expect(estimateVerticalZone(summitAltM: 1310, gpsAltM: 1400, distKm: 12, zoneMeters: 25), isNull,
          reason: 'being high on another hill must not count');
      expect(estimateVerticalZone(summitAltM: 0, gpsAltM: 900, distKm: 0.1, zoneMeters: 25), isNull);
      expect(estimateVerticalZone(summitAltM: 900, gpsAltM: 0, distKm: 0.1, zoneMeters: 25), isNull);
    });
  });

  test('shared ref-data layer stays Flutter-free (the build tool imports it)', () {
    // tool/fetch_refs.dart runs on the plain Dart VM, which has no dart:ui.
    for (final dir in ['lib/models', 'lib/refdata', 'lib/config']) {
      for (final f in Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(f.readAsStringSync(), isNot(contains('package:flutter')),
            reason: '${f.path} imports Flutter but is shared with tool/fetch_refs.dart');
      }
    }
  });

  test('radius-zone check: point objects only, not LLOTA (measured from shore)', () {
    final bota = activationRules[PoiCategory.bota]!;
    expect(inRadiusZone(bota, 0.9), isTrue);
    expect(inRadiusZone(bota, 1.2), isFalse);
    expect(inRadiusZone(activationRules[PoiCategory.llota]!, 0.05), isNull);
    expect(inRadiusZone(activationRules[PoiCategory.sota]!, 0.0), isNull);
  });

  group('POI long-press cycling', () {
    const a = PoiCategory.cityLarge, b = PoiCategory.sota, c = PoiCategory.pota;
    test('advances and wraps', () {
      expect(PoiService.nextActive([a, b, c], a), b);
      expect(PoiService.nextActive([a, b, c], c), a);
    });
    test('current no longer enabled → first active', () {
      expect(PoiService.nextActive([b, c], a), b);
    });
    test('nothing enabled → null', () {
      expect(PoiService.nextActive([], a), isNull);
    });
  });
}
