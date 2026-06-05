import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/palette.dart';
import '../utils/anchor_math.dart';

/// Custom painters for the dashboard's compass / bearing visuals. Each is a pure
/// renderer: it receives everything it draws via its constructor and holds no
/// reference to the screen state. Colours come from the [Palette] constants so the
/// pure-red night rule still holds.

/// Hold-to-clear progress ring drawn around the MOB / nav waypoint card border.
/// [progress] 0 → 1 fills the rounded-rectangle border clockwise.
class WptBorderPainter extends CustomPainter {
  final double progress;
  final bool dayMode;
  const WptBorderPainter(this.progress, {required this.dayMode});

  static const _trackWidth = 1.5;
  static const _arcWidth = 5.5;
  static const _borderRadius = Radius.circular(6.0);

  @override
  void paint(Canvas canvas, Size size) {
    const inset = _arcWidth / 2 + 1.0;
    final rrect = RRect.fromLTRBR(
        inset, inset, size.width - inset, size.height - inset, _borderRadius);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _trackWidth
        ..color = progress > 0
            ? (dayMode ? kDEmgRing    : kNEmgRing)
            : (dayMode ? kDEmgRingDim : kNEmgRingDim),
    );

    if (progress <= 0) return;

    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final arc = metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));

    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _arcWidth
        ..color = dayMode
            ? Color.lerp(kDEmg, kDEmgArc, progress)!
            : Color.lerp(kN2,   kNEmgArc, progress)!
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(WptBorderPainter old) =>
      old.progress != progress || old.dayMode != dayMode;
}

// ── Bearing ring ──────────────────────────────────────────────────────────────
//
// Drawn behind the heading arrows. Shows coloured dots at the relative bearing
// of each POI so the user can immediately tell "is the city ahead? left? right?"
// without reading the absolute bearing number.
//
//   dot at 12 o'clock → POI is directly ahead
//   dot at 3 o'clock  → POI is 90° to the right
//   dot at 6 o'clock  → POI is directly behind
//
// A small tick at the top marks "ahead" as the reference.
// The ring itself is very dim — it provides context without cluttering the display.

class BearingRingPainter extends CustomPainter {
  final double primaryHeading;
  final List<({double bearingDeg, Color color, double sizeScale})> markers;
  final bool dayMode;
  final bool windRoseMode;
  final double? secondaryBearing; // shown as a dash in wind-rose mode
  final Color secondaryColor;

  BearingRingPainter({
    required this.primaryHeading,
    required this.markers,
    required this.dayMode,
    this.windRoseMode = false,
    this.secondaryBearing,
    this.secondaryColor = kDFg0,
  });

  static const _ringR   = 37.5;
  static const _dotR    = 3.5;
  static const _glowR   = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (markers.isEmpty && !windRoseMode) return;

    final cx = size.width  / 2;
    final cy = size.height / 2;

    final ringBase = dayMode ? kDFg0 : kN2;
    // Wind-rose: high contrast in bright sunlight; arrow mode: matches city-card ring style.
    final ringAlpha = windRoseMode ? (dayMode ? 0.70 : 0.78) : (dayMode ? 0.20 : 0.28);
    final ringColor = ringBase.withValues(alpha: ringAlpha);

