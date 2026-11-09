import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/models/poi_category.dart';
import 'package:qth_dashboard/theme/palette.dart';

/// Returns true when a colour is "pure red or black": green and blue channels
/// are both zero (it lies on the line #000000 → #FF0000).
bool _pureRedOrBlack(Color c) {
  final argb = c.toARGB32();
  final green = (argb >> 8) & 0xFF;
  final blue = argb & 0xFF;
  return green == 0 && blue == 0;
}

void main() {
  // The single most important UI invariant (constitution §4): night mode emits
  // ONLY long-wavelength red light, so it never destroys night-adapted vision.
  // Any green/blue leak is a safety bug — this test fails the build if one appears.
  group('night palette is STRICT pure red (g=0, b=0)', () {
    const nightConstants = <String, Color>{
      'kN0': kN0, 'kN1': kN1, 'kN2': kN2, 'kN3': kN3, 'kN4': kN4,
      'kNBg': kNBg, 'kNDiv': kNDiv, 'kNSheet': kNSheet,
      'kNEmgRing': kNEmgRing, 'kNEmgRingDim': kNEmgRingDim, 'kNEmgArc': kNEmgArc,
    };
    nightConstants.forEach((name, c) {
      test('$name has no green/blue channel', () {
        expect(_pureRedOrBlack(c), isTrue,
            reason: '$name = ${c.toARGB32().toRadixString(16)} leaks green/blue light');
      });
    });

    test('every Palette night-mode role resolves to pure red or black', () {
      const p = Palette(false); // night
      final roles = <String, Color>{
        'textPrimary': p.textPrimary, 'textSecondary': p.textSecondary,
        'textTertiary': p.textTertiary, 'textDim': p.textDim, 'textFaint': p.textFaint,
        'gps': p.gps, 'gpsLabel': p.gpsLabel, 'trk': p.trk, 'emergency': p.emergency,
        'nav': p.nav, 'navLabel': p.navLabel, 'stale': p.stale,
        'amber': p.amber, 'amberLabel': p.amberLabel, 'port': p.port, 'portLabel': p.portLabel,
        'tileBg': p.tileBg, 'cardBg': p.cardBg, 'sheetBg': p.sheetBg, 'snackBg': p.snackBg,
        'divider': p.divider, 'border': p.border, 'focus': p.focus,
        'rippleMuted': p.rippleMuted,
        'ringIdle': p.ringIdle, 'ringActive': p.ringActive, 'ringArc': p.ringArc,
        // Nearby-POI category colours (every city tier and ham program).
        for (final c in PoiCategory.values) ...{
          'poi(${c.id})': p.poi(c),
          'poiSub(${c.id})': p.poiSub(c),
        },
      };
      final leaks = roles.entries
          .where((e) => !_pureRedOrBlack(e.value))
          .map((e) => e.key)
          .toList();
      expect(leaks, isEmpty,
          reason: 'these night roles leak green/blue light: $leaks');
    });
  });

  test('every POI category has a distinct day colour', () {
    const p = Palette(true);
    final colours = {for (final c in PoiCategory.values) p.poi(c).toARGB32()};
    expect(colours.length, PoiCategory.values.length);
  });

  group('Palette resolver behaviour', () {
    test('Palette.of selects the right mode', () {
      expect(Palette.of(true).day, isTrue);
      expect(Palette.of(false).day, isFalse);
    });

    test('Palette.of is allocation-free (returns const singletons)', () {
      expect(identical(Palette.of(true), Palette.of(true)), isTrue);
      expect(identical(Palette.of(false), Palette.of(false)), isTrue);
    });

    test('pick() returns the day colour in day mode, night colour at night', () {
      expect(Palette.of(true).pick(kDGps, kN1), kDGps);
      expect(Palette.of(false).pick(kDGps, kN1), kN1);
    });

    test('day-mode roles use the semantic day palette', () {
      const p = Palette(true);
      expect(p.emergency, kDEmg);
      expect(p.gps, kDGps);
      expect(p.tileBg, Colors.black);
    });
  });
}
