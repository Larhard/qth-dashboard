import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/settings/display_settings.dart';
import 'package:qth_dashboard/utils/heading_source.dart';

void main() {
  group('gpsHeadingUsable', () {
    test('usable when moving fast enough with a valid course', () {
      expect(gpsHeadingUsable(5.0, 90.0), isTrue);
      expect(gpsHeadingUsable(1.5, 0.0), isTrue); // exactly at the threshold
    });
    test('not usable below the speed threshold', () {
      expect(gpsHeadingUsable(1.0, 90.0), isFalse);
      expect(gpsHeadingUsable(0.0, 90.0), isFalse);
    });
    test('not usable with an invalid course', () {
      expect(gpsHeadingUsable(5.0, double.nan), isFalse);
      expect(gpsHeadingUsable(5.0, -1.0), isFalse);
    });
  });

  group('chooseHeadingSource', () {
    test('magOnly: MAG is primary and data is always present', () {
      final c = chooseHeadingSource(
          mode: HeadingSourceMode.magOnly, gpsUsable: false, trkAvailable: false);
      expect(c.computed, HeadingSource.mag);
      expect(c.display, HeadingSource.mag);
      expect(c.hasData, isTrue);
      expect(c.usingGps, isFalse);
    });

    test('auto + GPS usable → GPS for both value and display', () {
      final c = chooseHeadingSource(
          mode: HeadingSourceMode.auto, gpsUsable: true, trkAvailable: true);
      expect(c.computed, HeadingSource.gps);
      expect(c.display, HeadingSource.gps);
      expect(c.hasData, isTrue);
      expect(c.usingGps, isTrue);
    });

    test('auto + no GPS but TRK available → TRK', () {
      final c = chooseHeadingSource(
          mode: HeadingSourceMode.auto, gpsUsable: false, trkAvailable: true);
      expect(c.computed, HeadingSource.trk);
      expect(c.display, HeadingSource.trk);
      expect(c.hasData, isTrue);
      expect(c.usingGps, isTrue);
    });

    test('auto + no data: HONEST waiting state — MAG drives the live arrow, '
        'display reads TRK, value is "---" (hasData=false)', () {
      final c = chooseHeadingSource(
          mode: HeadingSourceMode.auto, gpsUsable: false, trkAvailable: false);
      expect(c.computed, HeadingSource.mag, reason: 'live arrow keeps moving via compass');
      expect(c.display, HeadingSource.trk, reason: 'never silently shows MAG in auto');
      expect(c.hasData, isFalse, reason: 'so the degree readout shows ---');
      expect(c.usingGps, isFalse);
    });
  });

  group('HeadingSource labels', () {
    test('map to the on-screen source tags', () {
      expect(HeadingSource.gps.label, 'GPS');
      expect(HeadingSource.trk.label, 'TRK');
      expect(HeadingSource.mag.label, 'MAG');
    });
  });
}