    // ── Ring ─────────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(cx, cy), _ringR,
        Paint()..color = ringColor..style = PaintingStyle.stroke
               ..strokeWidth = windRoseMode ? 2.0 : 1.0);

    // ── Wind-rose mode: rotating cardinal/intercardinal tick marks ────────
    if (windRoseMode) {
      for (int i = 0; i < 8; i++) {
        final cardBearing = i * 45.0;
        final rel   = (cardBearing - primaryHeading + 360) % 360;
        final angle = rel * _piOver180 - _halfPi;
        final isCardinal = i % 2 == 0;

        if (i == 0) {
          // North — most prominent marker on the ring.
          // A thick colored arc on the ring plus an inward pointer tick.
          // The arc (unlike a thin tick) is visible in direct sunlight.
          final nColor = dayMode ? kDEmg : kN0;
          const arcHalfSpan = 0.32; // ~18° each side → ~36° total arc
          canvas.drawArc(
            Rect.fromLTWH(cx - _ringR, cy - _ringR, _ringR * 2, _ringR * 2),
            angle - arcHalfSpan,
            arcHalfSpan * 2,
            false,
            Paint()
              ..color = nColor
              ..strokeWidth = 5.5
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );
          // Inward pointer from the arc
          canvas.drawLine(
            Offset(cx + _ringR * _cos(angle), cy + _ringR * _sin(angle)),
            Offset(cx + (_ringR - 13) * _cos(angle), cy + (_ringR - 13) * _sin(angle)),
            Paint()..color = nColor..strokeWidth = 3.0..strokeCap = StrokeCap.round,
          );
          // "N" label at tip of pointer
          final lx = cx + (_ringR - 22) * _cos(angle);
          final ly = cy + (_ringR - 22) * _sin(angle);
          final nPainter = TextPainter(
            text: TextSpan(text: 'N', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w900, color: nColor,
            )),
            textDirection: TextDirection.ltr,
          )..layout();
          nPainter.paint(canvas,
              Offset(lx - nPainter.width / 2, ly - nPainter.height / 2));
        } else {
          // Other cardinals/intercardinals — larger and brighter than before.
          final tLen  = isCardinal ? 9.0 : 7.0;
          final tW    = isCardinal ? 2.8 : 1.6;
          final alpha = isCardinal ? (dayMode ? 0.80 : 0.88) : (dayMode ? 0.55 : 0.65);
          canvas.drawLine(
            Offset(cx + _ringR * _cos(angle), cy + _ringR * _sin(angle)),
            Offset(cx + (_ringR - tLen) * _cos(angle), cy + (_ringR - tLen) * _sin(angle)),
            Paint()..color = ringBase.withValues(alpha: alpha)..strokeWidth = tW..strokeCap = StrokeCap.round,
          );
        }
      }

      // Secondary bearing: prominent inward dash (clearly distinct from dots)
      if (secondaryBearing != null) {
        final rel   = (secondaryBearing! - primaryHeading + 360) % 360;
        final angle = rel * _piOver180 - _halfPi;
        // Outer glow for visibility
        canvas.drawLine(
          Offset(cx + (_ringR + 2) * _cos(angle), cy + (_ringR + 2) * _sin(angle)),
          Offset(cx + (_ringR - 11) * _cos(angle), cy + (_ringR - 11) * _sin(angle)),
          Paint()
            ..color = secondaryColor.withValues(alpha: 0.25)
            ..strokeWidth = 7.0
            ..strokeCap = StrokeCap.round,
        );
        // Main dash
        canvas.drawLine(
          Offset(cx + (_ringR + 1) * _cos(angle), cy + (_ringR + 1) * _sin(angle)),
          Offset(cx + (_ringR - 10) * _cos(angle), cy + (_ringR - 10) * _sin(angle)),
          Paint()
            ..color = secondaryColor.withValues(alpha: 0.85)
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round,
        );
      }
    } else {
      // Arrow mode: 4-tick crosshair at N / E / S / W (absolute, matching the
      // city/waypoint/MOB rings so the heading ring looks visually consistent).
      for (int q = 0; q < 4; q++) {
        final a = q * math.pi / 2 - _halfPi; // 12, 3, 6, 9 o'clock
        canvas.drawLine(
          Offset(cx + _ringR * _cos(a), cy + _ringR * _sin(a)),
          Offset(cx + (_ringR - 4.5) * _cos(a), cy + (_ringR - 4.5) * _sin(a)),
          Paint()
            ..color = ringBase.withValues(alpha: dayMode ? 0.32 : 0.42)
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // ── Heading cursor — fixed triangle at 12 o'clock (wind-rose only) ───
    // Always points toward the top of the ring = the direction the user is heading.
    // Drawn before POI dots so dots appear on top.
    if (windRoseMode) {
      // Triangle: base on ring at top, tip inward — indicates heading direction.
      // cx at top = (cx, cy - _ringR). tip 9px inward from ring.
      final hColor = dayMode
          ? kDFg0.withValues(alpha: 0.85)
          : kN1.withValues(alpha: 0.85);
      final hPath = Path()
        ..moveTo(cx, cy - (_ringR - 9))       // tip (inward)
        ..lineTo(cx - 5, cy - _ringR)          // base left
        ..lineTo(cx + 5, cy - _ringR)          // base right
        ..close();
      canvas.drawPath(hPath, Paint()..color = hColor..style = PaintingStyle.fill);
    }

    // ── POI dots ─────────────────────────────────────────────────────────
    // Wind-rose: relative to heading (heading = 12 o'clock).
    // Arrow mode: absolute (North = 12 o'clock) — consistent with the absolute arrow.
    for (final m in markers) {
      final rel   = windRoseMode
          ? (m.bearingDeg - primaryHeading + 360) % 360
          : m.bearingDeg;
      final angle = rel * _piOver180 - _halfPi;
      final dx    = cx + _ringR * _cos(angle);
      final dy    = cy + _ringR * _sin(angle);
      // Glow
      canvas.drawCircle(Offset(dx, dy), _glowR * m.sizeScale,
          Paint()..color = m.color.withValues(alpha: 0.28)..style = PaintingStyle.fill);
      // Dot
      canvas.drawCircle(Offset(dx, dy), _dotR * m.sizeScale,
          Paint()..color = m.color..style = PaintingStyle.fill);
      // Emergency (MOB) gets a bright outline so it pops over any background.
      if (m.sizeScale > 1.3) {
        canvas.drawCircle(Offset(dx, dy), _dotR * m.sizeScale + 1.5,
            Paint()
              ..color = (dayMode ? kDFg0 : kN0).withValues(alpha: 0.65)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }
  }

  static const _halfPi    = 1.5707963267948966;
  static const _piOver180 = 0.017453292519943295;
  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(BearingRingPainter old) {
    if (old.primaryHeading != primaryHeading) return true;
    if (old.dayMode != dayMode) return true;
    if (old.windRoseMode != windRoseMode) return true;
    if (old.secondaryBearing != secondaryBearing) return true;
    if (old.secondaryColor != secondaryColor) return true;
    if (old.markers.length != markers.length) return true;
    // Check per-marker bearing and color — bearing changes when user moves.
    for (int i = 0; i < markers.length; i++) {
      if (old.markers[i].bearingDeg != markers[i].bearingDeg) return true;
      if (old.markers[i].color != markers[i].color) return true;
    }
    return false;
  }
}

// ── Relative bearing dot ring ─────────────────────────────────────────────────
//
// Drawn around an ArrowWidget in the city / waypoint / MOB cards.
// The arrow shows the ABSOLUTE bearing to the POI; this ring shows the bearing
// RELATIVE to the current heading — at a glance you can see whether the POI is
// ahead (12 o'clock), to the right (3 o'clock), behind (6 o'clock), etc.
//
// The ring shares the same size as the ArrowWidget it wraps; no extra space needed.

class RelativeDotRingPainter extends CustomPainter {
  final double relBearing; // 0 = ahead, 90 = right, 180 = behind, 270 = left
  final Color color;
  final bool dayMode;

  const RelativeDotRingPainter({
    required this.relBearing,
    required this.color,
    required this.dayMode,
  });

  static const _halfPi    = 1.5707963267948966;
  static const _piOver180 = 0.017453292519943295;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = size.width  / 2 - 3.0; // ring just inside widget bounds

    // Thin reference ring
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()
          ..color = color.withValues(alpha: dayMode ? 0.18 : 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    // Four small ticks at ahead / right / behind / left
    for (int q = 0; q < 4; q++) {
      final a = q * math.pi / 2 - _halfPi;
      canvas.drawLine(
        Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
        Offset(cx + (r - 3.5) * math.cos(a), cy + (r - 3.5) * math.sin(a)),
        Paint()
          ..color = color.withValues(alpha: dayMode ? 0.28 : 0.33)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Relative-bearing dot
    final angle = relBearing * _piOver180 - _halfPi;
    final dx = cx + r * math.cos(angle);
    final dy = cy + r * math.sin(angle);
    // Glow
    canvas.drawCircle(Offset(dx, dy), 5.0,
        Paint()..color = color.withValues(alpha: 0.28)..style = PaintingStyle.fill);
    // Dot
    canvas.drawCircle(Offset(dx, dy), 3.5,
        Paint()..color = color..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(RelativeDotRingPainter old) =>
      old.relBearing != relBearing ||
      old.color      != color      ||
      old.dayMode    != dayMode;
}

// ── Anchor radius progress ring ───────────────────────────────────────────────
// Drawn inside the anchor card behind the bearing arrow.
// frac = 0 (at anchor) → 1 (at boundary) → >1 (outside — alarm).
class AnchorProgressPainter extends CustomPainter {
  final double frac;
  final Color color;
  final AnchorAlarmLevel level;
  const AnchorProgressPainter(this.frac, this.color, this.level);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2 - 3.0;

    // Background track ring
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0);

    // Progress arc — fills clockwise from the top
    if (frac > 0) {
      canvas.drawArc(
        Rect.fromLTWH(cx - r, cy - r, r * 2, r * 2),
        -math.pi / 2,         // start at 12 o'clock
        2 * math.pi * frac.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color.withValues(alpha: frac >= 1.0 ? 0.9 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(AnchorProgressPainter old) =>
      old.frac != frac || old.color != color || old.level != level;
}
