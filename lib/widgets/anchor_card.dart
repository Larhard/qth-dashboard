import 'package:flutter/material.dart';
import '../services/anchor_service.dart';
import '../theme/palette.dart';
import 'compass_painters.dart';
import 'rel_bearing_arrow.dart';

/// The anchor-watch status card shown in the adaptive secondary zone while an
/// anchor is deployed: a bearing arrow with the radius progress ring, the current
/// status (RIDING / WARNING / OUTSIDE RADIUS / GPS lost), distance, bearing, and
/// the configured radius. Reads live data from the global [AnchorService].
class AnchorCard extends StatelessWidget {
  final bool dayMode;
  final bool portrait;
  final double heading; // current heading, for the relative-direction ring

  const AnchorCard({
    super.key,
    required this.dayMode,
    required this.portrait,
    required this.heading,
  });

  /// Status colour for an alarm level (also used by the floating-overlay line).
  static Color levelColor(Palette pal, AnchorAlarmLevel lvl) => switch (lvl) {
        AnchorAlarmLevel.alarm => pal.emergency,
        AnchorAlarmLevel.warning => pal.stale,
        AnchorAlarmLevel.idle => pal.pick(kDPort, kN2),
      };

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(dayMode);
    final svc = AnchorService.instance;
    final dist = svc.distanceM ?? 0.0;
    final brg = svc.bearingDeg ?? 0.0;
    final r = svc.radiusM;
    final lvl = svc.level;
    final color = levelColor(pal, lvl);
    final frac = (dist / r).clamp(0.0, 1.2);

    final arrowSz = portrait ? 50.0 : 38.0;
    final distFont = portrait ? 20.0 : 16.0;
    final labelFont = portrait ? 11.0 : 10.0;

    // Status label
    final String status;
    if (svc.gpsLost) {
      status = 'GPS lost ${svc.gpsLossSeconds}s';
    } else {
      status = switch (lvl) {
        AnchorAlarmLevel.alarm => 'OUTSIDE RADIUS',
        AnchorAlarmLevel.warning => 'WARNING',
        AnchorAlarmLevel.idle => 'RIDING',
      };
    }

    return Padding(
      padding: EdgeInsets.all(portrait ? 3 : 2),
      child: Container(
        padding: EdgeInsets.fromLTRB(
            portrait ? 12 : 8, portrait ? 8 : 5,
            portrait ? 12 : 8, portrait ? 8 : 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          // Arrow with relative ring + progress ring overlay
          SizedBox(
            width: arrowSz, height: arrowSz,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(child: CustomPaint(
                painter: AnchorProgressPainter(frac, color, lvl),
              )),
              RelBearingArrow(
                bearingDeg: brg, heading: heading, color: color,
                size: arrowSz * 0.7, dayMode: dayMode),
            ]),
          ),
          SizedBox(width: portrait ? 12 : 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.anchor, size: labelFont + 2, color: color),
                const SizedBox(width: 4),
                Text(status, style: TextStyle(
                    fontSize: labelFont, color: color,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ]),
              Row(children: [
                Text('${dist.round()} m',
                    style: TextStyle(fontSize: distFont, fontWeight: FontWeight.w700,
                        color: color, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                Text('${brg.round()}°',
                    style: TextStyle(fontSize: distFont * 0.8, color: color.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              Text('radius ${r.round()} m · warn ${svc.warningRadiusM.round()} m',
                  style: TextStyle(fontSize: labelFont, color: color.withValues(alpha: 0.65))),
            ],
          )),
          // Muted indicator (alarm is acknowledged but anchor still deployed).
          if (svc.isMuted)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.volume_off, color: color.withValues(alpha: 0.6), size: 18),
            ),
        ]),
      ),
    );
  }
}
