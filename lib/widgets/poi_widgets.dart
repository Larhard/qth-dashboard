import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;

import '../models/poi_category.dart';
import '../models/poi_hit.dart';
import '../refdata/activation_rules.dart';
import '../theme/palette.dart';

/// Small outlined category tag ("SOTA", "PORT", …) in the category colour.
class PoiTag extends StatelessWidget {
  final PoiCategory category;
  final bool dayMode;
  final double fontSize;
  const PoiTag(this.category, {super.key, required this.dayMode, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(dayMode).poi(category);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.45, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.8), width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(category.tag,
          style: TextStyle(
              fontSize: fontSize, color: c, fontWeight: FontWeight.w800, letterSpacing: 1)),
    );
  }
}

/// Activation essentials as compact pictograms:
///   🏆-style points (+ ❄ winter bonus) · zone (↕ 25 m / inside / island) ·
///   GPS estimate (Δ −12 m ✓) · QSOs needed (💬 4).
/// All glyphs are Material icons tinted with the text colour — emoji would ignore
/// the colour and break the pure-red night rule.
class RefRuleChips extends StatelessWidget {
  final PoiHit hit;
  final bool dayMode;
  final double fontSize;

  /// Live GPS fix (MSL altitude + position) for the zone estimate; optional.
  final Position? position;

  const RefRuleChips({
    super.key,
    required this.hit,
    required this.dayMode,
    this.fontSize = 13,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    final ref = hit.ref!;
    final rule = ruleFor(hit.category, hit.ref?.ref);
    final pal = Palette.of(dayMode);
    final color = pal.poiSub(hit.category);
    final strong = pal.poi(hit.category);
    final icon = fontSize + 2;

    Widget chip(IconData i, String text, {Color? c}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i, size: icon, color: c ?? color),
            const SizedBox(width: 2),
            Text(text,
                style: TextStyle(
                    fontSize: fontSize,
                    color: c ?? color,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        );

    final chips = <Widget>[
      if (ref.points > 0) chip(Icons.emoji_events_outlined, '${ref.points}'),
      if (ref.bonus > 0) chip(Icons.ac_unit, '+${ref.bonus}'),
      if (rule != null) ...switch (rule.zone) {
        ZoneKind.vertical => [chip(Icons.height, '${rule.zoneMeters} m')],
        ZoneKind.radius => [chip(Icons.radar, _metres(rule.zoneMeters))],
        ZoneKind.insideArea => [chip(Icons.crop_free, 'inside')],
        ZoneKind.onIsland => [chip(Icons.waves, 'island')],
        ZoneKind.unknown => [chip(Icons.help_outline, 'rules')],
      },
      ..._estimate(rule, ref.altM, strong, chip),
      if (rule?.minQsos != null)
        chip(Icons.forum_outlined, '${rule!.minQsos}${rule.cumulative ? ' Σ' : ''}'),
    ];
    return Wrap(spacing: fontSize * 0.8, runSpacing: 2, children: chips);
  }

  List<Widget> _estimate(ActivationRule? rule, int altM, Color strong,
      Widget Function(IconData, String, {Color? c}) chip) {
    final p = position;
    if (rule == null || p == null) return const [];
    if (rule.zone == ZoneKind.vertical) {
      final e = estimateVerticalZone(
          summitAltM: altM, gpsAltM: p.altitude, distKm: hit.distKm, zoneMeters: rule.zoneMeters);
      if (e == null) return const [];
      final d = e.deltaM.round();
      return [
        chip(e.likelyInZone ? Icons.check_circle_outline : Icons.north,
            'Δ${d >= 0 ? '+' : '−'}${d.abs()} m', c: e.likelyInZone ? strong : null),
      ];
    }
    if (inRadiusZone(rule, hit.distKm) == true) {
      return [chip(Icons.check_circle_outline, 'in zone', c: strong)];
    }
    if (rule.zone == ZoneKind.onIsland) {
      final box = hit.ref!.bbox;
      if (box != null && _inBox(p.latitude, p.longitude, box)) {
        return [chip(Icons.check_circle_outline, 'in area', c: strong)];
      }
    }
    return const [];
  }

  static bool _inBox(double lat, double lon,
      ({double latMin, double latMax, double lonMin, double lonMax}) b) {
    final latLo = b.latMin < b.latMax ? b.latMin : b.latMax;
    final latHi = b.latMin < b.latMax ? b.latMax : b.latMin;
    if (lat < latLo || lat > latHi) return false;
    return b.lonMin <= b.lonMax
        ? lon >= b.lonMin && lon <= b.lonMax
        : lon >= b.lonMin || lon <= b.lonMax; // crosses the antimeridian
  }

  static String _metres(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km' : '$m m';
}
