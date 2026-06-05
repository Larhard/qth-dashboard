import 'package:flutter/material.dart';
import 'arrow_widget.dart';
import 'compass_painters.dart';

/// A bearing [ArrowWidget] wrapped in a [RelativeDotRingPainter] ring. The arrow
/// points to the ABSOLUTE bearing of a POI; the ring's dot shows that bearing
/// RELATIVE to the current [heading] (ahead = 12 o'clock). Used by the city, nav,
/// MOB, and anchor cards.
class RelBearingArrow extends StatelessWidget {
  final double bearingDeg;
  final double heading;
  final Color color;
  final double size;
  final bool dayMode;

  const RelBearingArrow({
    super.key,
    required this.bearingDeg,
    required this.heading,
    required this.color,
    required this.size,
    required this.dayMode,
  });

  @override
  Widget build(BuildContext context) {
    final relBearing = (bearingDeg - heading + 360) % 360;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RelativeDotRingPainter(
                relBearing: relBearing,
                color: color,
                dayMode: dayMode,
              ),
            ),
          ),
          ArrowWidget(bearingDeg: bearingDeg, color: color, size: size),
        ],
      ),
    );
  }
}
